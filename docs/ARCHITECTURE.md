# Architecture — Voxema

## Overview

Voxema is a native macOS application (SwiftUI, Apple Silicon) that processes meeting audio through a five-stage pipeline entirely on-device, with optional cloud LLM for the summarization stage only. A post-MVP backend provides managed cloud summarization for Pro tier users.

```
┌───────────────────────────────────────────────────────────────────┐
│                          Voxema.app                                │
│                                                                    │
│  ┌──────────────── PipelineCoordinator ─────────────────────────┐ │
│  │                                                               │ │
│  │  ┌────────┐  ┌───────────┐  ┌────────┐  ┌────────────────┐  │ │
│  │  │Capture │→ │Transcribe │→ │Diarize │→ │   Summarize    │  │ │
│  │  └────────┘  └───────────┘  └────────┘  │ local | cloud  │  │ │
│  │                                          └────────────────┘  │ │
│  └──────────────────────────────────┬────────────────────────────┘ │
│                                     ▼                              │
│  ┌──────────────────────────────────────────────────────────────┐  │
│  │              Export / Storage (SQLite via GRDB)               │  │
│  └──────────────────────────────────────────────────────────────┘  │
│                                                                    │
│  ┌─────────────┐  ┌──────────────┐  ┌──────────┐  ┌───────────┐  │
│  │ ModelManager │  │ VoiceProfile │  │ Settings │  │ Security  │  │
│  │             │  │    Store     │  │          │  │ (Keychain)│  │
│  └─────────────┘  └──────────────┘  └──────────┘  └───────────┘  │
│                                                                    │
│  ┌──────────────┐  ┌──────────────┐  ┌─────────────┐             │
│  │NetworkManager│  │LicenseManager│  │UpdateManager│             │
│  │  (NWPath)   │  │  (post-MVP)  │  │  (Sparkle) │             │
│  └──────────────┘  └──────────────┘  └─────────────┘             │
└───────────────────────────────────────────────────────────────────┘
```

---

## Pipeline Stages

### 1. Capture

**Responsibility:** Record two audio streams in parallel.

| Component | Technology | Purpose |
|---|---|---|
| SystemAudioCapture | ScreenCaptureKit | Capture remote participants' audio |
| MicrophoneCapture | AVAudioEngine | Capture local user's microphone |
| AudioSessionManager | AVAudioSession | Manage device selection, format negotiation |

- Two independent streams tagged `remote` and `local`
- Output format: 16kHz mono PCM per channel (Whisper.cpp requirement)
- Temporary audio files encrypted at rest via CryptoKit
- Recording state machine: `idle` → `recording` → `stopping` → `idle`

### 2. Transcribe

**Responsibility:** Convert audio to timestamped text segments.

| Component | Technology | Purpose |
|---|---|---|
| WhisperEngine | Whisper.cpp (Swift C interop) | Speech-to-text inference |
| TranscriptionCoordinator | Swift | Orchestrate per-channel transcription |

- Each channel transcribed independently
- Model loaded on demand, unloaded after completion
- Configurable model size: tiny (bundled), base, small (on-demand download)
- Output: `[TranscribedSegment]` per channel — each with start/end timestamps, text, confidence

### 3. Diarize

**Responsibility:** Attribute each segment to a speaker.

| Component | Technology | Purpose |
|---|---|---|
| SpeakerEmbedding | ECAPA-TDNN (ONNX Runtime, CoreML EP) | Extract voice embeddings |
| VoiceProfileStore | SQLite (encrypted) | Persist known speaker profiles |
| SpeakerMatcher | Cosine similarity | Match embeddings to known profiles |

- Local channel → always attributed to user (no embedding needed)
- Remote channel → extract embedding per segment, match against known profiles
- Match threshold: cosine similarity ≥ 0.75
- Unknown speakers assigned temporary labels (`Speaker A`, `Speaker B`, ...)
- User can rename/merge/delete profiles via UI
- ECAPA-TDNN runs via ONNX Runtime with CoreML Execution Provider for ANE/GPU delegation (DEC-2)

### 4. Summarize

**Responsibility:** Generate structured meeting summary from diarized transcript.

