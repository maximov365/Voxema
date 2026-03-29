# Feature Map — Voxema

This document defines capability blocks, their dependencies, and the canonical Capability Index used for `capability_id` references in tasks and features.

---

## Capability Index

### Pipeline Stages

| ID | Capability | Stage | MVP | Description |
|---|---|---|---|---|
| `CAPTURE` | Audio Capture | capture | Yes | System audio (ScreenCaptureKit) + microphone (AVAudioEngine) two-channel recording |
| `TRANSCRIBE` | Speech-to-Text | transcribe | Yes | Whisper.cpp local transcription, per-channel, timestamped segments |
| `DIARIZE` | Speaker Identification | diarize | Yes | ECAPA-TDNN voice embeddings, cosine similarity matching, speaker clustering |
| `SUMMARIZE` | Meeting Summarization | summarize | Yes | LLM-powered structured summary via SummaryProvider protocol |
| `EXPORT` | Storage & Export | export | Yes | SQLite persistence (GRDB), Markdown and JSON export, full-text search |

### Cross-Cutting (Client)

| ID | Capability | Stage | MVP | Description |
|---|---|---|---|---|
| `PIPELINE-COORD` | Pipeline Coordinator | cross-cutting | Yes | Sequential stage orchestration, progress reporting, error propagation, model lifecycle coordination |
| `MODELS` | Model Management | cross-cutting | Yes | Hybrid bundle + on-demand download, models-manifest.json, SHA-256 verification, hardware-based LLM recommendation (DEC-2) |
| `SECURITY` | Security & Encryption | cross-cutting | Yes | CryptoKit encryption at rest, Keychain integration, privacy enforcement, structured logging |
| `NETWORKING` | Network Manager | cross-cutting | Yes | NWPathMonitor reachability monitoring, offline-first behavior, connectivity state for dependent modules |
| `UPDATE` | Update Manager | cross-cutting | Yes | Sparkle 2 auto-update, GitHub Pages appcast, EdDSA + code signing verification (DEC-4) |
| `VOICE-PROFILES` | Voice Profile Management | diarize | Yes | Speaker database CRUD, merge, rename; encrypted storage |
| `PROMPTS` | Prompt Management | summarize | Yes | Prompt templates in Resources/Prompts/, few-shot examples, dynamic prompt assembly |
| `LICENSE` | License Manager | cross-cutting | **No** | Lemon Squeezy JWT validation, tier management (.free/.pro/.enterprise), feature gating at UI layer (DEC-1) |

### UI

| ID | Capability | Stage | MVP | Description |
|---|---|---|---|---|
| `UI-ONBOARDING` | Onboarding | cross-cutting | Yes | Permission setup (Screen Recording + Microphone), mic selection, Whisper model selection, summarization model selection (DEC-2) |
| `UI-RECORDING` | Recording UI | cross-cutting | Yes | Start/stop controls, visual recording indicator, processing progress |
| `UI-LIBRARY` | Meeting Library | cross-cutting | Yes | Meeting list with full-text search, navigation |
| `UI-DETAIL` | Meeting Detail View | cross-cutting | Yes | Transcript with speaker labels + summary display, export triggers |
| `UI-SETTINGS` | Settings | cross-cutting | Yes | Model selection, provider selection, audio device, API key management. Post-MVP: license tier display, VoxemaProxyProvider config |

### Backend (Post-MVP)

| ID | Capability | Stage | MVP | Description |
|---|---|---|---|---|
| `BACKEND-AUTH` | Backend Authentication | backend | **No** | Apple Sign In + Email OTP, JWT tokens with 7-day refresh (DEC-3) |
| `BACKEND-BILLING` | Backend Billing & Usage | backend | **No** | Lemon Squeezy webhook integration, subscription management, license key validation, per-user usage tracking (minutes, tokens, cost) (DEC-1, DEC-3) |
| `BACKEND-PROXY` | Backend LLM Proxy | backend | **No** | VoxemaProxyProvider backend: prompt-wrapping proxy, SSE streaming, post-response token counting, database-backed rate limiting (DEC-3) |
| `BACKEND-ADMIN` | Admin Dashboard | backend | **No** | Internal tool: user list, subscription status, usage stats, cost monitoring (DEC-3) |

---

## Dependency Map

