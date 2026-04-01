# Decisions

<!-- Record significant technical decisions here. -->
<!-- Each decision should include: context, options considered, decision, and rationale. -->

| ID | Title | Status | Date |
|----|-------|--------|------|
| DEC-1 | Monetization: Subscription-only Pro with Lemon Squeezy | accepted | 2026-03-29 |
| DEC-3 | Backend stack: TypeScript (Hono) + Railway + PostgreSQL | accepted | 2026-03-29 |
| DEC-4 | Auto-update: Sparkle 2 via SPM + GitHub Pages/Releases | accepted | 2026-03-29 |
| DEC-2 | Model packaging: Hybrid bundle + on-demand download | accepted | 2026-03-29 |
| DEC-16 | Diarization embedding: MFCC via Accelerate (interim) → CoreML ECAPA-TDNN (production) | accepted | 2026-03-29 |
| DEC-17 | Whisper initial_prompt: "Meeting transcript:" as default context hint | accepted | 2026-04-01 |
| DEC-18 | DiarizeStage: skip embedding for segments < 1.5 s, reuse last speaker | accepted | 2026-04-01 |

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
- **Downloaded on demand:** Whisper base (~142MB), small (~466MB), LLM (user-selected during onboarding)
- **Storage:** `~/Library/Application Support/Voxema/Models/` with subdirectories per model family
- **Integrity & catalog:** `models-manifest.json` shipped with app — contains curated LLM list, SHA-256 checksums, RAM requirements per model, and quality tier labels. Updated via Sparkle alongside the app.
- **Total disk budget (all MVP models):** ~2.6GB (varies by LLM choice)
- **ECAPA-TDNN runtime:** ONNX Runtime with CoreML Execution Provider (ANE/GPU delegation)
- **LLM selection UX:** During onboarding, app detects device RAM (`ProcessInfo.processInfo.physicalMemory`) and recommends the best-fit model. User sees human-readable quality tiers ("Good / Better / Best"), not model names. Model names shown as secondary detail. User can skip LLM download and set up later. Curated list at MVP: Qwen 2.5 3B Q4_K_M (~1.9GB, 8GB devices), Qwen 2.5 7B Q4_K_M (~4.5GB, 16GB+ devices). List will expand as models are benchmarked.

### Rationale

- 150–180MB DMG is standard for macOS productivity apps (matches competitor pattern)
- Bundled Whisper tiny + ECAPA-TDNN enables immediate recording + transcription + diarization out of box
- On-demand download for larger models preserves install UX while offering quality upgrades
- Every competitor (MacWhisper, Superwhisper, WhisperKit) uses on-demand model downloads
- Qwen 2.5 3B is the best quality/size tradeoff for 8GB devices with 128K context window
- Hardware-based recommendation removes decision burden from non-technical users
- Plain-language tiers ("Good / Better / Best") keep onboarding accessible
- Skip option respects users who plan to use CloudProvider

### Decision stability

Hybrid bundle strategy: **stable**. ONNX Runtime for ECAPA-TDNN: **stable** (revisit if Apple MLX matures). LLM curated list: **evolving** — models and tier assignments updated as new models are benchmarked. LLM selection UX: **stable**.

---

## DEC-3 — Backend Stack: TypeScript (Hono) + Railway + PostgreSQL

**Status:** accepted
**Date:** 2026-03-29
**Source:** Discovery FEAT-3 (`docs/discoveries/FEAT-3-backend-stack.md`)

### Context

Voxema needs a post-MVP backend for Pro tier services: authentication, subscription/billing (Lemon Squeezy webhooks), LLM proxy, usage tracking, and admin dashboard. Backend is content-stateless — never stores audio, transcripts, or summaries. Must be simple enough for a solo developer to operate.

### Options Considered

**Language/Framework:**
1. Go (Echo/Chi) — 37/40
2. TypeScript (Hono) — 37/40 (selected: Lemon Squeezy SDK advantage)
3. Swift (Vapor) — 30/40
4. Python (FastAPI) — 29/40
5. Rust (Axum) — 31/40

