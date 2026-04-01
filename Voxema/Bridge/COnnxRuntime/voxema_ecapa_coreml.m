/*
 * voxema_ecapa_coreml.m  —  TASK-29 / DEC-16 Phase 2
 *
 * Speaker embedding using CoreML ECAPA-TDNN (SpeechBrain spkrec-ecapa-voxceleb).
 * Falls back silently to MFCC statistics (Phase 1) when the model file is absent.
 *
 * CoreML model contract:
 *   Input  "waveform"  — MLMultiArrayDataTypeFloat32, shape [1, N_samples]
 *   Output "embedding" — MLMultiArrayDataTypeFloat32, shape [1, 192]
 *   Prepared via: python3 scripts/convert_ecapa_coreml.py
 *                 → place ecapa-tdnn.mlpackage at Voxema/Resources/Models/
 *
 * Memory management:
 *   ObjC objects (MLModel, NSString) are stored in the C struct as void* via
 *   CFBridgingRetain / CFBridgingRelease to avoid unsafe_unretained under ARC.
 */

#import <CoreML/CoreML.h>
#import <Foundation/Foundation.h>
#import <Accelerate/Accelerate.h>
#include "include/voxema_ecapa.h"
#include <stdlib.h>
#include <string.h>
#include <math.h>

// ── MFCC fallback constants (identical to former voxema_ecapa_mfcc.c) ─────────
#define SR          16000
#define WIN         400
#define HOP         160
#define N_FFT       512
#define LOG2N       9
#define N_BINS      (N_FFT/2+1)
#define N_MEL       40
#define FMIN        80.0f
#define FMAX        8000.0f

// ── Context ───────────────────────────────────────────────────────────────────
struct VoxemaEcapaContext {
    // CoreML model — NULL when model file unavailable, MFCC fallback active
    void *mlModelRef;      // CFBridgingRetain'd MLModel*
    void *outputNameRef;   // CFBridgingRetain'd NSString* (output tensor key)

    // MFCC fallback state — always initialised
    FFTSetup fft;
    float    hann[WIN];
    float    fb[N_MEL * N_BINS];
    float    buf[N_FFT];
    float    re[N_FFT / 2];
    float    im[N_FFT / 2];
    float    power[N_BINS];
    float    mel[N_MEL];
};

// ── Mel frequency helpers (shared with MFCC path) ─────────────────────────────
static float hz2mel(float hz) { return 2595.0f * log10f(1.0f + hz / 700.0f); }
static float mel2hz(float m)  { return 700.0f * (powf(10.0f, m / 2595.0f) - 1.0f); }

static void build_filterbank(float *fb)
{
    float mel_min = hz2mel(FMIN);
    float mel_max = hz2mel(FMAX);
    int   n_pts   = N_MEL + 2;
    float hz_pts[N_MEL + 2];
    float bin_pts[N_MEL + 2];

    for (int i = 0; i < n_pts; i++) {
        float mel  = mel_min + (float)i * (mel_max - mel_min) / (float)(N_MEL + 1);
        hz_pts[i]  = mel2hz(mel);
        bin_pts[i] = (float)(N_FFT + 1) * hz_pts[i] / (float)SR;
    }
    memset(fb, 0, N_MEL * N_BINS * sizeof(float));

    for (int m = 0; m < N_MEL; m++) {
        float lo     = bin_pts[m];
        float center = bin_pts[m + 1];
        float hi     = bin_pts[m + 2];
        float *row   = fb + m * N_BINS;
        if (center <= lo || hi <= center) continue;

        for (int k = 0; k < N_BINS; k++) {
            float kf = (float)k;
            if (kf > lo && kf < center)
                row[k] = (kf - lo) / (center - lo);
            else if (kf >= center && kf < hi)
                row[k] = (hi - kf) / (hi - center);
        }
    }
}