```
                     ┌─────────────────┐
                     │  UI-ONBOARDING   │
                     └────────┬────────┘
                              │ permissions + model selection
                              ▼
┌────────────┐    ┌─────────────────────┐    ┌────────────┐
│ NETWORKING │    │   PIPELINE-COORD     │    │  SECURITY  │
│ (NWPath)   │    │  (orchestrates all   │    │ (Keychain, │
│            │    │   pipeline stages)   │    │  CryptoKit)│
└──────┬─────┘    └──┬──┬──┬──┬──┬──────┘    └──────┬─────┘
       │             │  │  │  │  │                   │
       │    ┌────────┘  │  │  │  └────────┐          │
       │    ▼           │  │  │           ▼          │
       │ CAPTURE ───────┘  │  │        EXPORT ◄──────┤
       │    │              │  │          │ ▲          │
       │    ▼              │  │          │ │          │
       │ TRANSCRIBE ◄──MODELS │          │ │          │
       │    │           ▲  │  │          │ │          │
       │    ▼           │  │  │          │ │          │
       │ DIARIZE ◄──────┤  │  │          │ │          │
       │    │   ◄── VOICE-PROFILES       │ │          │
       │    ▼           │  │             │ │          │
       ├──► SUMMARIZE ◄─┘  │             │ │          │
       │    │   ◄── PROMPTS│             │ │          │
       │    └──────────────┘─────────────┘ │          │
       │                                   │          │
       │    ┌──────────────────────────────┘          │
       │    ▼                                         │
       │ UI-LIBRARY ──► UI-DETAIL                     │
       │                                              │
       │ UI-RECORDING ◄── CAPTURE                     │
       │                                              │
       │ UI-SETTINGS ◄── MODELS + SECURITY            │
       │                                              │
       ├──► UPDATE (Sparkle 2, DEC-4)                 │
       │                                              │
       │         ─── Post-MVP ───────────────         │
       │                                              │
       ├──► LICENSE ◄── BACKEND-BILLING               │
       │       │                                      │
       │       ▼                                      │
       │    UI-SETTINGS (tier display)                │
       │                                              │
       │ BACKEND-AUTH ◄── BACKEND-BILLING             │
       │                   │                          │
       │ BACKEND-PROXY ◄───┤                          │
       │                   │                          │
       │ BACKEND-ADMIN ◄───┘                          │
       │                                              │
       └──────────────────────────────────────────────┘
```

### Dependency Rules

**Pipeline chain (sequential, enforced by PIPELINE-COORD):**

- `TRANSCRIBE` depends on `CAPTURE` (needs audio streams)
- `DIARIZE` depends on `TRANSCRIBE` (needs text segments)
- `SUMMARIZE` depends on `DIARIZE` (needs speaker-attributed transcript)
- `EXPORT` follows `SUMMARIZE` in the pipeline sequence. Receives `[DiarizedSegment]` (required) and `MeetingSummary` (optional — may not exist if summarization was skipped or failed)

**Cross-cutting dependencies:**

- `PIPELINE-COORD` orchestrates all five pipeline stages — no direct stage-to-stage calls
- `MODELS` is required by `TRANSCRIBE` (Whisper), `DIARIZE` (ECAPA-TDNN), and `SUMMARIZE` (LLM) for model lifecycle
- `SECURITY` is required by `CAPTURE` (audio encryption), `DIARIZE` (voice profile encryption), `EXPORT` (database encryption), and `UI-SETTINGS` (Keychain for API keys)
- `VOICE-PROFILES` is required by `DIARIZE` (speaker database)
- `PROMPTS` is required by `SUMMARIZE` (prompt templates)
- `NETWORKING` is required by `SUMMARIZE` (cloud provider fallback), `MODELS` (download management), `UPDATE` (update checks), and `LICENSE` (license refresh, post-MVP)
- `UPDATE` depends on `NETWORKING` for connectivity checks

**UI dependencies:**

- `UI-ONBOARDING` is the entry point — required before any recording
- `UI-RECORDING` depends on `CAPTURE`
- `UI-LIBRARY` depends on `EXPORT`
- `UI-DETAIL` depends on `UI-LIBRARY`
- `UI-SETTINGS` depends on `MODELS` and `SECURITY`

**Post-MVP dependencies:**