**Hosting:**
1. Railway — 38/40 (selected)
2. Fly.io — 33/40 (upgrade path)
3. AWS (ECS/Lambda) — 28/40
4. Hetzner + Docker — 30/40

**Database:**
1. PostgreSQL — 38/40 (selected)
2. SQLite — 29/40 (eliminated: single-writer under concurrent LLM proxy)

### Decision

**Recommended stack:**

- **Language/Framework:** TypeScript with Hono (ultralight, built-in JWT/CORS middleware)
- **ORM:** Drizzle ORM (type-safe, lightweight)
- **Database:** PostgreSQL (managed by Railway)
- **Hosting:** Railway (usage-based pricing, ~$15–25/mo at launch)
- **Auth:** Apple Sign In (server-side validation) + Email OTP (no passwords per PRD). JWT tokens with 7-day refresh cycle.
- **Billing:** Lemon Squeezy webhook integration (official TypeScript SDK). License key validation with JWT offline support.
- **LLM Proxy:** Prompt-wrapping proxy with SSE streaming. Claude Haiku 4.5 primary (~$0.27/user/month at 20 meetings), GPT-4o-mini fallback (~$0.04/user/month). Post-response token counting, database-backed rate limiting.
- **Admin Dashboard:** Internal-only, same Hono backend serving a lightweight frontend (post-MVP, Pro launch phase).

### Cost model

| Scale | Infra/mo | LLM cost/mo | Revenue/mo | Gross margin |
|---|---|---|---|---|
| 100 Pro users | ~$50 | ~$27 | $800–1,200 | ~90% |
| 1,000 Pro users | ~$265 | ~$270 | $8,000–12,000 | ~93% |
| 10,000 Pro users | ~$2,100 | ~$2,700 | $80,000–120,000 | ~94% |

### Rationale

- TypeScript + Hono: fastest development velocity for a solo dev, Lemon Squeezy has official TS SDK and typed webhook library
- Go was equally scored but lacks the Lemon Squeezy ecosystem advantage
- Railway: simplest deploy (git push), managed Postgres, usage-based pricing; migration to Fly.io is a half-day task when EU data residency or edge deployment is needed
- PostgreSQL over SQLite for backend: concurrent writes from LLM proxy requests require multi-writer support
- 86–94% gross margins validate $12/mo ($8/mo annual) pricing from DEC-1

### Decision stability

Language (TypeScript/Hono): **stable**. Database (PostgreSQL): **stable**. ORM (Drizzle): **stable**. Hosting (Railway): **temporary** — revisit at scale or when EU data residency required, migrate to Fly.io. LLM primary provider (Haiku 4.5): **temporary** — revisit based on pricing changes and quality benchmarks. Auth flow (Apple Sign In + OTP): **stable**.

---

## DEC-4 — Auto-Update: Sparkle 2 via SPM + GitHub Pages/Releases

**Status:** accepted
**Date:** 2026-03-29
**Source:** Discovery FEAT-5 (`docs/discoveries/FEAT-5-sparkle-integration.md`)

### Context

Voxema distributes via DMG (no App Store at MVP). Users need a way to receive updates. Without a built-in update mechanism, users on outdated versions miss security patches and quality improvements.

### Options Considered

**Framework:** Sparkle 2 (only serious option for macOS DMG auto-update).

**Appcast hosting:**
1. GitHub Pages + GitHub Releases — 38/40 (selected)
2. S3/R2 bucket — 34/40
3. Railway backend — 28/40

**Update UX:**
1. Sparkle built-in UI — 39/40 (selected for MVP)
2. Custom SwiftUI UI — post-MVP enhancement

**Delta updates:**
1. Defer to post-MVP — 38/40 (selected)
2. Implement at MVP — 30/40

### Decision