| Component | Technology | Purpose |
|---|---|---|
| PromptBuilder | Swift | Assemble dynamic prompt from template + context |
| SummaryProvider (protocol) | — | Abstract LLM interface |
| LocalProvider | llama.cpp (GGUF) | On-device LLM inference |
| CloudProvider | URLSession | Direct API client (user's own key) |
| VoxemaProxyProvider | URLSession | Proxied through Voxema backend |
| OnPremProvider | URLSession | Custom endpoint client |

**SummaryProvider** is a Swift protocol with **four** concrete implementations:

| Provider | Tier | Phase | How it works |
|---|---|---|---|
| LocalProvider | Free | MVP | llama.cpp with GGUF models, fully offline |
| CloudProvider (direct API) | Free | MVP | User's own Anthropic/OpenAI key stored in Keychain; app calls cloud LLM directly via URLSession |
| VoxemaProxyProvider | Pro | Post-MVP | Proxied through Voxema backend; backend holds API keys, applies server-side prompts, tracks usage |
| OnPremProvider | Enterprise | Post-MVP | User-specified corporate LLM endpoint |

- Provider selected in Settings; switching does not affect the pipeline
- CloudProvider and VoxemaProxyProvider send text transcript only (never audio), require per-session explicit user consent
- Both CloudProvider and VoxemaProxyProvider map to `provider_used: "cloud"` in pipeline contracts
- Output structure: `MeetingSummary` — summary text, key decisions, action items, open questions
- Prompt templates stored in `Resources/Prompts/` (maps to `prompts/` referenced in ARCHITECTURE_GUARDRAILS.md rule 7)

### 5. Export

**Responsibility:** Persist meeting data and produce export artifacts.

| Component | Technology | Purpose |
|---|---|---|
| MeetingStore | SQLite (GRDB) | Persist transcripts, summaries, metadata |
| MarkdownExporter | Swift | Generate .md files |
| JSONExporter | Swift | Generate .json files with full entity relationships |

- All meeting data in a single encrypted SQLite database
- Full-text search on transcripts and summaries
- JSON export preserves full entity relationships for downstream AI processing
- Deletion is complete and irreversible (hard delete, not soft)

---

## PipelineCoordinator

**Responsibility:** Orchestrate the five pipeline stages sequentially.

Referenced in `docs/PIPELINE_CONTRACTS.md` cross-stage rule #2: "Stages do not call each other directly — orchestrated by PipelineCoordinator."

| Concern | Behavior |
|---|---|
| Stage execution | Sequential: Capture → Transcribe → Diarize → Summarize → Export |
| Stage transitions | Each stage receives immutable input and produces new output |
| Error propagation | Errors raised at stage boundaries with structured error types |
| Progress reporting | Per-stage progress exposed to UI for processing indicator |
| Model lifecycle | Coordinates with ModelManager — models loaded before stage, unloaded after |
| Privacy | Error messages never contain transcript text, audio content, or PII |

PipelineCoordinator enforces the cross-stage rules defined in `docs/PIPELINE_CONTRACTS.md`:

1. Immutable input/output — no in-place mutation
2. No direct stage-to-stage calls
3. Structured error types at boundaries
4. Error messages never contain content or PII
5. Models loaded only during their stage, unloaded after (8GB RAM discipline)
6. Pipeline version bumped when contracts, stage order, or data representations change

---

## Cross-Cutting Concerns

### ModelManager

Manages lifecycle of ML models. Updated per DEC-2 (hybrid bundle + on-demand download).

| Concern | Detail |
|---|---|
| Bundled models | Whisper tiny (~75MB) + ECAPA-TDNN ONNX (~25MB) — shipped in DMG |
| Downloaded models | Whisper base (~142MB), small (~466MB), LLM (user-selected) |
| Model catalog | `models-manifest.json` — curated model list, SHA-256 checksums, RAM requirements, quality tier labels |
| Storage location | `~/Library/Application Support/Voxema/Models/` with subdirectories per model family |
| Integrity | SHA-256 verification on download and on load |
| Hardware detection | `ProcessInfo.processInfo.physicalMemory` for LLM recommendation |
| LLM format | GGUF via llama.cpp |
| ECAPA-TDNN runtime | ONNX Runtime with CoreML Execution Provider (ANE/GPU delegation) |
| Lazy loading | Models loaded only when their pipeline stage activates |
| Eager unloading | Models released from memory after stage completes |
| 8GB discipline | Enforces single-model-at-a-time policy on 8GB devices |
| Download UX | On-demand download with progress tracking; background download supported |
| Manifest updates | `models-manifest.json` updated alongside app via Sparkle |

**LLM selection UX (onboarding):**

| Device RAM | Recommended tier | Model (MVP curated list) |
|---|---|---|
| 8GB | "Good — faster, lighter" | Qwen 2.5 3B Q4_K_M (~1.9GB) |
| 16GB+ | "Better — recommended for your Mac" | Qwen 2.5 7B Q4_K_M (~4.5GB) |

User sees human-readable quality tiers, not model names. Model names shown as secondary detail. "Skip — I'll set this up later" option available for users who plan to use CloudProvider. Curated list will expand as models are benchmarked (DEC-2: LLM curated list is **evolving**).

### Settings

- Audio device selection (microphone)
- Whisper model size selection
- Summary provider selection (Local / CloudProvider / VoxemaProxyProvider *(post-MVP)* / OnPrem *(post-MVP)*)
- Cloud API key management (stored in Keychain) — for CloudProvider direct API mode
- LLM model selection (from curated manifest)
- Voice profile management
- Data management (export all, delete all)
- License tier display and subscription management (post-MVP)

### Security & Encryption

| Asset | Protection |
|---|---|
| Voice profile database | Encrypted via CryptoKit (AES-256-GCM) |
| Encryption key | Stored in Apple Keychain |
| Temporary audio files | Encrypted at rest via CryptoKit |
| API keys (cloud LLM) | Stored in Keychain, never in UserDefaults or files |
| License JWT (post-MVP) | Stored in Keychain |
| Logs | Structured logging with metadata only — no content |

### NetworkManager

**Responsibility:** Network reachability monitoring for offline-first behavior.

| Concern | Detail |
|---|---|
| Technology | NWPathMonitor (Network framework) |
| Reachability state | Exposes current connectivity status to dependent modules |
| Consumers | Summarize stage (cloud provider fallback), ModelManager (download management), LicenseManager (license refresh), UpdateManager (update checks) |
| Design | Passive monitoring — does not initiate connections, only reports state changes |

Used by the Summarize stage to implement offline-first degradation behavior defined in PRD:

| Scenario | Behavior |
|---|---|
| CloudProvider selected, no internet | Queue request, notify user, offer LocalProvider fallback |
| VoxemaProxyProvider, backend unreachable | Notify user, offer LocalProvider fallback, queue for retry |
| OnPremProvider endpoint unreachable | Retry with exponential backoff (max 3), then offer fallback |

### LicenseManager *(post-MVP)*

**Responsibility:** Subscription tier validation and feature gating. Introduced per DEC-1.

| Concern | Detail |
|---|---|
| Provider | Lemon Squeezy license key API |
| Validation | JWT-based; offline validation via embedded public key |
| Storage | JWT stored in Apple Keychain |
| Refresh | Online license refresh every 7 days when connected |
| Tiers | `.free` / `.pro` / `.enterprise` |
| Gating scope | UI/Settings layer only — pipeline stages unaffected |
| MVP impact | Not present at MVP — Free tier ships without gating code |

**Tier capabilities (gating reference):**

| Capability | Free | Pro | Enterprise |
|---|---|---|---|
| Full local pipeline | Yes | Yes | Yes |
| CloudProvider (direct API, own key) | Yes | Yes | Yes |
| VoxemaProxyProvider (managed cloud) | — | Yes | Yes |
| OnPremProvider | — | — | Yes |
| Server-side optimized prompts | — | Yes | Yes |
| Advanced export templates | — | Yes | Yes |

### UpdateManager *(MVP)*

**Responsibility:** Application updates for DMG distribution. Finalized per DEC-4 (FEAT-5 Discovery).

| Concern | Detail |
|---|---|
| Framework | Sparkle 2, integrated via Swift Package Manager |
| Appcast hosting | GitHub Pages (appcast XML) + GitHub Releases (DMG artifacts) |
| Update verification | Dual: EdDSA signature (Sparkle) + Apple code signing (notarization) |
| Code signing | Apple Developer ID certificate + Hardened Runtime + notarization |
| Update UX (MVP) | Sparkle built-in UI — check on launch, user-initiated check, notify + prompt to install |
| Update UX (post-MVP) | Optional custom SwiftUI UI for branded experience |
| Delta updates | Deferred to post-MVP (full DMG download ~150–180MB acceptable at early scale) |
| Check interval | Default Sparkle interval (~24h), plus manual "Check for Updates" menu item |
| Network dependency | Uses NetworkManager to check connectivity before update checks |
| Model catalog updates | `models-manifest.json` updated via Sparkle app releases (no separate model update mechanism) |
| Release pipeline | GitHub Actions: build → sign → notarize → DMG → EdDSA sign → GitHub Release → generate appcast → push to Pages |
| Critical key | EdDSA private key must be backed up securely — loss prevents future updates for existing users |

---

## Data Model

High-level entity relationships for meeting data. Struct definitions in `docs/PIPELINE_CONTRACTS.md`.

```
Meeting 1──N Segment
Meeting 1──0..1 Summary
Meeting N──N Speaker (through Segments)
Speaker 1──N Segment
```

| Entity | Key Fields | Storage |
|---|---|---|
| Meeting | meeting_id, title, recorded_at, duration, metadata | SQLite (GRDB) |
| Segment | segment_id, start_time, end_time, text, channel, speaker, confidence | SQLite (GRDB) |
| Speaker | speaker_id, label, is_user, voice_profile_id | SQLite (GRDB) + encrypted voice profile store |
| Summary | meeting_id, summary_text, key_decisions, action_items, open_questions, provider_used, model_name, generated_at | SQLite (GRDB) |

**Storage constraints:**

- Single encrypted SQLite database via GRDB
- Full-text search on transcript text and summary text
- Supports Markdown export (human-readable) and JSON export (machine-readable, full entity relationships preserved)
- Summary is optional per meeting (may not exist before summarization or if summarization fails)
- Complete deletion on user request — hard delete, irreversible

See `docs/PIPELINE_CONTRACTS.md` for detailed struct definitions (`AudioStream`, `TranscribedSegment`, `DiarizedSegment`, `SpeakerIdentity`, `MeetingSummary`, `Meeting`, `MeetingMetadata`, `ActionItem`).

---

## Data Flow

```
User clicks Record
       │
       ▼
  ┌─────────────────┐
  │     Capture      │
  │  system + mic    │
  └────────┬────────┘
           │ Two PCM audio files (encrypted)
           ▼
  ┌─────────────────┐
  │   Transcribe     │
  │  Whisper.cpp     │
  └────────┬────────┘
           │ [TranscribedSegment] per channel
           ▼
  ┌─────────────────┐
  │    Diarize       │
  │  ECAPA-TDNN      │
  └────────┬────────┘
           │ [DiarizedSegment] (speaker-attributed)
           ▼
  ┌─────────────────────────────────────┐
  │           Summarize                  │
  │                                      │
  │  ┌───────────┐  ┌──────────────┐  │
  │  │  Local     │  │Cloud/On-prem │  │
  │  │ (llama.cpp)│  │(direct API / │  │
  │  │           │  │ proxy/on-prem)│  │
  │  └───────────┘  └──────────────┘  │
  └────────┬────────────────────────────┘
           │ MeetingSummary
           ▼
  ┌─────────────────┐
  │     Export       │
  │  SQLite + files  │
  └─────────────────┘
           │
           ▼
  User views summary, exports .md / .json
  Temporary audio files deleted
```

---

## Backend Services Architecture *(post-MVP)*

> The MVP operates entirely without a backend. Backend services are required only for Pro and Enterprise tiers. This section is included because backend design decisions affect VoxemaProxyProvider, monetization, and privacy contracts.

### Stack (DEC-3)

| Component | Technology |
|---|---|
| Language / Framework | TypeScript with Hono |
| ORM | Drizzle ORM (type-safe) |
| Database | PostgreSQL (managed by Railway) |
| Hosting | Railway (usage-based, ~$15–25/mo at launch) |
| Hosting upgrade path | Railway → Fly.io at scale or for EU data residency |

### Backend Components

| Service | Responsibility |
|---|---|
| Auth service | Apple Sign In (server-side validation) + Email OTP. JWT tokens with 7-day refresh. |
| Billing / Webhook handler | Lemon Squeezy webhook integration (official TypeScript SDK). License key validation with JWT offline support. |
| LLM Proxy | Prompt-wrapping proxy with SSE streaming. Primary: Claude Haiku 4.5 (~$0.27/user/mo at 20 meetings). Fallback: GPT-4o-mini (~$0.04/user/mo). Post-response token counting, database-backed rate limiting. |
| Usage tracker | Minutes of audio processed via cloud, LLM tokens consumed, billing enforcement |
| Admin Dashboard | Internal-only (Pro launch phase). User list, subscription status, usage stats, cost monitoring. Same Hono backend serving lightweight frontend. |

### Client ↔ Backend Flow (VoxemaProxyProvider)

```
┌──────────────┐        ┌────────────────────┐        ┌───────────┐
│  Voxema.app  │  TLS   │  Voxema Backend     │  TLS   │ Cloud LLM │
│              │───────→│                    │───────→│ (Anthropic/│
│ VoxemaProxy  │        │ Auth → Rate limit  │        │  OpenAI)  │
│  Provider    │←───────│ → Prompt wrap      │←───────│           │
│              │  SSE   │ → Token count      │  SSE   │           │
└──────────────┘        └────────────────────┘        └───────────┘
                              │
                              │ Stores only:
                              │ - User identity
                              │ - Subscription status
                              │ - Usage counters
                              │ - Billing records
                              │
                              │ Never stores:
                              │ - Audio, transcripts,
                              │   summaries, or PII
```

### Privacy Constraints (Backend)

| Constraint | Detail |
|---|---|
| Content-stateless | Backend stores no transcripts, summaries, audio, or meeting PII |
| Transit only | Transcript text passes through LLM proxy in transit only, never persisted |
| Stored data | User identity, subscription status, usage counters, billing records only |
| Encryption | All transcript transmission encrypted via TLS |
| Server logs | Must not contain transcript text or any meeting content |

---

## Key Architectural Decisions

| Decision | Rationale | Reference |
|---|---|---|
| Two-channel capture (not mixed) | Enables reliable speaker attribution — local channel is always the user | — |
| Whisper.cpp (not Apple Speech) | Consistent quality, offline, supports multiple languages, open-source | — |
| ECAPA-TDNN for speaker ID | State-of-the-art speaker verification, small model footprint | — |
| ONNX Runtime with CoreML EP for ECAPA-TDNN | ANE/GPU delegation for efficient inference on Apple Silicon | DEC-2 |
| SQLite (GRDB) for all storage | Single-file database, no server, encrypts easily, excellent Swift support | — |
| SummaryProvider as protocol (4 implementations) | Clean abstraction enables local/cloud-direct/cloud-proxy/on-prem without pipeline changes | — |
| CloudProvider dual-mode (direct API + Voxema proxy) | Direct API for MVP/Free (user's own key); proxy for Pro (managed experience) | DEC-1, FEAT-4 |
| Lazy model loading + eager unloading | Critical for 8GB devices — cannot hold Whisper + LLM simultaneously | — |
| Hybrid bundle + on-demand download | 150–180MB DMG with immediate functionality; larger models downloaded on demand | DEC-2 |
| `models-manifest.json` with SHA-256 | Curated model catalog with integrity verification and hardware-based recommendations | DEC-2 |
| Subscription-only Pro with Lemon Squeezy | JWT offline validation aligns with offline-first; MoR handles tax compliance | DEC-1 |
| LicenseManager gating at UI layer only | Pipeline stages unaffected by tier — gating is a UI/Settings concern | DEC-1 |
| TypeScript (Hono) + Railway backend | Fastest dev velocity for solo dev; Lemon Squeezy TS SDK; content-stateless | DEC-3 |
| PostgreSQL for backend (not SQLite) | Concurrent writes from LLM proxy requests require multi-writer support | DEC-3 |
| No real-time transcription in MVP | Simplifies architecture, avoids streaming complexity, focuses on quality | — |
| Sparkle 2 via SPM for auto-update | Standard for macOS DMG apps; GitHub Pages/Releases for zero-cost hosting; EdDSA + Apple code signing dual verification | DEC-4 |

---

## File Structure (planned)

```
Voxema/
├── App/                        # SwiftUI app entry, scenes, navigation
├── Features/
│   ├── Recording/              # Capture UI and state management
│   ├── MeetingLibrary/         # List, search, detail views
│   ├── MeetingDetail/          # Transcript + summary view
│   ├── Settings/               # Preferences, model management, tier display
│   └── Onboarding/             # Permission setup + model selection flow
├── Pipeline/
│   ├── Coordinator/            # PipelineCoordinator — stage orchestration
│   ├── Capture/                # SystemAudioCapture, MicrophoneCapture
│   ├── Transcribe/             # WhisperEngine, TranscriptionCoordinator
│   ├── Diarize/                # SpeakerEmbedding, VoiceProfileStore, SpeakerMatcher
│   ├── Summarize/              # PromptBuilder, SummaryProvider protocol + 4 implementations
│   │   ├── SummaryProvider.swift       # Protocol definition
│   │   ├── LocalProvider.swift         # llama.cpp (GGUF)
│   │   ├── CloudProvider.swift         # Direct API (user's own key)
│   │   ├── VoxemaProxyProvider.swift   # Voxema backend proxy (post-MVP)
│   │   └── OnPremProvider.swift        # Custom endpoint (post-MVP)
│   └── Export/                 # MeetingStore, MarkdownExporter, JSONExporter
├── Core/
│   ├── Models/                 # Data models (Meeting, Segment, Speaker, Summary)
│   ├── Storage/                # Database layer (GRDB wrapper)
│   ├── Security/               # Encryption, Keychain helpers
│   ├── ModelManager/           # ML model lifecycle, models-manifest.json handling
│   ├── Networking/             # NetworkManager (NWPathMonitor), reachability
│   ├── LicenseManager/         # JWT validation, tier management (post-MVP)
│   ├── UpdateManager/          # Sparkle integration, version checks
│   └── Logging/                # Structured logging (no content in logs)
├── Resources/
│   ├── Prompts/                # Summary prompt templates
│   ├── Models/                 # Bundled models (Whisper tiny, ECAPA-TDNN ONNX)
│   ├── models-manifest.json    # Curated model catalog
│   └── Assets/                 # App icons, images
└── Tests/
    ├── PipelineTests/
    ├── CoreTests/
    └── FeatureTests/
```

---

## Constraints

| Constraint | Detail |
|---|---|
| Language | Swift (with C++ bridging for Whisper.cpp and llama.cpp via Swift C interop) |
| UI Framework | SwiftUI — no third-party UI frameworks, no Electron, no web views |
| Minimum macOS | 13.0 (Ventura) — required for ScreenCaptureKit audio-only capture API |
| Hardware | Apple Silicon only — ML models optimized for Neural Engine / GPU via Metal |
| Build toolchain | Swift 5.9+ / Xcode 15+ |
| Database (client) | SQLite via GRDB |
| Database (backend) | PostgreSQL via Drizzle ORM (post-MVP) |
| Dependencies | All dependencies must be auditable (prefer source-available) |
| Distribution | Direct download (DMG) for MVP |
| Update mechanism | Sparkle 2 via SPM. Appcast on GitHub Pages, DMGs on GitHub Releases. EdDSA + Apple code signing. See DEC-4. |
| Model packaging | Hybrid: bundle Whisper tiny + ECAPA-TDNN ONNX in DMG (~150–180MB). Larger models on demand. See DEC-2. |
| Backend stack | TypeScript (Hono) + PostgreSQL (Drizzle) on Railway. Post-MVP only. See DEC-3. |
| Memory budget | ≤ 4 GB peak during any single pipeline stage. Sequential stage execution with model unloading on 8GB devices. |
| Privacy | Audio never leaves device. Transcript to cloud only with per-session explicit consent. Backend is content-stateless. |
