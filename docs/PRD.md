# Product Requirements — Voxema

## Vision

Voxema is a privacy-first macOS application for Apple Silicon that records, transcribes, and analyzes work meetings end-to-end. It captures both sides of any audio/video call — system audio (the remote participants) and the user's microphone — as two separate channels, transcribes them locally, identifies who said what, and generates structured meeting summaries with action items.

The core promise: **meeting intelligence without your data leaving your device**.

---

## Problem

Knowledge workers spend hours in meetings but lose most of the value afterward. Notes are incomplete, action items get lost, and decisions are forgotten.

Existing solutions (Otter.ai, Fireflies, Grain) require sending audio to the cloud, which is unacceptable for:
- Companies with data residency requirements
- Freelancers discussing sensitive client projects
- Regulated industries (legal, healthcare, finance)
- Privacy-conscious individuals

There is no high-quality, fully local meeting intelligence tool for macOS.

---

## Target Users

| Segment | Need |
|---|---|
| Freelancers | Record and summarize client calls without third-party cloud services |
| Managers | Track decisions and action items across recurring team meetings |
| Distributed teams | Searchable meeting archive with speaker attribution |
| Privacy-conscious enterprises | On-device meeting intelligence with zero data exfiltration |

---

## Product Principles

1. **Privacy by architecture** — Audio never leaves the device. Transcript goes to cloud only with explicit opt-in.
2. **User is in control** — Recording starts/stops on explicit action. No background recording. Full data deletion on request.
3. **Works offline** — Core pipeline (capture → transcribe → diarize → summarize) functions without internet via local models. See [Offline-First UX](#offline-first-ux) for detailed behavior.
4. **Progressive quality** — Local models for privacy; cloud models available for users who opt in to better summaries.
5. **Minimal friction** — One click to start recording, one click to stop. Summary appears automatically.
6. **Graceful degradation** — Every core workflow must complete with a useful result even without internet. Cloud features enhance quality but are never blocking.

---

## Monetization Model

Three tiers, structured around privacy boundaries. Specifics below reflect Discovery **FEAT-1** (pricing, gating, payments, and go-to-market).

### Pricing

| Tier | Monthly | Annual | Effective Monthly |
|------|---------|--------|-------------------|
| Free | $0 | $0 | $0 |
| Pro | $12/mo | $96/yr | $8/mo |
| Enterprise | Custom | Custom | Custom |

### Feature gating

**Free tier (MVP and beyond)** — no limits on local functionality:

- Full pipeline: capture → transcribe → diarize → summarize → export
- LocalProvider (llama.cpp) — unlimited
- CloudProvider (direct API) with user's own key — unlimited
- All Whisper model sizes (MVP ships with tiny/base/small; medium available post-MVP based on performance validation)
- Meeting library, search, all export formats
- Voice profile management
- No meeting count limits, no time limits

**Pro tier (post-MVP)** — everything in Free, plus:

- Managed cloud LLM summarization (Voxema proxy) — no API key management
- Server-side optimized prompts (better summaries, iterate without app updates)
- Priority access to latest/largest cloud models
- Advanced export templates
- Email support

**Enterprise tier (later phase)** — everything in Pro, plus:

- OnPremProvider support (custom LLM endpoints)
- Volume licensing, SSO/SCIM
- Admin dashboard, custom deployment support

**CloudProvider (direct API) stays in Free tier** — gating it would feel hostile to the privacy audience. Pro sells convenience + quality, not access.

### Payment infrastructure

**Lemon Squeezy** — merchant of record (handles tax compliance); built-in license key API with JWT-based offline validation; **5% + $0.50** fee; offline-friendly: JWT with embedded public key enables validation without network.

### Technical gating approach

- **MVP:** no monetization code — Free tier ships as-is
- **Post-MVP:** `LicenseManager` module in `Core/`, JWT token stored in Keychain
- Feature gating at UI/Settings layer — pipeline stages unaffected
- `VoxemaProxyProvider` added as new SummaryProvider conformance
- Periodic online license refresh (every 7 days when connected)

### Go-to-market path

1. **F&F Beta** — Free tier only, direct DMG, collect pipeline quality feedback
2. **Public Beta** — ProductHunt/HN launch, Free tier, build audience
3. **Pro Launch** — Enable Pro with Lemon Squeezy checkout on voxema.com
4. **Mac App Store** — evaluate after Pro tier is stable (30% cut vs discoverability)

**Privacy guardrails per tier:**

- **Free:** All processing on-device by default. CloudProvider (direct API) available with user's own key — network call for summarization text only, with per-session consent.
- **Pro:** Audio never leaves device. Only text transcript sent to Voxema backend for cloud LLM summarization, only with per-session explicit consent. Transcript passes through the backend to the cloud LLM encrypted in transit (TLS), never persisted on Voxema's servers. No persistent cloud storage of transcripts.
- **Enterprise:** All processing within corporate network. OnPremProvider endpoints configured by IT. No data leaves corporate perimeter.

> **Note:** Pricing validated against market data (Otter $8.33/mo, Krisp $8/mo, Fireflies $10/mo, Superwhisper $8.49/mo annual rates). Subject to adjustment after F&F beta user testing.

---

## Core Capabilities

### Recording
- Capture system audio (remote participants) via ScreenCaptureKit
- Capture microphone (user) via AVAudioEngine
- Two channels maintained separately throughout processing
- Visual recording indicator always visible
- Start/stop controlled exclusively by explicit user action

### Transcription
- Local speech-to-text via Whisper.cpp
- Per-channel transcription (remote and local independently)
- Timestamped segments
- Multiple Whisper model sizes for quality/performance tradeoff

### Speaker Identification
- Local channel automatically attributed to the user
- Remote channel: speaker clustering via ECAPA-TDNN voice embeddings
- Matching against a local database of known voice profiles (SQLite + cosine similarity)
- Unknown speakers get temporary labels; user can rename
- Voice profiles stored encrypted — biometric data

### Summarization
- Full transcript assembled with speaker labels and timestamps
- Dynamic prompt with template + project context + few-shot examples from user corrections
- Provider options:
  - **LocalProvider** — llama.cpp, fully offline
  - **CloudProvider (direct API)** — MVP. User provides their own Anthropic/OpenAI API key (stored in Keychain). App calls cloud LLM directly via URLSession. Text transcript only (never audio), per-session explicit user consent required.
  - **CloudProvider (Voxema proxy)** — Post-MVP, Pro tier. Cloud LLM access proxied through Voxema's backend. Backend handles API keys, server-side optimized prompts, and per-user usage tracking. User does not manage API keys. Per-session explicit consent still required.
  - **OnPremProvider** — user-specified endpoint for corporate deployments
- Structured output: summary, key decisions, action items, open questions

### Storage & Export
- All data persisted locally in SQLite (via GRDB)
- Meeting library with full-text search on transcripts and summaries
- Export to Markdown (human-readable) and JSON (machine-readable, full entity relationships preserved)
- Data format supports both quick export to any system (wiki, notes apps) and downstream AI processing (third-party meeting file processors, future analysis modes)
- Full data deletion on user request (irreversible)

### Data Model

High-level entity relationships for meeting data:

| Entity | Key Fields | Description |
|---|---|---|
| **Meeting** | title, recorded_at, duration, metadata | Top-level entity representing a single recorded meeting |
| **Segment** | start_time, end_time, text, channel, confidence | A timestamped piece of transcribed text belonging to a Meeting |
| **Speaker** | label, is_user, voice_profile_id | Identity associated with segments. Known speakers from VoiceProfileStore or temporary labels |
| **Summary** | summary_text, key_decisions, action_items, open_questions, provider_used | Structured output generated for a Meeting |

**Relationships:**
- Meeting 1→N Segments
- Meeting 1→0..1 Summary (summary is optional — may not exist before summarization runs or if summarization fails)
- Meeting N→N Speakers (through Segments)
- Speaker 1→N Segments

**Storage constraints:**
- Maps directly to SQLite schema (via GRDB)
- Must support full-text search on transcript text and summary text
- Must support both human-readable export (Markdown) and machine-readable export (JSON with full entity relationships preserved) to enable downstream AI processing

---

## Onboarding Flow

For a macOS app using ScreenCaptureKit, onboarding is critical for activation. Without correct permissions, the app cannot function.

**Goal:** Minimize drop-off between install and first recording (ties directly to the Activation success metric).

### Permission Setup Sequence

1. **Welcome screen** — Explain what Voxema does and why it needs permissions (two-channel concept: system audio = remote participants, microphone = you)
2. **Screen Recording permission** — Guide user to grant Screen Recording access in macOS System Settings. Provide visual instructions specific to the macOS version.
3. **Microphone permission** — Standard macOS microphone permission prompt via AVAudioEngine. Explain why both permissions are needed.
4. **Permission verification** — Check that both permissions are granted before allowing first recording. Show clear status indicators (granted / not granted) for each permission.
5. **Configuration** — Microphone device selection, transcription quality (Whisper model size), and summarization model setup. Sensible defaults pre-selected based on detected hardware (RAM via `ProcessInfo.processInfo.physicalMemory`).
   - **Summarization model step:** App detects device RAM and recommends the best-fit local model. User sees quality tiers described in plain language (e.g. "Good — faster, lighter" / "Better — recommended for your Mac" / "Best — highest quality, needs more memory"), not model names. A "Skip — I'll set this up later" option is available for users who plan to use cloud summarization or decide later. Recommended tier is pre-selected and highlighted. Download starts on confirmation with progress indicator.
   - Model names and sizes are shown as secondary detail for advanced users, not as primary labels.
6. **Ready state** — Confirm setup complete. Direct user to start first recording.

### Fallback Behavior

- If a permission is denied: show specific instructions to enable it in System Settings, with a deep link or navigation path
- If a permission is revoked after initial grant: detect on next app launch or recording attempt, show re-permission flow
- If user skips onboarding: block recording with clear explanation of what's missing and how to fix it

---

## User Flows

### First Launch Flow

```
Install → Open → Onboarding (permissions + two-channel explanation)
  → Configure (model selection, mic device)
  → Ready state
```

User installs Voxema, opens the app, completes the onboarding flow (grants Screen Recording and Microphone permissions, learns about two-channel capture), configures preferences, and reaches the ready state for their first recording.

### Typical Recording Flow

```
Click Record → Visual indicator active → Meeting happens
  → Click Stop → Processing indicator
  → Pipeline runs (capture → transcribe → diarize → summarize)
  → Summary appears → User reviews/edits
  → Optional export (Markdown / JSON)
```

User clicks Record, sees a persistent visual indicator confirming capture is active. After the meeting, clicks Stop. A processing indicator shows pipeline progress. When complete, the structured summary appears with key decisions, action items, and open questions. User can review, edit, and optionally export.

### Meeting History Flow

```
Open library → Search/browse meetings → Select meeting
  → View transcript with speaker labels
  → View summary / decisions / action items
  → Export to Markdown or JSON
  → Optionally delete meeting
```

User opens the meeting library, searches or browses past meetings. Selects a meeting to view the full transcript with speaker attribution and the generated summary. Can export in Markdown (for wikis, notes apps) or JSON (for AI processing, third-party tools). Can permanently delete any meeting.

**Export requirement:** The system must store data in a format suitable for both quick human export (Markdown for wikis and notes apps) and machine-readable export (JSON with full entity relationships) to enable downstream AI processing by third-party tools or future Voxema analysis features.

---

## Offline-First UX

Principle #3 (Works offline) and Principle #6 (Graceful degradation) require specific behavior across all connectivity scenarios.

### Always Offline (no connectivity dependency)
- Transcription (Whisper.cpp) — always local, always available
- Speaker diarization (ECAPA-TDNN) — always local, always available
- Meeting library, search, and export — always local, always available
- Local summarization (LocalProvider / llama.cpp) — always available

### Cloud Degradation Behavior

| Scenario | Behavior |
|---|---|
| CloudProvider (direct API) selected, no internet | Queue the summarization request. Notify user. Offer immediate fallback to LocalProvider. Do NOT silently fail. |
| OnPremProvider endpoint unreachable | Retry with exponential backoff (max 3 retries). Then offer fallback to LocalProvider or queue for later retry. |
| Voxema backend unreachable (Pro, proxy mode) | Notify user that managed cloud summarization is temporarily unavailable. Offer immediate fallback to LocalProvider. Queue request for retry when connectivity is restored. |

### Design Principles
- Network state changes during pipeline execution: only the Summarize stage is affected; all other stages proceed normally
- Every core workflow must complete with a useful result even without internet
- Cloud features enhance quality but are never blocking

---

## Backend Services

> **Post-MVP, architecturally significant.** Backend services are required only for Pro and Enterprise tiers. The MVP operates entirely without a backend. This section is included early because backend design decisions affect the CloudProvider model, monetization architecture, and privacy contracts.

### a) Authentication & Identity

- Apple Sign In and email-based authentication
- Session management for Pro/Enterprise users
- Enterprise: domain-based authentication (SSO), centralized access management
- All auth is for subscription/billing purposes only — no meeting content flows through auth

### b) Subscription & Billing

- Subscription validation via Lemon Squeezy license key API (JWT-based offline validation) for direct distribution; App Store Server API if/when Mac App Store distribution is added
- Feature gating based on subscription tier (Free vs Pro)
- Usage tracking: minutes of audio processed via cloud, LLM tokens consumed
- Usage limits and billing enforcement
- Enterprise: volume licensing management

### c) LLM Proxy

Pro users do **not** manage their own API keys. The Voxema backend proxies LLM requests using Voxema's own API keys, replacing the direct-API CloudProvider mode with a fully managed experience.

See [Monetization Model](#monetization-model) for payment infrastructure (Lemon Squeezy) and license validation approach.

**Flow:**
1. App sends text transcript to Voxema backend (encrypted in transit, TLS)
2. Backend applies optimized server-side prompts
3. Backend calls cloud LLM (Anthropic/OpenAI)
4. Backend returns structured summary to app

**Benefits:**
- Server-side prompt management — optimized prompts for meeting summarization maintained and iterated on the backend, deployed independently of app releases
- Per-user usage tracking and cost control
- No API key management burden on users
- Prompt iteration without app updates

### d) Admin Dashboard

For product owner / operator use in the Pro launch phase (post-MVP, when the backend ships), not during the Free-only F&F beta:

- User list with subscription status
- Usage statistics per user (minutes, tokens, cost)
- Grant / revoke access capability
- API cost monitoring and spending alerts
- Early stage: simple dashboard (not a full admin panel)
- Can evolve into a more comprehensive admin system post-beta

### Privacy Constraints for Backend

| Constraint | Detail |
|---|---|
| Content-stateless | Backend stores no transcripts, summaries, audio, or PII from meetings |
| Transit only | Transcript text passes through the LLM proxy in transit only (for the cloud LLM call), never persisted on server |
| Stored data | User identity, subscription status, usage counters, billing records only |
| Encryption in transit | All transcript transmission encrypted via TLS |
| Server logs | Must not contain transcript text or any meeting content |

### Enterprise Additions (post-MVP)

- Domain-based authentication (SSO integration)
- Centralized model management: IT admin can block cloud models to prevent data leaks, preset OnPremProvider endpoints
- No backend dependency for Enterprise if fully self-hosted

---

## Versioning & Update Strategy

For direct download (DMG) distribution without the App Store, the app needs a built-in update mechanism. **Sparkle** is the standard solution for macOS DMG-distributed apps — open-source, widely adopted, and supports code signing verification.

**Options:** automatic updates with explicit user consent, or a manual check-for-updates flow.

This choice is **architecturally significant** — it must be reflected in [Technical Constraints](#technical-constraints) and the build pipeline (signing, update feed hosting, release cadence).

**MVP:** At minimum, a check-for-updates mechanism that notifies the user when a newer version is available. Auto-update via Sparkle is the **preferred** approach once Discovery has settled integration, code signing, and update hosting.

---

## Accessibility

**VoiceOver compatibility is not in MVP scope** — a conscious trade-off. The MVP prioritizes the core pipeline and privacy architecture; full accessibility is deferred but not forgotten.

**During MVP:** Apply basic accessibility practices where cost is low: semantic SwiftUI labels, standard system controls, and keyboard navigation. SwiftUI provides reasonable default accessibility for standard components, so baseline compliance during MVP is inexpensive.

**Post-MVP:** A full VoiceOver audit and remediation is planned. This is relevant for a future Mac App Store submission, where Apple reviews accessibility.

---

## MVP Scope

The MVP delivers the core loop: **Record → Transcribe → Identify Speakers → Summarize → View & Export**.

### In scope (MVP)
- macOS 13+ (Ventura), Apple Silicon only
- System audio + microphone capture as two channels
- Local transcription via Whisper.cpp (tiny/base/small models)
- Speaker diarization with voice profile database
- Summary generation via LocalProvider or CloudProvider
- Meeting library (list, search, view)
- Markdown and JSON export
- Settings: model selection, provider selection, audio device selection
- SwiftUI native interface
- Direct download distribution (DMG)
- Update notification or auto-update mechanism (Sparkle)
- Onboarding flow with permission setup (see [Onboarding Flow](#onboarding-flow))

### Not in scope (MVP)
- Windows or Linux
- iOS / iPadOS
- Real-time transcription display during recording
- Calendar integration
- Task manager integration (Notion, Linear, Jira)
- Multi-language transcription in a single meeting
- Video recording
- Mac App Store distribution
- Collaborative editing of summaries
- Cloud sync between devices
- Enterprise tier features (OnPremProvider, volume licensing)
- Monetization / paywall implementation
- Backend services (authentication, billing, LLM proxy)
- Admin dashboard
- Server-side prompt management
- Full accessibility / VoiceOver audit

---

## Technical Constraints

| Constraint | Detail |
|---|---|
| Language | Swift (with C++ bridging for Whisper.cpp and llama.cpp via Swift C interop) |
| UI Framework | SwiftUI — no third-party UI frameworks, no Electron, no web views |
| Minimum macOS | 13.0 (Ventura) — required for ScreenCaptureKit audio-only capture API |
| Hardware | Apple Silicon only — ML models optimized for Neural Engine / GPU via Metal |
| Build toolchain | Swift 5.9+ / Xcode 15+ |
| Database | SQLite via GRDB |
| Dependencies | All dependencies must be auditable (prefer source-available) |
| Distribution | Direct download (DMG) for MVP |
| Update mechanism | Sparkle framework (preferred) for auto-update in DMG distribution. Requires Discovery for integration approach, code signing, and update hosting. |
| Model packaging | Hybrid: bundle Whisper tiny (~75MB) + ECAPA-TDNN (~25MB) in DMG for immediate use. Whisper base/small and LLM downloaded on demand. LLM selected during onboarding from a curated list with hardware-based recommendation (see DEC-2). DMG ~150–180MB. Models stored in ~/Library/Application Support/Voxema/Models/. Curated model list and SHA-256 checksums in `models-manifest.json`. See DEC-2. |
| Backend technology stack | TypeScript (Hono) + PostgreSQL (Drizzle ORM) on Railway. Auth: Apple Sign In + Email OTP, JWT tokens. Billing: Lemon Squeezy webhooks. LLM proxy: Claude Haiku 4.5 primary, GPT-4o-mini fallback, SSE streaming. Hosting temporary (Railway → Fly.io at scale). See DEC-3. |

---

## Privacy & Security Requirements

These are hard constraints, not preferences:

| Requirement | Detail |
|---|---|
| Audio stays on device | Audio data never transmitted anywhere, under any circumstances |
| Transcript cloud opt-in | Text transcript sent to cloud LLM only with per-session explicit consent |
| Voice embeddings encrypted | Biometric data stored in encrypted local storage only |
| No background recording | Recording only while user explicitly activates it |
| Full deletion | All meeting data (transcripts, summaries, voice profiles) deletable on demand |
| No telemetry with content | Logs, analytics, crash reports never contain audio, transcript text, or PII |
| Temporary audio cleanup | Raw audio files encrypted at rest, deleted after transcription completes successfully. On transcription failure: retry policy applies (max 3 retries); audio retained until retry exhaustion or manual cleanup. Audio files never persist beyond the processing session. |
| Backend content-stateless | No transcripts, summaries, audio, or meeting content persisted on Voxema's backend servers. Transcript text passes through the LLM proxy in transit only (encrypted via TLS), never stored. Server logs must not contain meeting content. |

---

## Quality Requirements

| Metric | Target |
|---|---|
| Transcription accuracy (English) | WER ≤ 15% (Whisper small model, clear audio) |
| Transcription accuracy (Russian) | WER ≤ 25% (Whisper small model, clear audio) |
| Transcription accuracy (other languages) | Targets TBD after testing |
| Speaker identification accuracy | ≥ 85% for known speakers (after 3+ meetings) |
| Summary relevance | ≥ 80% of key decisions captured (user-judged) |
| Recording startup latency | ≤ 2 seconds from click to active capture |
| End-to-end processing time | ≤ 2× meeting duration on M1 (base Whisper model) |
| Memory usage (8GB device) | ≤ 4 GB peak during any single pipeline stage. On 8GB devices this implies sequential stage execution with model unloading between stages. |

---

## Success Metrics

| Metric | Definition |
|---|---|
| Activation | User completes first meeting recording and views summary |
| Retention | User records ≥ 3 meetings in first 2 weeks |
| Quality satisfaction | User makes ≤ 2 edits per summary on average |
| Export usage | ≥ 30% of meetings exported within 24 hours |

---

## Risks

| Risk | Mitigation |
|---|---|
| ScreenCaptureKit permission UX is confusing | Dedicated [Onboarding Flow](#onboarding-flow) with step-by-step permission guide, visual instructions, verification checks, and fallback instructions for denied/revoked permissions |
| Whisper accuracy degrades on noisy audio | Offer model size selection; show confidence indicators |
| 8GB RAM insufficient for large models | Lazy loading, model unloading between stages, recommend smaller models. Sequential stage execution enforced on 8GB devices. |
| macOS API changes break capture | Abstract capture behind protocol; monitor macOS betas |
| User expects real-time transcription | Clearly communicate that transcription happens post-recording in MVP |
| Model download required after install | Bundled Whisper tiny enables immediate use; larger models (base/small/LLM) require on-demand download (~0.5–2GB each). Mitigation: progress UI, background download, Whisper tiny works immediately. |
| Cloud provider unavailability blocks workflow | Offline-first design ensures local fallback always available (see [Offline-First UX](#offline-first-ux)) |
| Backend dependency for Pro cloud features | If Voxema backend is down, Pro cloud summarization is unavailable. Mitigation: offline-first design ensures LocalProvider fallback is always available; cloud features are never blocking. |
| Users on outdated versions miss critical fixes | Built-in update mechanism (Sparkle). Version check on app launch. |
