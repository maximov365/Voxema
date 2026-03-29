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

Three tiers, structured around privacy boundaries:

| Tier | Processing Model | Key Features |
|---|---|---|
| **Free** | Fully local on user's device | Local Whisper models, local LLM (llama.cpp), all data on-device. No cloud features. Complete meeting pipeline without subscription. |
| **Pro** | Local + optional cloud LLM | Adds ability to send transcriptions to cloud LLM for higher-quality summaries. Includes explicit per-session consent, text-only transmission (never audio), and encrypted transport. All Free features included. Subscription model. |
| **Enterprise** | Corporate perimeter deployment | Installable within corporate infrastructure. Processing on corporate local servers with local models. Custom endpoint support (OnPremProvider). Volume licensing. |

**Privacy guardrails per tier:**
- Free: Zero network calls. All processing on-device.
- Pro: Audio never leaves device. Only text transcript sent to cloud, only with per-session explicit consent. No persistent cloud storage of transcripts.
- Enterprise: All processing within corporate network. OnPremProvider endpoints configured by IT. No data leaves corporate perimeter.

> **Note:** This tier structure directly affects architecture decisions (feature gating, paywall boundaries, licensing). Detailed pricing, feature gating granularity, and go-to-market strategy require a dedicated Discovery.

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
- Three provider options:
  - **LocalProvider** — llama.cpp, fully offline
  - **CloudProvider** — Anthropic/OpenAI API (text only, user consent required)
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
5. **Configuration** — Model selection (Whisper model size), microphone device selection. Sensible defaults pre-selected.
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
| CloudProvider selected, no internet | Queue the summarization request. Notify user. Offer immediate fallback to LocalProvider. Do NOT silently fail. |
| OnPremProvider endpoint unreachable | Retry with exponential backoff (max 3 retries). Then offer fallback to LocalProvider or queue for later retry. |
| Cloud API key invalid or expired | Detect on settings change (not on every recording start). Notify user with clear instructions to update. |

### Design Principles
- Cloud API key validation: check on settings change, not on every recording start
- Network state changes during pipeline execution: only the Summarize stage is affected; all other stages proceed normally
- Every core workflow must complete with a useful result even without internet
- Cloud features enhance quality but are never blocking

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
| Model packaging | Requires Discovery — how models are bundled with app vs. downloaded on first launch, size implications for DMG distribution |

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
| Model packaging increases DMG size | Requires Discovery — evaluate bundling vs. first-launch download strategy |
| Cloud provider unavailability blocks workflow | Offline-first design ensures local fallback always available (see [Offline-First UX](#offline-first-ux)) |
