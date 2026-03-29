//
// whisper.h  —  Voxema C bridge for whisper.cpp
//
// This header declares the subset of the whisper.cpp C API used by WhisperEngine.
// In production:
//   • Replace whisper_stub.c with the real whisper.cpp + ggml sources
//     (or swap this target for a pre-built xcframework).
// The Swift wrapper (WhisperEngine.swift) never needs to change.
//

#ifndef WHISPER_H
#define WHISPER_H

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// ── Opaque context ────────────────────────────────────────────────────────────

typedef struct whisper_context whisper_context;

// ── Context lifecycle ─────────────────────────────────────────────────────────

/// Load a GGUF model file and return a context.  Returns NULL on failure.
whisper_context * whisper_init_from_file(const char * path_model);

/// Free the context and release all resources.
void whisper_free(whisper_context * ctx);

// ── Inference parameters ─────────────────────────────────────────────────────

typedef struct whisper_full_params {
    /// BCP-47 language code, e.g. "en", "auto" for auto-detect.  Max 8 bytes.
    char language[8];
    /// Translate to English if non-zero.
    int translate;
    /// Number of threads to use (0 = auto).
    int n_threads;
    /// No-speech probability threshold in [0, 1].  Segments above this are
    /// treated as silent and excluded from output.
    float no_speech_thold;
} whisper_full_params;

/// Returns a params struct with sensible defaults.
whisper_full_params whisper_full_default_params(void);

// ── Inference ─────────────────────────────────────────────────────────────────

/// Run full transcription on mono float32 16kHz samples.
/// Returns 0 on success, negative on error.
int whisper_full(
    whisper_context * ctx,
    whisper_full_params params,
    const float * samples,
    int n_samples
);

// ── Results ───────────────────────────────────────────────────────────────────

/// Number of segments in the latest transcription result.
int whisper_full_n_segments(whisper_context * ctx);

/// Segment text (UTF-8, null-terminated).  Valid until next whisper_full() call.
const char * whisper_full_get_segment_text(whisper_context * ctx, int i_segment);

/// Segment start time in milliseconds × 10 (centiseconds).
int64_t whisper_full_get_segment_t0(whisper_context * ctx, int i_segment);

/// Segment end time in milliseconds × 10 (centiseconds).
int64_t whisper_full_get_segment_t1(whisper_context * ctx, int i_segment);

/// No-speech probability for this segment in [0, 1].
float whisper_full_get_segment_no_speech_prob(whisper_context * ctx, int i_segment);

// ── Language ──────────────────────────────────────────────────────────────────

/// Language detected during inference, as BCP-47 code.
/// Valid after a successful whisper_full() call.
const char * whisper_full_lang_str(whisper_context * ctx);

#ifdef __cplusplus
}
#endif
#endif /* WHISPER_H */
