//
// voxema_llm_gguf.mm  —  Real llama.cpp implementation of the voxema_llm.h C bridge.
//
// Replaces voxema_llm_stub.c. Do NOT compile both files in the same target.
//
// Inference strategy:
//   - Metal GPU offload (n_gpu_layers = 99, falls back automatically when VRAM is low)
//   - top-p 0.9 + temperature 0.7 sampler — balanced quality/diversity for meeting notes
//   - Greedy EOS detection via llama_vocab_is_eog
//
// Thread safety: each VoxemaLLMContext is single-threaded; callers must not share
// contexts across threads.
//

#include "include/voxema_llm.h"
#include <llama.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>

// MARK: - Context

struct VoxemaLLMContext {
    struct llama_model   * model;
    struct llama_context * ctx;
};

// MARK: - voxema_llm_init

VoxemaLLMContext * voxema_llm_init(const char * model_path, int n_ctx) {
    if (!model_path || n_ctx < 128) return NULL;

    llama_model_params mparams = llama_model_default_params();
    mparams.n_gpu_layers = 99; // offload all layers to Metal; ignored on non-Metal builds

    struct llama_model * model = llama_model_load_from_file(model_path, mparams);
    if (!model) return NULL;

    llama_context_params cparams = llama_context_default_params();
    cparams.n_ctx   = (uint32_t)n_ctx;
    cparams.n_batch = 512;

    struct llama_context * ctx = llama_init_from_model(model, cparams);
    if (!ctx) {
        llama_model_free(model);
        return NULL;
    }

    VoxemaLLMContext * vctx = (VoxemaLLMContext *)malloc(sizeof(VoxemaLLMContext));
    if (!vctx) {
        llama_free(ctx);
        llama_model_free(model);
        return NULL;
    }
    vctx->model = model;
    vctx->ctx   = ctx;
    return vctx;
}

// MARK: - voxema_llm_free

void voxema_llm_free(VoxemaLLMContext * vctx) {
    if (!vctx) return;
    if (vctx->ctx)   llama_free(vctx->ctx);
    if (vctx->model) llama_model_free(vctx->model);
    free(vctx);
}

// MARK: - voxema_llm_generate

int voxema_llm_generate(VoxemaLLMContext * vctx,
                        const char       * prompt,
                        char             * output_buf,
                        int                max_output_bytes,
                        int                max_new_tokens) {
    if (!vctx || !prompt || !output_buf || max_output_bytes < 2 || max_new_tokens < 1)
        return -1;

    output_buf[0] = '\0';
    const struct llama_vocab * vocab = llama_model_get_vocab(vctx->model);

    // ── Tokenize prompt ─────────────────────────────────────────────────────
    int32_t prompt_len = (int32_t)strlen(prompt);

    // First call with n_tokens_max=0 returns the negative token count needed.
    int n_prompt = -llama_tokenize(vocab, prompt, prompt_len, NULL, 0, /*add_special=*/true, /*parse_special=*/true);
    if (n_prompt <= 0) return -1;

    llama_token * tokens = (llama_token *)malloc((size_t)n_prompt * sizeof(llama_token));
    if (!tokens) return -1;

    int r = llama_tokenize(vocab, prompt, prompt_len, tokens, n_prompt, /*add_special=*/true, /*parse_special=*/true);
    if (r < 0) { free(tokens); return -1; }
    n_prompt = r;

    // ── Prefill (process prompt) ─────────────────────────────────────────────
    struct llama_batch batch = llama_batch_get_one(tokens, n_prompt);
    if (llama_decode(vctx->ctx, batch) != 0) {
        free(tokens);
        return -2;
    }
    free(tokens);

    // ── Sampler chain: top-p 0.9, temp 0.7, dist seed=42 ───────────────────
    struct llama_sampler_chain_params sparams = llama_sampler_chain_default_params();
    struct llama_sampler * smpl = llama_sampler_chain_init(sparams);
    llama_sampler_chain_add(smpl, llama_sampler_init_top_k(50));
    llama_sampler_chain_add(smpl, llama_sampler_init_top_p(0.9f, 1));
    llama_sampler_chain_add(smpl, llama_sampler_init_temp(0.7f));
    llama_sampler_chain_add(smpl, llama_sampler_init_dist(42));

    // ── Autoregressive decode ────────────────────────────────────────────────
    int output_len = 0;

    for (int i = 0; i < max_new_tokens; i++) {
        llama_token id = llama_sampler_sample(smpl, vctx->ctx, -1);

        if (llama_vocab_is_eog(vocab, id)) break;

        char piece[256];
        int piece_len = llama_token_to_piece(vocab, id, piece, (int32_t)sizeof(piece), 0, /*special=*/true);
        if (piece_len <= 0) break;

        if (output_len + piece_len >= max_output_bytes - 1) break;
        memcpy(output_buf + output_len, piece, (size_t)piece_len);
        output_len += piece_len;
        output_buf[output_len] = '\0';

        struct llama_batch next = llama_batch_get_one(&id, 1);
        if (llama_decode(vctx->ctx, next) != 0) break;
    }

    llama_sampler_free(smpl);
    return 0;
}