- **Framework:** Sparkle 2 via Swift Package Manager
- **Appcast hosting:** GitHub Pages (appcast XML) + GitHub Releases (DMG downloads). Zero cost, version-controlled, proven pattern (Sindre Sorhus and many indie macOS apps).
- **Code signing:** Apple Developer ID certificate + Hardened Runtime + notarization (mandatory for DMG distribution). Sparkle EdDSA signatures for update verification. Dual verification on every update.
- **Update UX (MVP):** Sparkle's built-in UI — complete, localized, accessible. Check on launch (default ~24h interval) + manual "Check for Updates" menu item.
- **Update UX (post-MVP):** Optional custom SwiftUI UI for branded experience.
- **Delta updates:** Deferred to post-MVP. Full DMG download (~150–180MB) is acceptable at early scale.
- **Model catalog updates:** `models-manifest.json` updated via Sparkle app releases — no separate model update mechanism needed.
- **Release pipeline:** GitHub Actions tag-triggered: build → sign → notarize → create DMG → EdDSA sign → upload to GitHub Release → generate appcast via `generate_appcast` → push appcast to GitHub Pages.
- **Lemon Squeezy interaction:** None needed. Updates delivered to all tiers equally. License validation is orthogonal (UI layer per DEC-1).

### Rationale

- Sparkle 2 is the de facto standard for macOS DMG auto-update (used by hundreds of popular apps)
- GitHub Pages/Releases is zero-cost and version-controlled — no infrastructure to manage
- Built-in Sparkle UI is polished, localized (40+ languages), and VoiceOver-accessible — no reason to rewrite at MVP
- Delta updates add complexity to the release pipeline for minimal benefit at early scale
- models-manifest.json via app releases keeps model catalog in sync with app capabilities

### Decision stability

Framework (Sparkle 2): **stable**. Hosting (GitHub Pages/Releases): **stable**. Code signing (Developer ID + EdDSA): **stable**. Update UX (built-in): **stable for MVP**, revisit post-MVP for branding. Delta updates: **deferred** — revisit after 3–5 stable releases.

### Critical operational note

**EdDSA private key must be backed up securely** (password manager, not just on one machine). Loss of this key would prevent shipping updates that existing users' installations will accept.

---

## DEC-4 — whisper.cpp Integration: Local C Target (Stub Pattern)

**Date:** 2026-03-29
**Context:** TASK-8 required integrating the whisper.cpp speech recognition library. Options: full SPM package (ggerganov/whisper.cpp), WhisperKit (Argmax), xcframework binary, or local C stub target.

**Decision:** Use a local C target (`CWhisper`) with stub no-op implementations for the `swift test` build path, combined with a `module.modulemap` and Xcode build settings for `xcodebuild`. The stub pattern allows the Swift wrapper (`WhisperEngine.swift`) to compile against the real whisper.cpp C API without the library being present.

**Rationale:**
- `ggerganov/whisper.cpp` SPM package is 400MB+ git history — impractical for CI and incremental development. First build would take 5–10 minutes.
- WhisperKit uses CoreML model format (not `.gguf`) — incompatible with `models-manifest.json` and `ModelManager` (TASK-5 / DEC-2).
- xcframework binary requires a separate build step and binary distribution.
- Local stub pattern: zero build overhead, correct API surface, mechanical swap at model-integration milestone. `whisper_stub.c` clearly documents the replacement procedure.

**Replacement path:** When ready for real inference, remove `whisper_stub.c` and replace with:
- (a) Real `whisper.cpp` + `ggml` C source files in the `CWhisper` target, or
- (b) A `.binaryTarget` pointing to a pre-built `CWhisper.xcframework`.
Zero changes to `WhisperEngine.swift` are required.

**Trade-offs:**
- Stub returns empty transcriptions at runtime (expected and documented).
- No performance tuning or Metal acceleration until real library is integrated.

---

## DEC-5 — ECAPA-TDNN integration: domain-specific C bridge (stub pattern)