// ── API: init ─────────────────────────────────────────────────────────────────
VoxemaEcapaContext *voxema_ecapa_init(const char *model_path)
{
    VoxemaEcapaContext *ctx = (VoxemaEcapaContext *)calloc(1, sizeof(VoxemaEcapaContext));
    if (!ctx) return NULL;

    // Always initialise MFCC fallback so embed() works without the CoreML model.
    ctx->fft = vDSP_create_fftsetup(LOG2N, FFT_RADIX2);
    if (!ctx->fft) { free(ctx); return NULL; }
    vDSP_hann_window(ctx->hann, WIN, vDSP_HANN_NORM);
    build_filterbank(ctx->fb);

    // Attempt CoreML model load if a non-empty path was supplied.
    if (model_path && model_path[0] != '\0') {
        @autoreleasepool {
            NSString *pathStr = [NSString stringWithUTF8String:model_path];
            if (pathStr) {
                NSURL *modelURL = [NSURL fileURLWithPath:pathStr];
                NSError *err = nil;
                MLModelConfiguration *cfg = [[MLModelConfiguration alloc] init];
                cfg.computeUnits = MLComputeUnitsAll; // ANE + GPU + CPU
                MLModel *model = [MLModel modelWithContentsOfURL:modelURL
                                                   configuration:cfg
                                                           error:&err];
                if (model && !err) {
                    // Discover the first MLMultiArray output key
                    NSString *outKey = nil;
                    NSDictionary *outDesc = model.modelDescription.outputDescriptionsByName;
                    for (NSString *key in outDesc) {
                        MLFeatureDescription *desc = outDesc[key];
                        if (desc.type == MLFeatureTypeMultiArray) {
                            outKey = key;
                            break;
                        }
                    }
                    if (outKey) {
                        ctx->mlModelRef    = (void *)CFBridgingRetain(model);
                        ctx->outputNameRef = (void *)CFBridgingRetain(outKey);
                    }
                    // If no multi-array output found, model is unusable → MFCC fallback
                }
                // Silently ignore load errors — MFCC fallback is active
            }
        }
    }

    return ctx;
}

// ── API: free ─────────────────────────────────────────────────────────────────
void voxema_ecapa_free(VoxemaEcapaContext *ctx)
{
    if (!ctx) return;
    if (ctx->mlModelRef)    CFBridgingRelease(ctx->mlModelRef);
    if (ctx->outputNameRef) CFBridgingRelease(ctx->outputNameRef);
    if (ctx->fft)           vDSP_destroy_fftsetup(ctx->fft);
    free(ctx);
}

// ── CoreML inference path ─────────────────────────────────────────────────────
static int embed_coreml(VoxemaEcapaContext *ctx,
                        const float        *samples,
                        int                 n_samples,
                        float              *out,
                        int                 out_size)
{
    @autoreleasepool {
        MLModel  *model     = (__bridge MLModel  *)ctx->mlModelRef;
        NSString *outputKey = (__bridge NSString *)ctx->outputNameRef;

        // Build input MLMultiArray [1, n_samples]
        NSError *err = nil;
        MLMultiArray *inputArr = [[MLMultiArray alloc]
                                  initWithShape:@[@1, @(n_samples)]
                                      dataType:MLMultiArrayDataTypeFloat32
                                         error:&err];
        if (!inputArr || err) return -2;

        // Copy PCM samples — MLMultiArray backing store is contiguous float32
        float *ptr = (float *)inputArr.dataPointer;
        memcpy(ptr, samples, (size_t)n_samples * sizeof(float));

        // Run inference
        MLFeatureValue *inputFV = [MLFeatureValue featureValueWithMultiArray:inputArr];
        NSDictionary<NSString *, MLFeatureValue *> *inputDict = @{@"waveform": inputFV};
        MLDictionaryFeatureProvider *provider =
            [[MLDictionaryFeatureProvider alloc] initWithDictionary:inputDict error:&err];
        if (!provider || err) return -2;

        id<MLFeatureProvider> result = [model predictionFromFeatures:provider error:&err];
        if (!result || err) return -2;

        MLFeatureValue *outFV = [result featureValueForName:outputKey];
        MLMultiArray *outArr  = outFV.multiArrayValue;
        if (!outArr) return -2;

        // Extract up to out_size floats (model output may be [1, 192] or [192])
        NSInteger available = outArr.count;
        NSInteger toCopy    = (available < out_size) ? available : out_size;
        float *outPtr = (float *)outArr.dataPointer;
        memcpy(out, outPtr, (size_t)toCopy * sizeof(float));

        // Zero-pad if model output is shorter than expected embedding dim
        if (toCopy < out_size)
            memset(out + toCopy, 0, (size_t)(out_size - toCopy) * sizeof(float));

        return 0;
    }
}

