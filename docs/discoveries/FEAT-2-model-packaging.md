# Discovery: FEAT-2 — Model Packaging Strategy

## Discovery Question

How should Voxema package and deliver ML models (Whisper.cpp, ECAPA-TDNN, llama.cpp) to users, given DMG direct download distribution, multiple models of varying sizes, and a requirement for offline operation after initial setup?

## Prior Decisions

- **DEC-1 — Monetization:** Subscription-only Pro with Lemon Squeezy. Free tier ships all local functionality including all Whisper model sizes. No monetization code at MVP. This means model access is not gated — all users get all models.

## Context

Voxema's pipeline requires three distinct ML model families:

| Model Family | Purpose | Pipeline Stage | Sizes |
|---|---|---|---|
| Whisper.cpp (GGML) | Speech-to-text | Transcribe | tiny ~75MB, base ~142MB, small ~466MB, medium ~1.5GB |
| ECAPA-TDNN | Speaker embeddings | Diarize | ~25–50MB |
| llama.cpp (GGUF) | Meeting summarization | Summarize | 1.5–4GB+ |

MVP ships with Whisper tiny/base/small + ECAPA-TDNN. Medium Whisper is post-MVP. The LLM model for LocalProvider is also needed at MVP.

The packaging decision directly affects:
- **DMG download size** — impacts first-download conversion
- **First-launch experience** — if models must download, user must wait before first use
- **Disk space** — cumulative model storage on user's SSD
- **Update mechanism** — models evolve independently from app code
- **Offline guarantee** — models must work without internet after setup

The ModelManager component (defined in ARCHITECTURE.md) already manages model lifecycle: lazy loading, eager unloading, single-model-at-a-time on 8GB devices. This discovery determines *how models arrive on disk* before ModelManager takes over.

---

## Market & Competitive Research

### Reference 1 — MacWhisper

- **What they do:** macOS transcription app using Whisper models, supports both whisper.cpp and WhisperKit engines
- **UX approach:** Models are downloaded on-demand via a "Manage Models" screen. App ships without models; user selects and downloads. WhisperKit models require an initial preparation/compilation phase on first load (up to minutes for larger models).
- **Strengths:** Tiny app download (~15MB). User controls disk usage. Multiple engine options (whisper.cpp GGML + WhisperKit CoreML).
- **Weaknesses:** First use requires internet and waiting. No offline-out-of-the-box experience. WhisperKit compilation delay can confuse users.
- **URL:** https://goodsnooze.gumroad.com/l/macwhisper

### Reference 2 — Superwhisper