**Decision:** Implement ECAPA-TDNN speaker embedding via a Voxema-specific C bridge (`COnnxRuntime`) with a no-op stub, following the same pattern as `CWhisper` (DEC-4).

**Context:** ECAPA-TDNN runs via ONNX Runtime (DEC-2). The ONNX Runtime C API is complex (hundreds of functions accessed through a function-table `OrtApi*`). Exposing the full API to Swift would create maintenance burden and tie Swift code to ORT internals.

**Options considered:**

1. Expose full ONNX Runtime C API to Swift (`onnxruntime_c_api.h`) — large header, tight coupling to ORT version
2. Voxema-specific 4-function wrapper API (`voxema_ecapa.h`) hiding ORT details — minimal surface, easily swappable
3. CoreML / CreateML directly (no ORT) — loses CoreML EP flexibility, limits model portability

**Decision:** Option 2 — minimal domain-specific wrapper.

**`voxema_ecapa.h` API:**
- `voxema_ecapa_init(model_path)` → opaque context
- `voxema_ecapa_free(ctx)`
- `voxema_ecapa_embed(ctx, samples, n_samples, embedding_out, embedding_size)` → 192-dim float32
- Stub (`voxema_ecapa_stub.c`) returns zero embeddings

**Mechanical replacement path:**
1. Remove `voxema_ecapa_stub.c`
2. Add real implementation (`voxema_ecapa_ort.c`) that calls ONNX Runtime C API
3. Link `onnxruntime.xcframework` (CoreML EP) in `project.pbxproj`
4. No Swift code changes required

**Status:** Stable. Real ORT implementation deferred until ECAPA-TDNN model is bundled.

---

## DEC-6 — LLM integration: domain-specific C bridge (stub pattern)

**Decision:** Implement llama.cpp local LLM inference via a Voxema-specific C bridge (`CLlama`) with a no-op stub, following the same pattern as `CWhisper` (DEC-4) and `COnnxRuntime` (DEC-5).

**Context:** llama.cpp has a complex C++ API. Exposing it fully to Swift would require bridging C++ headers. A thin domain-specific C wrapper (`voxema_llm.h`) hides llama.cpp internals.

**`voxema_llm.h` API:**
- `voxema_llm_init(model_path, n_ctx)` → opaque context
- `voxema_llm_free(ctx)`
- `voxema_llm_generate(ctx, prompt, output_buf, max_bytes, max_new_tokens)` → UTF-8 completion

**Stub behavior:** `voxema_llm_stub.c` returns hard-coded JSON `{"summary":"[Stub]",...}` — parseable by `SummaryOutputParser`.

**Mechanical replacement path:**
1. Remove `voxema_llm_stub.c`
2. Add `voxema_llm_gguf.c` wrapping llama.cpp C API
3. Link `llama.xcframework` (or build from source) in `project.pbxproj`
4. No Swift code changes required

**Status:** Stable. Real llama.cpp implementation deferred until GGUF model is bundled.

---

## DEC-7 — System audio capture: Core Audio tap (macOS 14.2+) instead of ScreenCaptureKit

**Status:** accepted
**Date:** 2026-03-29
**Source:** Discovery (TASK-20)

### Context

Voxema captures system audio to record remote meeting participants. The original implementation used ScreenCaptureKit (`SCStream`), which requires the full "Screen & System Audio Recording" TCC permission (`kTCCServiceScreenCaptureWithAudio`). This caused multiple problems:

- macOS TCC caching issues required app restarts after permission grants
- The word "screen recording" in the permission prompt conflicted with Voxema's audio-only positioning
- Recurring development issues with apps not appearing in System Settings

macOS 14.2 introduced Core Audio Process Taps (`CATapDescription` + `AudioHardwareCreateProcessTap`), which capture system audio without any screen recording involvement. Apps using this API appear under the separate "Allow system audio recording" section in System Settings, not under "Screen Recording".