// ── MFCC fallback path ────────────────────────────────────────────────────────
static int embed_mfcc(VoxemaEcapaContext *ctx,
                      const float        *samples,
                      int                 n_samples,
                      float              *out,
                      int                 out_size)
{
    memset(out, 0, (size_t)out_size * sizeof(float));

    int n_frames = (n_samples - WIN) / HOP + 1;
    if (n_frames < 1) return -1;

    double mu[N_MEL], M2[N_MEL];
    memset(mu, 0, sizeof(mu));
    memset(M2, 0, sizeof(M2));

    DSPSplitComplex split = { ctx->re, ctx->im };
    float eps = 1e-6f;
    int n_mel = N_MEL;

    for (int f = 0; f < n_frames; f++) {
        vDSP_vmul(samples + (size_t)f * HOP, 1, ctx->hann, 1, ctx->buf, 1, WIN);
        memset(ctx->buf + WIN, 0, (N_FFT - WIN) * sizeof(float));
        vDSP_ctoz((DSPComplex *)ctx->buf, 2, &split, 1, N_FFT / 2);
        vDSP_fft_zrip(ctx->fft, &split, 1, LOG2N, FFT_FORWARD);

        ctx->power[0]          = ctx->re[0] * ctx->re[0];
        ctx->power[N_BINS - 1] = ctx->im[0] * ctx->im[0];
        {
            DSPSplitComplex mid = { ctx->re + 1, ctx->im + 1 };
            vDSP_zvmags(&mid, 1, ctx->power + 1, 1, N_FFT / 2 - 1);
        }

        vDSP_mmul(ctx->fb, 1, ctx->power, 1, ctx->mel, 1, N_MEL, 1, N_BINS);
        vDSP_vsadd(ctx->mel, 1, &eps, ctx->mel, 1, N_MEL);
        vvlogf(ctx->mel, ctx->mel, &n_mel);

        for (int m = 0; m < N_MEL; m++) {
            double x     = ctx->mel[m];
            double delta = x - mu[m];
            mu[m] += delta / (f + 1);
            M2[m] += delta * (x - mu[m]);
        }
    }

    for (int m = 0; m < N_MEL; m++) {
        out[m]         = (float)mu[m];
        out[m + N_MEL] = (n_frames > 1) ? (float)(M2[m] / (n_frames - 1)) : 0.0f;
    }

    float norm = 0.0f;
    vDSP_svesq(out, 1, &norm, VOXEMA_ECAPA_EMBEDDING_DIM);
    norm = sqrtf(norm);
    if (norm > 1e-8f) {
        float inv = 1.0f / norm;
        vDSP_vsmul(out, 1, &inv, out, 1, VOXEMA_ECAPA_EMBEDDING_DIM);
    }

    return 0;
}

// ── API: embed ────────────────────────────────────────────────────────────────
int voxema_ecapa_embed(VoxemaEcapaContext *ctx,
                       const float        *samples,
                       int                 n_samples,
                       float              *out,
                       int                 out_size)
{
    if (!ctx || !samples || n_samples < WIN
        || !out || out_size != VOXEMA_ECAPA_EMBEDDING_DIM)
        return -1;

    if (ctx->mlModelRef)
        return embed_coreml(ctx, samples, n_samples, out, out_size);
    else
        return embed_mfcc(ctx, samples, n_samples, out, out_size);
}
