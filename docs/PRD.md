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
3. **Works offline** — Core pipeline (capture → transcribe → diarize → summarize) functions without internet via local models.
4. **Progressive quality** — Local models for privacy; cloud models available for users who opt in to better summaries.
5. **Minimal friction** — One click to start recording, one click to stop. Summary appears automatically.

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
- All data persisted locally in SQLite
- Meeting library with search
- Export to Markdown and JSON
- Full data deletion on user request (irreversible)

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
- Markdown export
- Settings: model selection, provider selection, audio device selection
- SwiftUI native interface
- Direct download distribution (DMG)

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
| Temporary audio cleanup | Raw audio files encrypted at rest, deleted after transcription completes |

---

## Quality Requirements

| Metric | Target |
|---|---|
| Transcription accuracy (English) | WER ≤ 15% (Whisper small model, clear audio) |
| Speaker identification accuracy | ≥ 85% for known speakers (after 3+ meetings) |
| Summary relevance | ≥ 80% of key decisions captured (user-judged) |
| Recording startup latency | ≤ 2 seconds from click to active capture |
| End-to-end processing time | ≤ 2× meeting duration on M1 (base Whisper model) |
| Memory usage (8GB device) | ≤ 4 GB peak during any single pipeline stage |

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
| ScreenCaptureKit permission UX is confusing | Clear onboarding flow with step-by-step permission guide |
| Whisper accuracy degrades on noisy audio | Offer model size selection; show confidence indicators |
| 8GB RAM insufficient for large models | Lazy loading, model unloading between stages, recommend smaller models |
| macOS API changes break capture | Abstract capture behind protocol; monitor macOS betas |
| User expects real-time transcription | Clearly communicate that transcription happens post-recording in MVP |