- `LICENSE` depends on `NETWORKING` (periodic license refresh) and `BACKEND-BILLING` (license key issuance)
- `BACKEND-BILLING` depends on `BACKEND-AUTH` (user identity for subscription management)
- `BACKEND-PROXY` depends on `BACKEND-AUTH` (authenticated requests) and `BACKEND-BILLING` (tier enforcement, rate limiting)
- `BACKEND-ADMIN` depends on `BACKEND-AUTH` (admin access) and `BACKEND-BILLING` (subscription data)

---

## MVP Scope

Aligned with PRD "MVP Scope" section. The MVP delivers: **Record → Transcribe → Identify Speakers → Summarize → View & Export**.

### MVP Capabilities

| ID | Scope |
|---|---|
| `CAPTURE` | Full — system audio + microphone, two-channel, encrypted temp files |
| `TRANSCRIBE` | Full — Whisper.cpp (tiny bundled, base/small on-demand download) |
| `DIARIZE` | Basic — local channel = user, remote = embedding match or temp label |
| `SUMMARIZE` | LocalProvider (llama.cpp, offline) + CloudProvider (direct API, user's own key) |
| `EXPORT` | SQLite persistence + Markdown export + JSON export (full entity relationships) |
| `PIPELINE-COORD` | Full — sequential orchestration, progress reporting, error propagation |
| `MODELS` | Full — hybrid bundle, on-demand download, models-manifest.json, SHA-256, hardware recommendation (DEC-2) |
| `SECURITY` | Full — CryptoKit encryption at rest, Keychain integration, structured logging |
| `NETWORKING` | Full — NWPathMonitor reachability, offline-first degradation behavior |
| `UPDATE` | Full — Sparkle 2 auto-update, appcast, EdDSA + code signing verification (DEC-4) |
| `VOICE-PROFILES` | Basic CRUD — create, rename, merge, delete speaker profiles |
| `PROMPTS` | Default templates — summary, key decisions, action items, open questions |
| `UI-ONBOARDING` | Full — permission setup, mic selection, Whisper model, LLM model selection (DEC-2) |
| `UI-RECORDING` | Full — start/stop, visual indicator, processing progress |
| `UI-LIBRARY` | Full — meeting list with full-text search |
| `UI-DETAIL` | Full — transcript + summary view, export triggers |
| `UI-SETTINGS` | Core — model selection, provider selection (Local/CloudProvider), audio device, API key |

### Post-MVP Capabilities

| ID | Scope | Tier |
|---|---|---|
| `SUMMARIZE` | VoxemaProxyProvider (managed cloud, no user API key) | Pro |
| `SUMMARIZE` | OnPremProvider (custom corporate endpoint) | Enterprise |
| `EXPORT` | Advanced export templates | Pro |
| `DIARIZE` | Advanced clustering, cross-meeting profile improvement | All |
| `UI-DETAIL` | Inline transcript editing, summary regeneration | All |
| `UI-SETTINGS` | License tier display, VoxemaProxyProvider config, subscription management | Pro/Enterprise |
| `LICENSE` | Lemon Squeezy JWT validation, tier gating at UI layer | Pro/Enterprise |
| `BACKEND-AUTH` | Apple Sign In + Email OTP, session management | Pro/Enterprise |
| `BACKEND-BILLING` | Lemon Squeezy webhooks, subscription management, usage tracking | Pro/Enterprise |
| `BACKEND-PROXY` | LLM proxy with server-side prompts, SSE streaming, rate limiting | Pro |
| `BACKEND-ADMIN` | Internal admin dashboard for Pro launch phase | Internal |
| `UPDATE` | Custom SwiftUI update UI, delta updates | All |

### Key MVP scope clarifications

- **JSON export IS in MVP** — both Markdown and JSON export are MVP per PRD
- **CloudProvider (direct API) IS in MVP** — user's own Anthropic/OpenAI key, Free tier
- **VoxemaProxyProvider is NOT in MVP** — requires backend (post-MVP, Pro tier)
- **OnPremProvider is NOT in MVP** — post-MVP, Enterprise tier
- **LicenseManager is NOT in MVP** — no monetization code at MVP; Free tier ships as-is
- **Backend services are NOT in MVP** — the MVP operates entirely without a backend
- **Sparkle/UpdateManager IS in MVP** — DMG distribution requires built-in update mechanism (DEC-4)
- **PipelineCoordinator IS in MVP** — required for stage orchestration
- **NetworkManager IS in MVP** — required for offline-first cloud fallback behavior

---

## Suggested Implementation Phases

Ordering reflects dependency chains and risk reduction. Actual implementation order may be refined by Architect when planning tasks.

### Phase 1: Core Pipeline (foundation)

| ID | Rationale |
|---|---|
| `PIPELINE-COORD` | Foundation — all stages depend on the orchestrator |
| `CAPTURE` | First pipeline stage; enables audio recording |
| `TRANSCRIBE` | Second pipeline stage; depends on CAPTURE output |
| `MODELS` | Required by TRANSCRIBE (Whisper), and later by DIARIZE and SUMMARIZE. Depends on NETWORKING for on-demand downloads. |
| `SECURITY` | Required by CAPTURE (audio encryption) and all encrypted storage |
| `NETWORKING` | Required by MODELS (download management), SUMMARIZE (cloud fallback), UPDATE (update checks). Must exist from Phase 1. |

**Delivers:** Record audio and transcribe it. Foundation for all subsequent stages.

### Phase 2: Speaker & Summary (intelligence layer)

| ID | Rationale |
|---|---|
| `DIARIZE` | Third pipeline stage; depends on TRANSCRIBE + VOICE-PROFILES |
| `VOICE-PROFILES` | Required by DIARIZE for speaker matching |
| `SUMMARIZE` | Fourth pipeline stage; LocalProvider + CloudProvider (direct API) |
| `PROMPTS` | Required by SUMMARIZE for prompt template assembly |

**Delivers:** Full pipeline — speakers identified, meeting summarized with decisions and action items.

### Phase 3: Storage & UI (user-facing)

| ID | Rationale |
|---|---|
| `EXPORT` | Fifth pipeline stage; SQLite persistence, Markdown + JSON export |
| `UI-LIBRARY` | Meeting list with search — primary navigation for stored meetings |
| `UI-DETAIL` | Transcript + summary display — the core read experience |
| `UI-RECORDING` | Start/stop controls — the core recording interaction |

**Delivers:** Users can record, view results, browse history, and export meetings.

### Phase 4: Setup & Polish (complete MVP experience)

| ID | Rationale |
|---|---|
| `UI-ONBOARDING` | Permission setup + model selection — required for first-run activation |
| `UI-SETTINGS` | Preferences — model, provider, audio device, API key management |
| `UPDATE` | Sparkle 2 auto-update — required for DMG distribution (DEC-4) |

**Delivers:** Complete MVP — polished first-run, settings, update mechanism.

### Phase 5: Monetization (post-MVP)

| ID | Rationale |
|---|---|
| `LICENSE` | Client-side JWT validation + tier gating (DEC-1) |
| `BACKEND-AUTH` | User identity — required by all backend services (DEC-3) |
| `BACKEND-BILLING` | Subscription management — depends on AUTH (DEC-1, DEC-3) |
| `BACKEND-PROXY` | Managed cloud LLM for Pro — depends on AUTH + BILLING (DEC-3) |
| `BACKEND-ADMIN` | Internal dashboard — depends on AUTH + BILLING (DEC-3) |

**Delivers:** Pro tier with managed cloud summarization, subscription billing, admin tools.

---

## Decision References

| Capability | Decision | Key Detail |
|---|---|---|
| `MODELS` | DEC-2 | Hybrid bundle: Whisper tiny + ECAPA-TDNN bundled; larger models on demand. models-manifest.json with SHA-256. Hardware-based LLM recommendation. |
| `SUMMARIZE` | DEC-1 | CloudProvider (direct API) stays in Free tier. VoxemaProxyProvider is Pro, post-MVP. |
| `LICENSE` | DEC-1 | Lemon Squeezy JWT offline validation. UI-layer gating only — pipeline unaffected. No monetization code at MVP. |
| `UPDATE` | DEC-4 | Sparkle 2 via SPM. GitHub Pages appcast + GitHub Releases DMGs. EdDSA + Apple code signing. |
| `BACKEND-*` | DEC-3 | TypeScript (Hono) + PostgreSQL (Drizzle) on Railway. Content-stateless. |
| `UI-ONBOARDING` | DEC-2 | Summarization model selection step with hardware-based recommendation and human-readable quality tiers. |

