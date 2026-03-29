//
// voxema_ecapa.h  —  Voxema domain-specific C bridge for ECAPA-TDNN via ONNX Runtime.
//
// Exposes a minimal 4-function API hiding ONNX Runtime internals from Swift.
// Embedding size: 192 float32 values (ECAPA-TDNN standard output).
//
// REPLACEMENT: Remove voxema_ecapa_stub.c and add the real ONNX Runtime-backed
// implementation when the ECAPA-TDNN ONNX model is available.
// Swift wrapper (EmbeddingEngine.swift) does NOT need to change.
//

#ifndef VOXEMA_ECAPA_H
#define VOXEMA_ECAPA_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/// Opaque context wrapping an ONNX Runtime session for ECAPA-TDNN.
typedef struct VoxemaEcapaContext VoxemaEcapaContext;

/// Dimensionality of the ECAPA-TDNN output embedding.
#define VOXEMA_ECAPA_EMBEDDING_DIM 192

// ── Context lifecycle ────────────────────────────────────────────────────────

/// Load the ECAPA-TDNN ONNX model from `model_path`.
/// Returns NULL on failure (file not found, invalid model, ORT init error).
VoxemaEcapaContext * voxema_ecapa_init(const char * model_path);

/// Release the context and all associated ONNX Runtime resources.
void voxema_ecapa_free(VoxemaEcapaContext * ctx);

// ── Inference ────────────────────────────────────────────────────────────────

/// Extract a speaker embedding from `samples` (mono float32, 16 kHz).
///
/// - `samples`        : audio samples (16 kHz mono float32)
/// - `n_samples`      : number of samples
/// - `embedding_out`  : caller-allocated buffer of VOXEMA_ECAPA_EMBEDDING_DIM floats
/// - `embedding_size` : must equal VOXEMA_ECAPA_EMBEDDING_DIM (validated)
///
/// Returns 0 on success, -1 on invalid args, -2 on inference error.
int voxema_ecapa_embed(
    VoxemaEcapaContext * ctx,
    const float        * samples,
    int                  n_samples,
    float              * embedding_out,
    int                  embedding_size
);

#ifdef __cplusplus
}
#endif
#endif /* VOXEMA_ECAPA_H */
