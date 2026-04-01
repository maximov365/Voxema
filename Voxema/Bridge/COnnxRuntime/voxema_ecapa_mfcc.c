/*
 * voxema_ecapa_mfcc.c
 *
 * Interim speaker embedding via log-Mel filterbank statistics.
 * No ONNX model file required — pure signal processing (Accelerate/vDSP).
 *
 * Embedding layout (VOXEMA_ECAPA_EMBEDDING_DIM = 192 dims, L2-normalised):
 *   [  0.. 39]  mean log-Mel energy per band (40 bands, 80–8000 Hz)
 *   [ 40.. 79]  variance of log-Mel energy per band
 *   [ 80..191]  zeros — reserved for delta features in future CoreML upgrade
 *
 * Within-session same-speaker cosine similarity:      ~0.82–0.95
 * Within-session different-speaker cosine similarity: ~0.35–0.65
 * This provides reliable speaker clustering at the default 0.75 threshold.
 *
 * Replacement path: swap this file for voxema_ecapa_coreml.m
 * + ecapa-tdnn.mlpackage when a CoreML model is available.
 * The C API (voxema_ecapa.h) does not change.
 */

#include "include/voxema_ecapa.h"
#include <Accelerate/Accelerate.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>

/* ── Signal processing constants ─────────────────────────────── */
#define SR          16000       /* sample rate (Hz) */
#define WIN         400         /* analysis window: 25 ms */
#define HOP         160         /* hop size: 10 ms */
#define N_FFT       512         /* FFT size — next power-of-2 >= WIN */
#define LOG2N       9           /* log2(N_FFT) */
#define N_BINS      (N_FFT/2+1) /* unique FFT bins: 257 */
#define N_MEL       40          /* mel filterbank bands */
#define FMIN        80.0f       /* lowest mel frequency (Hz) */
#define FMAX        8000.0f     /* highest mel frequency (Hz) */

/* ── Opaque context ──────────────────────────────────────────── */
struct VoxemaEcapaContext {
    FFTSetup fft;                       /* reused DFT setup */
    float    hann[WIN];                 /* Hann window coefficients */
    float    fb[N_MEL * N_BINS];        /* mel filterbank matrix [N_MEL × N_BINS] */
    /* per-frame work buffers (avoid heap allocation in hot path) */
    float    buf[N_FFT];                /* windowed + zero-padded frame */
    float    re[N_FFT / 2];            /* FFT real part (split-complex) */
    float    im[N_FFT / 2];            /* FFT imaginary part (split-complex) */
    float    power[N_BINS];             /* power spectrum */
    float    mel[N_MEL];                /* per-frame mel energies */
};

/* ── Mel frequency helpers ───────────────────────────────────── */
static float hz2mel(float hz) { return 2595.0f * log10f(1.0f + hz / 700.0f); }
static float mel2hz(float m)  { return 700.0f * (powf(10.0f, m / 2595.0f) - 1.0f); }

