//
// voxema_ecapa.h  —  Voxema domain-specific C bridge for speaker embeddings.
//
// Exposes a minimal 4-function API.
//
// Current implementation: voxema_ecapa_coreml.m (DEC-16 Phase 2).
//   - CoreML ECAPA-TDNN (SpeechBrain spkrec-ecapa-voxceleb, ~22 MB .mlpackage).
//   - Falls back to MFCC statistics (Phase 1) when the model file is absent.
//   - Obtain the model: python3 scripts/convert_ecapa_coreml.py
//     then move ecapa-tdnn.mlpackage to Voxema/Resources/Models/
//     and re-run python3 scripts/add_coreml_ecapa.py to bundle it.
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
