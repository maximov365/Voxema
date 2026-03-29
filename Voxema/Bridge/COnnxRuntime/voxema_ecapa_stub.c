//
// voxema_ecapa_stub.c  —  No-op stub for ECAPA-TDNN ONNX Runtime bridge.
//
// Returns a zero-filled 192-dim embedding. All remote segments will fall below
// the cosine similarity threshold and receive temporary labels ("Speaker A", …).
//
// REPLACEMENT: Remove this file and add the real ORT-backed implementation.
//
#include "include/voxema_ecapa.h"
#include <stdlib.h>
#include <string.h>

struct VoxemaEcapaContext {
    int _placeholder;
};

VoxemaEcapaContext * voxema_ecapa_init(const char * model_path) {
    (void)model_path;
    VoxemaEcapaContext * ctx = (VoxemaEcapaContext *)malloc(sizeof(VoxemaEcapaContext));
    if (ctx) ctx->_placeholder = 0;
    return ctx;
}

void voxema_ecapa_free(VoxemaEcapaContext * ctx) {
    free(ctx);
}

int voxema_ecapa_embed(VoxemaEcapaContext * ctx,
                       const float * samples, int n_samples,
                       float * embedding_out, int embedding_size) {
    (void)ctx; (void)samples; (void)n_samples;
    if (!embedding_out || embedding_size != VOXEMA_ECAPA_EMBEDDING_DIM) return -1;
    memset(embedding_out, 0, (size_t)embedding_size * sizeof(float));
    return 0;
}