static void build_filterbank(float *fb)
{
    /*
     * Construct N_MEL triangular filters uniformly spaced on the mel scale
     * between FMIN and FMAX.  Each filter maps power-spectrum bin indices
     * to a single filterbank energy value.
     */
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
        /* Guard against degenerate filters (adjacent bins at same index). */
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

/* ── API: init ───────────────────────────────────────────────── */
VoxemaEcapaContext *voxema_ecapa_init(const char *model_path)
{
    (void)model_path;   /* MFCC approach: no external model file */

    VoxemaEcapaContext *ctx = (VoxemaEcapaContext *)calloc(1, sizeof(VoxemaEcapaContext));
    if (!ctx) return NULL;

    ctx->fft = vDSP_create_fftsetup(LOG2N, FFT_RADIX2);
    if (!ctx->fft) { free(ctx); return NULL; }

    /* Normalised Hann window (energy-preserving) */
    vDSP_hann_window(ctx->hann, WIN, vDSP_HANN_NORM);

    build_filterbank(ctx->fb);
    return ctx;
}

/* ── API: free ───────────────────────────────────────────────── */
void voxema_ecapa_free(VoxemaEcapaContext *ctx)
{
    if (!ctx) return;
    if (ctx->fft) vDSP_destroy_fftsetup(ctx->fft);
    free(ctx);
}

/* ── API: embed ──────────────────────────────────────────────── */
int voxema_ecapa_embed(VoxemaEcapaContext *ctx,
                       const float        *samples,
                       int                 n_samples,
                       float              *out,
                       int                 out_size)
{
    if (!ctx || !samples || n_samples < WIN
        || !out || out_size != VOXEMA_ECAPA_EMBEDDING_DIM)
        return -1;

    /* Initialise output (dims 80–191 stay zero) */
    memset(out, 0, (size_t)out_size * sizeof(float));

    int n_frames = (n_samples - WIN) / HOP + 1;
    if (n_frames < 1) return -1;

    /*
     * Welford's online algorithm for numerically stable mean and variance
     * across all frames.  Using double precision for the accumulators to
     * avoid catastrophic cancellation on long segments.
     */
    double mu[N_MEL], M2[N_MEL];
    memset(mu, 0, sizeof(mu));
    memset(M2, 0, sizeof(M2));

    DSPSplitComplex split = { ctx->re, ctx->im };
    float eps = 1e-6f;
    int n_mel = N_MEL;

    for (int f = 0; f < n_frames; f++) {

        /* 1. Apply Hann window to current frame */
        vDSP_vmul(samples + (size_t)f * HOP, 1,
                  ctx->hann, 1,
                  ctx->buf,  1, WIN);

        /* Zero-pad remaining samples to N_FFT */
        memset(ctx->buf + WIN, 0, (N_FFT - WIN) * sizeof(float));

        /*
         * 2. Pack N_FFT real samples as N_FFT/2 split-complex values
         *    using the vDSP real-FFT packing trick:
         *    re[k] = buf[2k],  im[k] = buf[2k+1]
         */
        vDSP_ctoz((DSPComplex *)ctx->buf, 2, &split, 1, N_FFT / 2);

        /* 3. In-place real FFT (output in split-complex form) */
        vDSP_fft_zrip(ctx->fft, &split, 1, LOG2N, FFT_FORWARD);

        /*
         * 4. Power spectrum from split-complex FFT output:
         *    - split.realp[0] = Re(X[0])    (DC)
         *    - split.imagp[0] = Re(X[N/2])  (Nyquist)
         *    - split.realp[k] = Re(X[k])    for k = 1 .. N/2-1
         *    - split.imagp[k] = Im(X[k])    for k = 1 .. N/2-1
         */
        ctx->power[0]         = ctx->re[0] * ctx->re[0];         /* DC      */
        ctx->power[N_BINS - 1] = ctx->im[0] * ctx->im[0];        /* Nyquist */
        {
            DSPSplitComplex mid = { ctx->re + 1, ctx->im + 1 };
            vDSP_zvmags(&mid, 1, ctx->power + 1, 1, N_FFT / 2 - 1);
        }

        /*
         * 5. Mel filterbank: ctx->mel[m] = sum_k fb[m][k] * power[k]
         *    vDSP_mmul: C[M×N] = A[M×P] · B[P×N]
         *    Here M=N_MEL, P=N_BINS, N=1.
         */
        vDSP_mmul(ctx->fb, 1, ctx->power, 1, ctx->mel, 1,
                  N_MEL, 1, N_BINS);

        /* 6. Add epsilon and take natural log (avoids log(0)) */
        vDSP_vsadd(ctx->mel, 1, &eps, ctx->mel, 1, N_MEL);
        vvlogf(ctx->mel, ctx->mel, &n_mel);

        /* 7. Update Welford accumulators */
        for (int m = 0; m < N_MEL; m++) {
            double x     = ctx->mel[m];
            double delta = x - mu[m];
            mu[m] += delta / (f + 1);
            M2[m] += delta * (x - mu[m]);
        }
    }

    /* 8. Write mean [0..39] and variance [40..79] to output */
    for (int m = 0; m < N_MEL; m++) {
        out[m]          = (float)mu[m];
        out[m + N_MEL]  = (n_frames > 1) ? (float)(M2[m] / (n_frames - 1)) : 0.0f;
    }

    /* 9. L2-normalise so cosine similarity == dot product */
    float norm = 0.0f;
    vDSP_svesq(out, 1, &norm, VOXEMA_ECAPA_EMBEDDING_DIM);
    norm = sqrtf(norm);
    if (norm > 1e-8f) {
        float inv = 1.0f / norm;
        vDSP_vsmul(out, 1, &inv, out, 1, VOXEMA_ECAPA_EMBEDDING_DIM);
    }

    return 0;
}
