//
// whisper_stub.c  —  No-op stub implementations of the whisper.cpp C API.
//
// PURPOSE: Enables Voxema to compile and run tests without the real whisper.cpp
// library.  All functions return empty/zero results.
//
// REPLACEMENT: When integrating real whisper.cpp, remove this file and either:
//   a) Add the real whisper.cpp + ggml source files to this C target, or
//   b) Swap the target for a .binaryTarget pointing to a pre-built xcframework.
//
// The Swift wrapper (WhisperEngine.swift) is unaffected by this swap.
//

#include "include/whisper.h"
#include <string.h>
#include <stdlib.h>

// Minimal opaque context — no real state in the stub.
struct whisper_context {
    int _placeholder;
};

whisper_context * whisper_init_from_file(const char * path_model) {
    (void)path_model;
    whisper_context * ctx = (whisper_context *)malloc(sizeof(whisper_context));
    if (ctx) ctx->_placeholder = 0;
    return ctx;
}

void whisper_free(whisper_context * ctx) {
    free(ctx);
}

whisper_full_params whisper_full_default_params(void) {
    whisper_full_params p;
    memset(&p, 0, sizeof(p));
    strncpy(p.language, "auto", sizeof(p.language) - 1);
    p.n_threads = 4;
    p.no_speech_thold = 0.6f;
    return p;
}

int whisper_full(whisper_context * ctx, whisper_full_params params,
                 const float * samples, int n_samples) {
    (void)ctx; (void)params; (void)samples; (void)n_samples;
    return 0; // success, 0 segments
}

int whisper_full_n_segments(whisper_context * ctx) {
    (void)ctx;
    return 0;
}

const char * whisper_full_get_segment_text(whisper_context * ctx, int i_segment) {
    (void)ctx; (void)i_segment;
    return "";
}

int64_t whisper_full_get_segment_t0(whisper_context * ctx, int i_segment) {
    (void)ctx; (void)i_segment;
    return 0;
}

int64_t whisper_full_get_segment_t1(whisper_context * ctx, int i_segment) {
    (void)ctx; (void)i_segment;
    return 0;
}

float whisper_full_get_segment_no_speech_prob(whisper_context * ctx, int i_segment) {
    (void)ctx; (void)i_segment;
    return 0.0f;
}

const char * whisper_full_lang_str(whisper_context * ctx) {
    (void)ctx;
    return "en";
}
