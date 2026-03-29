# Decisions

<!-- Record significant technical decisions here. -->
<!-- Each decision should include: context, options considered, decision, and rationale. -->

| ID | Title | Status | Date |
|----|-------|--------|------|
| DEC-1 | Monetization: Subscription-only Pro with Lemon Squeezy | accepted | 2026-03-29 |
| DEC-2 | Model packaging: Hybrid bundle + on-demand download | accepted | 2026-03-29 |

---

## DEC-1 — Monetization: Subscription-only Pro with Lemon Squeezy

**Status:** accepted
**Date:** 2026-03-29
**Source:** Discovery FEAT-1 (`docs/discoveries/FEAT-1-monetization.md`)

### Context

Voxema needs a monetization model that respects privacy-first positioning, supports cloud LLM operating costs for Pro tier, and works with DMG direct distribution (no App Store at MVP).

### Options Considered

1. Subscription-only Pro (recommended)
2. Hybrid: Subscription + Lifetime Local Premium
3. Usage-based Pro
4. Freemium with limits on Free tier

### Decision

**Subscription-only Pro** with Lemon Squeezy as merchant of record.

- **Free:** $0 — full local pipeline, no limits, CloudProvider (direct API) with user's own key
- **Pro:** $12/mo or $96/yr ($8/mo effective) — managed cloud LLM proxy, optimized prompts, no API key management
- **Enterprise:** custom pricing (later phase)
- **Payment:** Lemon Squeezy — merchant of record, built-in license key API, JWT-based offline validation
- **Feature gating:** UI/Settings layer via LicenseManager module; pipeline stages unaffected
- **CloudProvider (direct API) remains in Free tier** — Pro sells convenience + quality, not access

### Rationale

- Aligns with cloud LLM cost structure (Voxema pays per API call, user pays per month)
- $8–$12/mo validated against market (Otter $8.33, Krisp $8, Fireflies $10, Superwhisper $8.49)
- Lemon Squeezy handles tax compliance, supports JWT offline validation (critical for offline-first)
- No monetization code at MVP — Free tier ships alone
- Reversible: can add lifetime option or usage component later
- Scored 39/40 on decision quality (highest of 4 options)

### Subject to adjustment after F&F beta user testing.

---

## DEC-2 — Model Packaging: Hybrid Bundle + On-Demand Download

**Status:** accepted
**Date:** 2026-03-29
**Source:** Discovery FEAT-2 (`docs/discoveries/FEAT-2-model-packaging.md`)

### Context

Voxema requires multiple ML models (Whisper, ECAPA-TDNN, llama.cpp LLM) for its pipeline. DMG distribution means app size directly affects download conversion. Models range from 75MB to 4GB+.

### Options Considered

1. Bundle all models in DMG (~2.5GB+ DMG)
2. Download all models on first launch (~15MB DMG, no offline until download)
3. Hybrid: bundle smallest + download rest on demand (recommended)

### Decision

**Hybrid bundle strategy:**

- **Bundled in DMG:** Whisper tiny (~75MB) + ECAPA-TDNN ONNX (~25MB) → DMG ~150–180MB
- **Downloaded on demand:** Whisper base (~142MB), small (~466MB), LLM Qwen 2.5 3B Q4_K_M (~1.9GB)
- **Storage:** `~/Library/Application Support/Voxema/Models/` with subdirectories per model family
- **Integrity:** SHA-256 checksums in `models-manifest.json` shipped with app
- **Total disk budget (all MVP models):** ~2.6GB
- **ECAPA-TDNN runtime:** ONNX Runtime with CoreML Execution Provider (ANE/GPU delegation)
- **Default LLM:** Qwen 2.5 3B Q4_K_M (1.93GB GGUF, fits 4GB peak on 8GB devices, multilingual, Apache 2.0)

### Rationale

- 150–180MB DMG is standard for macOS productivity apps (matches competitor pattern)
- Bundled Whisper tiny + ECAPA-TDNN enables immediate recording + transcription + diarization out of box
- On-demand download for larger models preserves install UX while offering quality upgrades
- Every competitor (MacWhisper, Superwhisper, WhisperKit) uses on-demand model downloads
- Qwen 2.5 3B is the best quality/size tradeoff for 8GB devices with 128K context window

### Decision stability

Hybrid bundle strategy: **stable**. ONNX Runtime for ECAPA-TDNN: **stable** (revisit if Apple MLX matures). Default LLM choice: **temporary** — revisit after benchmarking with real meeting transcripts.
