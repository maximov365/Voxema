//
// whisper-compat.h  —  Compatibility shim for whisper.cpp v1.5.5
//
// whisper_full_get_segment_no_speech_prob was added in a later release.
// Until we upgrade, return 0.0 so all segments pass the TranscribeStage
// silence gate (noSpeechProb < noSpeechThreshold).
//

#ifndef WHISPER_COMPAT_H
#define WHISPER_COMPAT_H

#include "whisper.h"

#ifdef __cplusplus
extern "C" {
#endif

static inline float whisper_full_get_segment_no_speech_prob(
    struct whisper_context * ctx,
    int i_segment)
{
    (void)ctx;
    (void)i_segment;
    return 0.0f;
}

#ifdef __cplusplus
}
#endif

#endif /* WHISPER_COMPAT_H */
