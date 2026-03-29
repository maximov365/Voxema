# Decisions

<!-- Record significant technical decisions here. -->
<!-- Each decision should include: context, options considered, decision, and rationale. -->

| ID | Title | Status | Date |
|----|-------|--------|------|
| DEC-1 | Monetization: Subscription-only Pro with Lemon Squeezy | accepted | 2026-03-29 |
| DEC-3 | Backend stack: TypeScript (Hono) + Railway + PostgreSQL | accepted | 2026-03-29 |
| DEC-4 | Auto-update: Sparkle 2 via SPM + GitHub Pages/Releases | accepted | 2026-03-29 |
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