### Options Considered

1. **Stay with ScreenCaptureKit** — no deployment target change, but full "screen recording" permission required forever
2. **Core Audio tap on macOS 14.2+, SCK fallback on 13.0–14.1** — dual path, added maintenance burden
3. **Full migration to Core Audio tap, raise minimum to macOS 14.2** (selected)

### Decision

Replace `SystemAudioCapture.swift` with a Core Audio tap implementation. Raise minimum deployment target from **macOS 13.0 to macOS 14.2**.

- `NSScreenCaptureUsageDescription` replaced with `NSAudioCaptureUsageDescription`
- No restart required after granting permission (tap takes effect immediately)
- `PipelineError.captureScreenRecordingPermissionDenied` renamed to `.captureSystemAudioPermissionDenied`

### Rationale

- Core Audio tap is the technically correct API for audio-only capture — it was purpose-built for this use case
- The privacy story improves materially: users grant audio recording permission, not screen recording
- All Apple Silicon Macs can run macOS 14.2 (released December 2023); Ventura market share <10% by launch
- Eliminates the entire `kTCCServiceScreenCapture` TCC problem class permanently
- Single-file change to `SystemAudioCapture.swift` — no other pipeline changes required

### Deployment target note

macOS 13.0 was originally chosen because it was the earliest version supporting ScreenCaptureKit audio. With the move to Core Audio taps, the effective minimum is macOS 14.2. There are no other macOS 14.2+ API dependencies; future regressions to 13.0 would require reverting `SystemAudioCapture.swift` only.

---

## DEC-13: AppState uses ObservableObject (@MainActor) instead of @Observable

**Date:** 2026-03-30
**Task:** TASK-12
**Status:** accepted

**Context:** macOS 13+ compatibility is required (per PRD). `@Observable` (Swift 5.9 Observation framework) requires macOS 14.0+. SwiftUI's `NavigationSplitView` and `MenuBarExtra` are used as the primary layout primitives — both available from macOS 13.

**Decision:** `AppState` uses `ObservableObject` with `@Published` properties and `@StateObject` at the root. All mutations are dispatched on `@MainActor`.

**Tradeoffs:**
- `ObservableObject` requires explicit `@Published` annotation on every observed property — more boilerplate than `@Observable`, but no runtime version gate.
- `@Observable` would allow finer-grained dependency tracking and fewer redraws, but is only available macOS 14+.
- Migration to `@Observable` is a mechanical rename when minimum deployment target is raised to macOS 14.

---

## DEC-14: whisper.cpp integration via direct source files in CWhisper target

**Date:** 2026-03-29
**Task:** TASK-23
**Status:** accepted

**Context:** TASK-22 attempted SPM integration of `ggerganov/whisper.cpp` but failed due to Xcode package resolution errors and module conflicts. A Discovery phase evaluated three options: (A) direct source files, (B) pre-built XCFramework, (C) SPM.

**Decision:** Integrate whisper.cpp v1.5.5 as direct C/C++ source files in the existing `CWhisper` Xcode target. Source files live in `Voxema/Bridge/CWhisper/src/`. The real `whisper.h` replaces the stub header in `include/`. A `whisper-compat.h` shim provides `whisper_full_get_segment_no_speech_prob` (returns 0.0) until a version with native support is integrated. `WhisperEngine.swift` uses `whisper_init_from_file_with_params` and `whisper_full_default_params(WHISPER_SAMPLING_GREEDY)`.

**Tradeoffs:**
- No SPM / package manager overhead; source files are committed to the repo.
- ~1.7MB of C/C++ source added to the repo, but this is acceptable given the privacy-first, offline-first architecture.
- `whisper_full_get_segment_no_speech_prob` is not available in v1.5.5; the compat shim returns 0.0 so all segments pass the silence gate. To be revisited when upgrading to a version with native support.
- Upgrade path: replace files in `src/`, update `include/whisper.h`, remove compat shim if the function becomes available.

