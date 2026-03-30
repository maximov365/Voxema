//
// voxema_llm.h  —  Voxema domain-specific C bridge for local LLM inference via llama.cpp.
//
// Exposes a minimal 4-function API that hides llama.cpp internals from Swift.
// Input:  UTF-8 prompt string.
// Output: UTF-8 completion string written into a caller-allocated buffer.
//
// REPLACEMENT: Remove voxema_llm_stub.c and add the real llama.cpp-backed
// implementation when bundling a GGUF model. Swift wrapper (LocalProvider.swift)
// does NOT need to change.
//

#ifndef VOXEMA_LLM_H
#define VOXEMA_LLM_H

#ifdef __cplusplus
extern "C" {
#endif

/// Maximum bytes the output buffer must be able to hold.
#define VOXEMA_LLM_MAX_OUTPUT_BYTES 65536

/// Opaque context wrapping a llama.cpp model + inference session.
typedef struct VoxemaLLMContext VoxemaLLMContext;

// ── Context lifecycle ────────────────────────────────────────────────────────

/// Load a GGUF model from `model_path` with a context window of `n_ctx` tokens.
/// Returns NULL on failure (file not found, out of memory, incompatible model).
VoxemaLLMContext * voxema_llm_init(const char * model_path, int n_ctx);

/// Release all resources owned by the context.
void voxema_llm_free(VoxemaLLMContext * ctx);

// ── Inference ────────────────────────────────────────────────────────────────

/// Generate a completion for `prompt`.
///
/// - `ctx`            : valid context returned by voxema_llm_init
/// - `prompt`         : UTF-8 prompt string (null-terminated)
/// - `output_buf`     : caller-allocated buffer of at least `max_output_bytes` bytes
/// - `max_output_bytes`: buffer capacity (≤ VOXEMA_LLM_MAX_OUTPUT_BYTES recommended)
/// - `max_new_tokens` : maximum tokens to generate (≥ 1)
///
/// Returns 0 on success, -1 on invalid args, -2 on inference error.
/// On success, `output_buf` contains a null-terminated UTF-8 string.
int voxema_llm_generate(
    VoxemaLLMContext * ctx,
    const char       * prompt,
    char             * output_buf,
    int                max_output_bytes,
    int                max_new_tokens
);

#ifdef __cplusplus
}
#endif
#endif /* VOXEMA_LLM_H */
