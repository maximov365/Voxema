//
// voxema_llm_stub.c  —  No-op stub for the llama.cpp LLM bridge.
//
// Returns a minimal valid JSON meeting summary so that SummarizeStage and
// SummaryOutputParser can be exercised end-to-end without a real GGUF model.
//
// REPLACEMENT: Remove this file and add the real llama.cpp-backed implementation.
//
#include "include/voxema_llm.h"
#include <stdlib.h>
#include <string.h>

// Hard-coded stub response — valid JSON that SummaryOutputParser can parse.
static const char STUB_JSON[] =
    "{\"summary\":\"[Stub summary — replace with real llama.cpp inference.]\","
    "\"key_decisions\":[],"
    "\"action_items\":[],"
    "\"open_questions\":[]}";

struct VoxemaLLMContext {
    int _placeholder;
};

VoxemaLLMContext * voxema_llm_init(const char * model_path, int n_ctx) {
    (void)model_path; (void)n_ctx;
    VoxemaLLMContext * ctx = (VoxemaLLMContext *)malloc(sizeof(VoxemaLLMContext));
    if (ctx) ctx->_placeholder = 0;
    return ctx;
}

void voxema_llm_free(VoxemaLLMContext * ctx) {
    free(ctx);
}

int voxema_llm_generate(VoxemaLLMContext * ctx,
                        const char * prompt,
                        char * output_buf,
                        int max_output_bytes,
                        int max_new_tokens) {
    (void)ctx; (void)prompt; (void)max_new_tokens;
    if (!output_buf || max_output_bytes < 2) return -1;
    int len = (int)strlen(STUB_JSON);
    if (len >= max_output_bytes) len = max_output_bytes - 1;
    memcpy(output_buf, STUB_JSON, (size_t)len);
    output_buf[len] = '\0';
    return 0;
}