---

## DEC-15: Metal GPU acceleration for whisper.cpp — default.metallib approach

**Date:** 2026-03-29
**Task:** TASK-27
**Status:** accepted

**Context:** whisper-medium on CPU-only takes 3–5 minutes for a 30-second recording. Metal GPU reduces this to ~9–15 seconds on Apple Silicon (15–25× speedup). whisper.cpp v1.5.5's `ggml.c`, `ggml-backend.c`, and `whisper.cpp` already contain `#ifdef GGML_USE_METAL` hooks — they just needed the Metal implementation files.

**Decision:** Add `ggml-metal.h`, `ggml-metal.m`, and `ggml-metal.metal` from whisper.cpp v1.5.5 to the existing Voxema Xcode target. `ggml-metal.metal` compiles via Xcode's Metal frontend into `default.metallib` embedded in the app bundle. `ggml-metal.m` loads `default.metallib` at runtime via `[bundle pathForResource:@"default" ofType:@"metallib"]`. `GGML_USE_METAL` added to `OTHER_CFLAGS` and `OTHER_CPLUSPLUSFLAGS`. `cparams.use_gpu = true` in `WhisperEngine.swift`.

**Why not GGML_METAL_EMBED_LIBRARY:** That approach requires generating `ggml_metallib_start/end` symbols via a pre-build script. The `default.metallib` approach is the standard Xcode Metal workflow — simpler, no pre-build script, no generated files, and equally correct.

**Graceful fallback:** `ggml_backend_metal_supports_family(backend_gpu, 7)` in `whisper.cpp:1223` falls back to CPU silently on devices below Metal family 7 (irrelevant for macOS 14.2+ Apple Silicon, but safe).

**Tradeoffs:**
- ~420KB of additional Metal source added to the repo (`ggml-metal.m` + `ggml-metal.metal`).
- Xcode compiles `ggml-metal.metal` → `default.metallib` at build time (~5–10s, cached).
- First inference per app session triggers shader pipeline compilation (~200ms, OS-cached after).
- Upgrade path: replace `ggml-metal.*` files when upgrading whisper.cpp version.

---

## DEC-16 — Diarization embedding: MFCC via Accelerate (interim) → CoreML ECAPA-TDNN (production)

**Date:** 2026-03-29
**Task:** TASK-28
**Status:** accepted

**Context:** The ECAPA-TDNN speaker embedding stub (`voxema_ecapa_stub.c`) returns zero-filled 192-dim vectors for all audio. Zero vectors give cosine similarity = 0 for all pairs, which is always below the 0.75 matching threshold, so every segment receives a new "Speaker X" label — broken diarization. The architecture (DEC-2, DEC-5) specified ONNX Runtime as the inference backend. Discovery (2026-03-29) evaluated 5 approaches and found:

1. **ONNX Runtime via SPM** — same binary artifact failure mode as Sparkle (DEC-14 pattern); 350–400MB download per clean build.
2. **ONNX Runtime via direct dylib** — 85–100MB embedded binary requiring complex notarization and CI setup.
3. **CoreML direct** — no new runtime dependency; ECAPA-TDNN converts to ~22MB `.mlpackage` via one-time Python step; ANE acceleration identical to ORT+CoreML EP.
4. **MFCC statistics (no model file)** — pure Accelerate/vDSP; no download; within-session same-speaker cosine ~0.82–0.95; usable interim before model conversion.
5. **Apple Speech framework** — speaker diarization API not available on macOS.

**Decision (two-phase):**
- **Phase 1 (TASK-28, completed):** `voxema_ecapa_mfcc.c` — log-Mel filterbank mean + variance using `vDSP_fft_zrip`. No model file, no new dependencies beyond `Accelerate.framework`. Within-session speaker clustering only.
- **Phase 2 (TASK-29, implemented):** `voxema_ecapa_coreml.m` + `ecapa-tdnn.mlpackage` (SpeechBrain ECAPA-TDNN, Apache 2.0, ~22MB). One-time developer conversion via `coremltools` (`scripts/convert_ecapa_coreml.py`). MFCC fallback active when model file absent. The C API (`voxema_ecapa.h`) did not change. Updates DEC-2 "ONNX Runtime" → "CoreML direct".