- **What they do:** macOS speech-to-text/dictation tool with local Whisper models
- **UX approach:** Models download on demand during setup. Smaller model starts downloading first so user can begin using the app quickly while larger models download in background. Models range from 75MB (Fast/Free) to 3GB (Ultra/Pro).
- **Strengths:** Progressive download — user gets value immediately with small model. Larger models available as background downloads. Clean UX for model selection.
- **Weaknesses:** Requires internet for first setup. Pro-gated larger models (not applicable to Voxema's Free tier strategy).
- **URL:** https://superwhisper.com

### Reference 3 — WhisperKit (framework, not app)

- **What they do:** Swift framework by Argmax that runs Whisper models in CoreML format on Apple Silicon
- **UX approach:** Models hosted on HuggingFace as pre-compiled `.mlmodelc` bundles. Apps using WhisperKit download models at runtime. First-time compilation to device-specific format takes seconds to minutes.
- **Strengths:** CoreML ANE-optimized — 2× faster encoder than Metal on M3 Pro. Native Apple ecosystem integration. Models hosted centrally on HuggingFace.
- **Weaknesses:** Not whisper.cpp compatible (different format). First-load compilation time for large models. CoreML medium/large model compilation can take tens of minutes.
- **URL:** https://github.com/argmaxinc/WhisperKit

### Reference 4 — speech-swift (MLX-based)

- **What they do:** Swift library for speaker diarization + VAD on Apple Silicon using MLX framework
- **UX approach:** Uses WeSpeaker ResNet34 + Pyannote + Silero VAD, all running natively through MLX. Total model size ~32MB.
- **Strengths:** Extremely small model footprint. Native Swift + MLX integration. No ONNX Runtime dependency. Speaker embeddings (256-dim) from WeSpeaker ResNet34 are comparable to ECAPA-TDNN.
- **Weaknesses:** MLX is a newer framework (less battle-tested). Uses ResNet34 not ECAPA-TDNN architecture. Requires Apple Silicon (which Voxema already targets).
- **URL:** https://github.com/soniqo/speech-swift

### Patterns Observed

1. **No competitor bundles large models inside the app.** All use on-demand download.
2. **Progressive model availability is the standard UX:** ship a tiny/fast model for immediate use, download larger ones in background.
3. **HuggingFace is the de facto model hosting platform** for open-source ML models (GGML, GGUF, CoreML).
4. **Speaker embedding models are tiny** (~25–50MB) — bundling is feasible.
5. **CoreML offers performance advantages on Apple Silicon** but at the cost of first-load compilation time and a different ecosystem from whisper.cpp's GGML format.
6. **MLX is emerging as a viable alternative** to ONNX Runtime for Apple Silicon native inference, especially for small models like speaker embeddings.

---

## Options Considered

### Decision Area 1: App Bundle vs On-Demand Download Strategy

1. **Hybrid: Bundle smallest Whisper + ECAPA-TDNN, download everything else**
2. **Full on-demand: Download all models on first launch**
3. **Fat bundle: Bundle all MVP models in the DMG**

### Decision Area 2: Speaker Embedding Model Format

1. **ONNX Runtime with CoreML Execution Provider**
2. **CoreML native (converted from ONNX)**

### Decision Area 3: Default LLM for LocalProvider

1. **Qwen 2.5 3B (Q4_K_M) — 1.93GB**
2. **Phi-3.5 Mini 3.8B (Q4_K_M) — 2.39GB**

---

## Comparison

### Decision Area 1: Bundle vs Download

#### Option 1 — Hybrid Bundle (recommended)

Bundle Whisper tiny (~75MB) + ECAPA-TDNN (~25–50MB) inside the app. Download Whisper base, small, medium, and LLM models on demand.

- **pros:**
  - DMG size ~150–180MB (app + tiny Whisper + ECAPA-TDNN) — reasonable for macOS
  - User can record and transcribe immediately after install (with tiny model)
  - Speaker identification works out of the box
  - Larger models downloaded in background while user gets first value
  - Follows the pattern established by MacWhisper and Superwhisper
- **cons:**
  - DMG is larger than a bare app (~15MB) but far smaller than bundling everything
  - Tiny model quality is lower (WER ~30% vs ~15% for small)
  - User still needs internet for better models
- **dependency friendliness:** high — no new infrastructure needed beyond HTTPS download
- **implementation simplicity:** moderate — needs download manager, progress UI, resumable downloads
- **operational simplicity:** high — models hosted on HuggingFace or static file host
- **value-to-complexity:** high — immediate value + progressive quality improvement
- **reversibility:** easy — can always add more bundled models later or switch to full on-demand
- **pipeline fit:** fits cleanly — ModelManager already handles model paths and lifecycle
- **MVP fit:** strong — user gets working pipeline immediately
- **long-term fit:** strong — scales to any number of models

#### Option 2 — Full On-Demand Download

No models bundled. All models downloaded on first launch or when selected.

- **pros:**
  - Smallest possible DMG (~15–30MB)
  - Maximum flexibility in model selection
  - Models always up-to-date from source
- **cons:**
  - First launch requires internet — violates "works offline" principle for initial experience
  - User must wait before any functionality works
  - Higher friction = lower activation rate
  - Onboarding flow becomes: permissions → internet → download → wait → configure — long and fragile
- **dependency friendliness:** high
- **implementation simplicity:** moderate — same download infrastructure as hybrid
- **operational simplicity:** high
- **value-to-complexity:** medium — simpler bundle but worse UX
- **reversibility:** easy
- **pipeline fit:** fits cleanly
- **MVP fit:** weak — poor first-launch experience
- **long-term fit:** acceptable

#### Option 3 — Fat Bundle

Bundle all MVP Whisper models (tiny + base + small) + ECAPA-TDNN inside the DMG.

- **pros:**
  - Fully offline from first launch (except LLM)
  - No download infrastructure needed for Whisper models
  - Simplest implementation
- **cons:**
  - DMG size ~700MB+ (75 + 142 + 466 + 50 = ~733MB before compression)
  - Slow download for initial install
  - Users who only want one model size waste bandwidth and disk
  - Model updates require new app release
  - LLM model still requires download regardless
- **dependency friendliness:** high
- **implementation simplicity:** high — models are just bundled resources
- **operational simplicity:** high
- **value-to-complexity:** low — large download for marginal benefit
- **reversibility:** easy — can remove bundled models and switch to download
- **pipeline fit:** fits cleanly
- **MVP fit:** weak — DMG size is a problem for download conversion
- **long-term fit:** poor — scales badly as models grow

---

### Decision Area 2: Speaker Embedding Format

#### Option 1 — ONNX Runtime with CoreML EP (recommended)

Use ONNX Runtime with the CoreML Execution Provider. Deploy the ECAPA-TDNN model in ONNX format (~25MB). ONNX Runtime delegates to CoreML under the hood for ANE/GPU acceleration.

- **pros:**
  - Pre-trained ONNX models available (Wespeaker ECAPA-TDNN512, 24.9MB on HuggingFace)
  - CoreML EP provides ANE/GPU acceleration transparently
  - ONNX Runtime is mature, auditable, well-documented
  - Same model file works across future platforms if needed
  - ECAPA-TDNN is the architecture already specified in ARCHITECTURE.md
- **cons:**
  - ONNX Runtime is an additional dependency (~50MB framework size)
  - Slightly more complex build integration than pure CoreML
- **dependency friendliness:** moderate — one external framework but widely used
- **implementation simplicity:** moderate
- **operational simplicity:** high
- **value-to-complexity:** high
- **reversibility:** easy — model can be converted to CoreML later
- **pipeline fit:** fits cleanly — matches ARCHITECTURE.md specification
- **MVP fit:** strong
- **long-term fit:** strong

#### Option 2 — CoreML Native

Convert ECAPA-TDNN from ONNX to CoreML format. Use CoreML directly without ONNX Runtime.

- **pros:**
  - No ONNX Runtime dependency — smaller app binary
  - Native Apple framework — zero external dependencies for inference
  - Potentially better ANE optimization with direct CoreML
- **cons:**
  - Requires model conversion pipeline (ONNX → CoreML) as part of build process
  - CoreML model format is Apple-only (irreversible platform lock-in)
  - Less community support for CoreML speaker models
  - Conversion may introduce subtle accuracy differences
  - CoreML model compilation on first load adds latency
- **dependency friendliness:** high — no external runtime
- **implementation simplicity:** moderate — conversion pipeline needed
- **operational simplicity:** high
- **value-to-complexity:** medium
- **reversibility:** moderate — model conversion is one-way; would need to re-convert from ONNX
- **pipeline fit:** fits cleanly
- **MVP fit:** acceptable — but adds conversion risk
- **long-term fit:** strong if committed to Apple ecosystem

---

### Decision Area 3: Default LLM for LocalProvider

#### Option 1 — Qwen 2.5 3B Q4_K_M (recommended)

- **Size:** 1.93GB
- **Context:** 128K tokens (critical for long meeting transcripts)
- **pros:**
  - Smallest viable model that fits comfortably in 8GB RAM alongside other processes
  - 128K context window handles even very long meetings
  - Strong multilingual support (relevant for Voxema's Russian language target)
  - Q4_K_M quantization is the recommended balance of quality and size
  - Source-available (Apache 2.0 license)
  - Widely available on HuggingFace in GGUF format
- **cons:**
  - 3B parameter model — summarization quality will be lower than 7B+ models
  - Users on 16GB+ machines could use a larger model but this would be the default
- **RAM footprint:** ~2.5GB during inference (model + KV cache for medium context)
- **pipeline fit:** fits cleanly — ModelManager loads after Whisper unloads

#### Option 2 — Phi-3.5 Mini 3.8B Q4_K_M

- **Size:** 2.39GB
- **Context:** 128K tokens
- **pros:**
  - Slightly more parameters (3.8B vs 3B) — potentially better reasoning
  - Strong instruction-following from Microsoft's training
  - Good at structured output (summary format)
- **cons:**
  - 460MB larger than Qwen 2.5 3B (2.39 vs 1.93GB)
  - ~3GB RAM during inference — tighter on 8GB devices
  - Weaker multilingual support than Qwen (English-centric)
  - MIT license (fine, but Qwen's Apache 2.0 is equivalent)
- **RAM footprint:** ~3GB during inference
- **pipeline fit:** fits cleanly but tighter RAM margin on 8GB devices

---

## Decision Quality Score

Scoring rule:
1 = poor, 3 = acceptable, 5 = strong.
Scores support reasoning but do not determine the decision automatically.

### Decision Area 1: Bundle vs Download

#### Option 1 — Hybrid Bundle
- MVP fit: 5
- architecture fit: 5
- implementation simplicity: 4
- reversibility: 5
- dependency friendliness: 5
- operational simplicity: 4
- testability: 4
- long-term fit: 5
- **Total: 37/40**

#### Option 2 — Full On-Demand
- MVP fit: 2
- architecture fit: 5
- implementation simplicity: 4
- reversibility: 5
- dependency friendliness: 5
- operational simplicity: 4
- testability: 4
- long-term fit: 4
- **Total: 33/40**

#### Option 3 — Fat Bundle
- MVP fit: 2
- architecture fit: 5
- implementation simplicity: 5
- reversibility: 5
- dependency friendliness: 5
- operational simplicity: 5
- testability: 5
- long-term fit: 2
- **Total: 34/40**

### Decision Area 2: Speaker Embedding Format

#### Option 1 — ONNX Runtime with CoreML EP
- MVP fit: 5
- architecture fit: 5
- implementation simplicity: 4
- reversibility: 5
- dependency friendliness: 3
- operational simplicity: 5
- testability: 4
- long-term fit: 4
- **Total: 35/40**

#### Option 2 — CoreML Native
- MVP fit: 3
- architecture fit: 4
- implementation simplicity: 3
- reversibility: 3
- dependency friendliness: 5
- operational simplicity: 4
- testability: 3
- long-term fit: 4
- **Total: 29/40**

### Decision Area 3: Default LLM

#### Option 1 — Qwen 2.5 3B Q4_K_M
- MVP fit: 5
- architecture fit: 5
- implementation simplicity: 5
- reversibility: 5
- dependency friendliness: 5
- operational simplicity: 5
- testability: 4
- long-term fit: 4
- **Total: 38/40**

#### Option 2 — Phi-3.5 Mini 3.8B Q4_K_M
- MVP fit: 3
- architecture fit: 5
- implementation simplicity: 5
- reversibility: 5
- dependency friendliness: 5
- operational simplicity: 4
- testability: 4
- long-term fit: 4
- **Total: 35/40**

---

## Decision Stability

**Hybrid bundle strategy:** stable — this is a well-proven pattern across macOS ML apps.

**ONNX Runtime for speaker embeddings:** stable — but revisit if MLX ecosystem matures enough to replace ONNX Runtime with a smaller dependency footprint.

**Default LLM choice:** temporary — LLM landscape evolves rapidly. Revisit after MVP benchmarking with real meeting transcripts. The architecture (SummaryProvider protocol + ModelManager) makes switching trivial.

---

## Recommendation

### 1. Hybrid Bundle Strategy

**Bundle inside the DMG:**
- Whisper tiny model (~75MB GGML format)
- ECAPA-TDNN model (~25MB ONNX format)

**Download on demand (managed by ModelManager):**
- Whisper base (~142MB)
- Whisper small (~466MB)
- Whisper medium (~1.5GB, post-MVP)
- Default LLM model (~1.9GB)
- Any future models

**DMG size estimate:** ~130–180MB (compressed with lzfse: app binary ~30MB + Whisper tiny 75MB + ECAPA-TDNN 25MB + resources).

**Download UX:**
- First launch: onboarding flow includes a "Model Setup" step after permissions
- Bundled Whisper tiny + ECAPA-TDNN work immediately — user can record and get a basic transcription
- Model Setup screen shows available models with sizes; user selects preferred Whisper model size
- Selected models download in background with progress indicator
- LLM model download prompted when user first attempts local summarization, or optionally during setup
- All downloads are resumable (URLSession background download)
- After initial setup, everything works offline

### 2. Model Formats

| Model | Format | Source | Bundled |
|---|---|---|---|
| Whisper tiny/base/small/medium | GGML (.bin) | HuggingFace (ggerganov/whisper.cpp) | tiny only |
| ECAPA-TDNN | ONNX (.onnx) | HuggingFace (Wespeaker/wespeaker-ecapa-tdnn512) | yes |
| Default LLM (Qwen 2.5 3B) | GGUF (.gguf) | HuggingFace (bartowski/Qwen2.5-3B-GGUF, Q4_K_M) | no |

### 3. Storage Location

Per ARCHITECTURE.md: `~/Library/Application Support/Voxema/Models/`

Directory structure:
```
~/Library/Application Support/Voxema/Models/
├── whisper/
│   ├── ggml-tiny.bin        (bundled, copied on first launch)
│   ├── ggml-base.bin        (downloaded)
│   ├── ggml-small.bin       (downloaded)
│   └── ggml-medium.bin      (downloaded, post-MVP)
├── speaker/
│   └── ecapa-tdnn-512.onnx  (bundled, copied on first launch)
└── llm/
    └── qwen2.5-3b-q4_k_m.gguf  (downloaded)
```

Bundled models are copied from the app bundle to Application Support on first launch so that all models live in one location and the app bundle remains read-only.

### 4. Model Integrity & Updates

- **SHA-256 checksums** for every model file, embedded in a `models-manifest.json` shipped with the app
- Checksum verified after download completes; re-download if mismatch
- **Model manifest versioning:** manifest includes model version and checksum; app update can ship a new manifest triggering re-download of updated models
- **Disk space checking:** before download, verify available space ≥ model size + 10% buffer; warn user if insufficient
- **Model deletion:** user can delete downloaded models from Settings to reclaim space; bundled models can be re-copied from app bundle

### 5. Default LLM Recommendation

**Qwen 2.5 3B Q4_K_M (1.93GB GGUF)** as the default local summarization model.

Rationale:
- Fits within 4GB peak memory budget on 8GB devices (model ~2.5GB in RAM including KV cache)
- 128K context window handles transcripts from meetings up to several hours
- Multilingual (supports English and Russian, both Voxema targets)
- Apache 2.0 license — fully auditable and source-available
- Smallest viable model that produces useful meeting summaries

For users with 16GB+ RAM, ModelManager can offer larger models (Qwen 2.5 7B Q4_K_M at ~4.4GB, or Llama 3.2 8B) as optional downloads. This is a post-MVP enhancement.

### 6. Disk Space Budget (all models installed)

| Model | Size |
|---|---|
| Whisper tiny | 75MB |
| Whisper base | 142MB |
| Whisper small | 466MB |
| ECAPA-TDNN | 25MB |
| Qwen 2.5 3B Q4_K_M | 1,930MB |
| **Total** | **~2.6GB** |

This is reasonable for a professional macOS app. Settings should show per-model disk usage and allow individual model deletion.

---

## Score Interpretation

The hybrid bundle strategy scores highest (37/40) because it optimizes for the two factors that matter most at MVP: **immediate usability** (user can record and transcribe right after install) and **reversibility** (easy to change what's bundled vs downloaded). Full on-demand loses on MVP fit because a "download before you can do anything" flow is a known activation killer. Fat bundle loses on long-term fit and MVP fit because a 700MB+ DMG discourages initial download.

Qwen 2.5 3B scores highest (38/40) for the default LLM because it's the smallest model that meets the RAM constraint on 8GB devices while still providing useful summarization quality and multilingual support.

---

## Why This Is the Simplest Viable Choice

1. **Bundle the minimum for immediate value** (Whisper tiny + ECAPA-TDNN) — user can record, transcribe, and identify speakers without internet
2. **Download everything else on demand** — standard pattern proven by MacWhisper, Superwhisper, and every major macOS ML app
3. **Use established model formats** (GGML for Whisper, ONNX for speaker embeddings, GGUF for LLM) — no custom format conversion needed
4. **Store in Application Support** — already defined in architecture, follows macOS conventions
5. **SHA-256 checksums** — standard, simple, sufficient
6. **Qwen 2.5 3B** — smallest model that fits the RAM budget and context requirements

No new architectural components beyond what ModelManager already defines. No new external services. No new infrastructure.

---

## Risks / Trade-offs

- **Whisper tiny quality is low (~30% WER).** Users who only use the bundled model without downloading better ones will get poor transcription. Mitigation: prominently recommend downloading Whisper small during onboarding; show quality indicators per model.
- **LLM download is 1.9GB.** Users on slow connections may find this frustrating. Mitigation: local summarization is optional — CloudProvider works immediately with user's API key. Show clear download progress and estimated time.
- **Model hosting costs.** If Voxema hosts models directly (not HuggingFace), bandwidth costs scale with users. Mitigation: use HuggingFace as primary CDN for MVP; consider own CDN only at scale.
- **HuggingFace availability.** If HuggingFace goes down, model downloads fail. Mitigation: support fallback URLs in models-manifest.json; bundled models still work.
- **ONNX Runtime dependency size** (~50MB). Adds to app bundle size. Mitigation: acceptable trade-off for mature, auditable framework. Can revisit if MLX/CoreML ecosystem matures.
- **Qwen 2.5 3B summarization quality.** 3B parameter models produce adequate but not excellent summaries. Mitigation: CloudProvider (direct API) available for higher quality; larger local models available for 16GB+ devices post-MVP.

---

## Follow-up Implications

- **ModelManager implementation** must support: bundled model extraction, on-demand download with resumption, checksum verification, disk space checking, per-model deletion
- **Onboarding flow** must include a "Model Setup" step with download progress
- **Settings UI** must show model management: installed models, sizes, download/delete actions
- **ARCHITECTURE.md** should be updated with model storage structure and download flow
- **models-manifest.json** format must be defined (model ID, version, format, size, SHA-256, download URL, bundled flag)
- **Build pipeline** must include steps to bundle Whisper tiny and ECAPA-TDNN into the app resources
- **Post-MVP:** evaluate WhisperKit (CoreML) as alternative Whisper engine for better ANE performance; evaluate MLX-based speaker embeddings (speech-swift) as ONNX Runtime replacement; offer larger LLM models for 16GB+ devices

---

## Should This Go Into DECISIONS.md?

**Yes — record after implementation confirms the choice.** The hybrid bundle strategy is clear enough to proceed, but the specific model versions, manifest format, and download infrastructure should be validated during Architect planning before recording as a formal decision.

---

## Optional Follow-ups

- **FEAT-5 (Sparkle integration):** Sparkle update feed can also carry model manifest updates, enabling model-only updates without full app releases
- **Post-MVP model benchmark task:** benchmark Qwen 2.5 3B vs Phi-3.5 Mini vs Llama 3.2 3B on real meeting transcripts to validate default LLM choice
- **Post-MVP WhisperKit evaluation:** CoreML Whisper models show 2× encoder speedup on Apple Silicon — worth evaluating as optional engine alongside whisper.cpp
- **Post-MVP MLX speaker embeddings:** speech-swift library shows promising results (~32MB total for VAD + speaker embeddings + segmentation) — potential ONNX Runtime replacement

---

## Assumptions Made

- HuggingFace will remain a viable free CDN for open-source model hosting at MVP scale
- Whisper.cpp GGML format will remain the standard for whisper.cpp inference (no breaking format changes expected)
- GGUF format for llama.cpp is stable (it is the current standard, superseding GGML for LLMs)
- Qwen 2.5 3B produces adequate meeting summaries — this must be validated with real transcripts
- ONNX Runtime macOS builds with CoreML EP are stable and auditable
- 150–180MB is an acceptable DMG size for a professional macOS app (comparable to apps like Sketch ~70MB, Figma ~200MB, Xcode ~7GB)

---

## Recommended Next Step

Product should update the PRD Technical Constraints section to specify the hybrid bundle strategy and model packaging approach. Then Architect should plan the ModelManager implementation with download infrastructure, manifest format, and onboarding model setup flow.

---

```json
{
  "handoff": {
    "agent": "Discovery",
    "artifact_type": "design_note",
    "artifact_path": "docs/discoveries/FEAT-2-model-packaging.md",
    "status": "produced",
    "next_recommended_agent": "Product",
    "next_recommended_reason": "Discovery complete; update PRD Technical Constraints with model packaging strategy.",
    "blocking_issues": [],
    "workflow_state": {
      "task_id": "FEAT-2",
      "artifact_id": null,
      "current_stage": "discovery",
      "quality_loop_iteration": 0,
      "builder_cycle_count": 0,
      "analytics_used": false,
      "product_spec_accepted": false
    }
  }
}
```