**Why not ORT now:** DEC-14 documented SPM binary artifact failure. The ORT dylib path avoids SPM but introduces 90MB embedded binary, notarization complexity, and CI setup overhead. CoreML eliminates all of this while providing the same ANE delegation.

**Phase 2 implementation notes (TASK-29):**
- `voxema_ecapa_coreml.m` loads `ecapa-tdnn.mlpackage` via CoreML (ANE + GPU + CPU, `MLComputeUnitsAll`).
- Output tensor name discovered dynamically at init (first `MLFeatureTypeMultiArray` output).
- MFCC fallback is always initialised; CoreML activates only when the model file is present.
- ObjC objects (MLModel, NSString) stored in the C struct via `CFBridgingRetain`/`CFBridgingRelease`.
- `AppState.makeCoordinator()` resolves `Bundle.main.url(forResource:)` for the model; passes empty URL on miss → silent MFCC fallback.
- `EmbeddingEngine.loadModel` now uses `url.withUnsafeFileSystemRepresentation` (correct POSIX UTF-8 path for CoreML).

**Tradeoffs (Phase 2 CoreML):**
- Multi-speaker separation in single mixed stream: significantly improved over MFCC ✓
- Cross-session speaker recognition: supported (model is stateless, embeddings are comparable across sessions) ✓
- Developer prerequisite: one-time Python script execution + ~22MB model in bundle
- Without model file: transparent MFCC fallback, no user-visible degradation

---

## DEC-17 — Whisper initial_prompt: "Meeting transcript:" as context hint

**Status:** accepted
**Date:** 2026-04-01
**Source:** TASK-30 / Discovery FEAT-30

### Context

Whisper without context tends to hallucinate common phrases from its training data when handling silence or low-confidence audio. An `initial_prompt` anchors vocabulary and register to the meeting domain.

### Decision

Default `initialPrompt = "Meeting transcript:"` in `TranscribeConfiguration`. Passed via `whisper_full_params.initial_prompt` (nested `withCString` calls to keep both language and prompt C strings alive for the duration of `whisper_full()`). Users may override via `TranscribeConfiguration.initialPrompt`.

### Rationale

- Reduces hallucinations on quiet segments by priming Whisper toward meeting vocabulary.
- Prompt is applied to the first 30-second chunk only (Whisper.cpp behaviour).
- Zero additional memory or latency cost.
- Reversible: set `initialPrompt = nil` to restore default Whisper behaviour.

---

## DEC-18 — DiarizeStage: skip embedding for segments shorter than 1.5 s

**Status:** accepted
**Date:** 2026-04-01
**Source:** TASK-30 / Discovery FEAT-30

### Context

MFCC log-Mel statistics computed from fewer than ~24 frames (< 1.5 s at 10 ms hop) are numerically unreliable — variance estimates are high, cosine similarity is unstable. Such short segments frequently created spurious new speaker profiles or mis-matched the wrong existing speaker.

### Decision

`DiarizeConfiguration.minEmbeddingDuration = 1.5` (seconds). In `DiarizeStage.run()`, remote-channel segments shorter than this threshold reuse the last successfully matched speaker (`lastRemoteProfile`) instead of calling `engine.embed()`. If no previous speaker exists (first segment of a meeting), the embedding path runs regardless of duration.

### Rationale

- Eliminates the main source of spurious new speaker profiles in practice.
- No embedding quality change — same MFCC/CoreML engine.
- Configurable via `DiarizeConfiguration.minEmbeddingDuration` for future tuning.
- Confidence field set to 0.0 for short-segment assignments to distinguish them from real matches.
