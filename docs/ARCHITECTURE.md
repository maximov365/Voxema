# Architecture — Voxema

## Overview

Voxema is a native macOS application (SwiftUI, Apple Silicon) that processes meeting audio through a five-stage pipeline entirely on-device, with an optional cloud LLM for the summarization stage only.

```
┌─────────────────────────────────────────────────────────┐
│                     Voxema.app                          │
│                                                         │
│  ┌─────────┐  ┌────────────┐  ┌─────────┐  ┌────────┐ │
│  │ Capture  │→ │ Transcribe │→ │ Diarize │→ │Summarize│ │
│  └─────────┘  └────────────┘  └─────────┘  └────────┘ │
│       │                                         │       │
│       ▼                                         ▼       │
│  ┌──────────────────────────────────────────────────┐   │
│  │                   Export / Storage                │   │
│  │                    (SQLite)                       │   │
│  └──────────────────────────────────────────────────┘   │
│                                                         │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐  │
│  │  VoiceProfile │  │  ModelManager │  │   Settings   │  │
│  │   Database    │  │              │  │              │  │
│  └──────────────┘  └──────────────┘  └──────────────┘  │
└─────────────────────────────────────────────────────────┘
```

---

## Modules

### 1. Capture Module

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

### 2. Transcribe Module

**Responsibility:** Convert audio to timestamped text segments.

| Component | Technology | Purpose |
|---|---|---|
| WhisperEngine | Whisper.cpp (Swift bindings) | Speech-to-text inference |
| TranscriptionCoordinator | Swift | Orchestrate per-channel transcription |

- Each channel transcribed independently
- Model loaded on demand, unloaded after completion
- Configurable model size: tiny, base, small, medium
- Output: `[TranscribedSegment]` per channel — each with start/end timestamps and text

### 3. Diarize Module

**Responsibility:** Attribute each segment to a speaker.

| Component | Technology | Purpose |
|---|---|---|
| SpeakerEmbedding | ECAPA-TDNN (ONNX Runtime / CoreML) | Extract voice embeddings |
| VoiceProfileStore | SQLite (encrypted) | Persist known speaker profiles |
| SpeakerMatcher | Cosine similarity | Match embeddings to known profiles |

- Local channel → always attributed to user (no embedding needed)
- Remote channel → extract embedding per segment, match against known profiles
- Match threshold: cosine similarity ≥ 0.75
- Unknown speakers assigned temporary labels (`Speaker A`, `Speaker B`, ...)
- User can rename/merge/delete profiles via UI

### 4. Summarize Module

**Responsibility:** Generate structured meeting summary from diarized transcript.

| Component | Technology | Purpose |
|---|---|---|
| PromptBuilder | Swift | Assemble dynamic prompt from template + context |
| SummaryProvider (protocol) | — | Abstract LLM interface |
| LocalProvider | llama.cpp | On-device LLM inference |
| CloudProvider | URLSession | Anthropic / OpenAI API client |
| OnPremProvider | URLSession | Custom endpoint client |

- SummaryProvider is a Swift protocol with three concrete implementations
- Provider selected in Settings, switching does not affect the pipeline
- CloudProvider sends text transcript only (never audio), requires user consent
- Output structure: `MeetingSummary` — summary text, key decisions, action items, open questions

### 5. Export Module

**Responsibility:** Persist meeting data and produce export artifacts.

| Component | Technology | Purpose |
|---|---|---|
| MeetingStore | SQLite (GRDB) | Persist transcripts, summaries, metadata |
| MarkdownExporter | Swift | Generate .md files |
| JSONExporter | Swift | Generate .json files |

- All meeting data in a single encrypted SQLite database
- Full-text search on transcripts and summaries
- Deletion is complete and irreversible (hard delete, not soft)

---

## Cross-Cutting Concerns

### ModelManager

Manages lifecycle of ML models (Whisper, ECAPA-TDNN, llama.cpp).

- Lazy loading: models loaded only when their pipeline stage activates
- Eager unloading: models released from memory after stage completes
- On 8GB devices: enforces single-model-at-a-time policy
- Downloads and caches model files in `~/Library/Application Support/Voxema/Models/`

### Settings

- Audio device selection (microphone)
- Whisper model size
- Summary provider selection (local / cloud / on-prem)
- Cloud API key management (stored in Keychain)
- Voice profile management
- Data management (export all, delete all)

### Security & Encryption

- Voice profile database encrypted via CryptoKit (AES-256-GCM)
- Encryption key stored in Apple Keychain
- Temporary audio files encrypted at rest
- API keys stored in Keychain, never in UserDefaults or files
- No content in logs — structured logging with metadata only

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
  ┌─────────────────┐
  │   Summarize      │
  │  LLM provider    │
  └────────┬────────┘
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

## Key Architectural Decisions

| Decision | Rationale |
|---|---|
| Two-channel capture (not mixed) | Enables reliable speaker attribution — local channel is always the user |
| Whisper.cpp (not Apple Speech) | Consistent quality, offline, supports multiple languages, open-source |
| ECAPA-TDNN for speaker ID | State-of-the-art speaker verification, small model footprint (~50MB) |
| SQLite for all storage | Single-file database, no server, encrypts easily, excellent Swift support |
| SummaryProvider as protocol | Clean abstraction enables local/cloud/on-prem without pipeline changes |
| Lazy model loading | Critical for 8GB devices — cannot hold Whisper + LLM simultaneously |
| No real-time transcription in MVP | Simplifies architecture, avoids streaming complexity, focuses on quality |

---

## File Structure (planned)

```
Voxema/
├── App/                      # SwiftUI app entry, scenes, navigation
├── Features/
│   ├── Recording/            # Capture UI and state management
│   ├── MeetingLibrary/       # List, search, detail views
│   ├── MeetingDetail/        # Transcript + summary view
│   ├── Settings/             # Preferences, model management
│   └── Onboarding/           # Permission setup flow
├── Pipeline/
│   ├── Capture/              # SystemAudioCapture, MicrophoneCapture
│   ├── Transcribe/           # WhisperEngine, TranscriptionCoordinator
│   ├── Diarize/              # SpeakerEmbedding, VoiceProfileStore, SpeakerMatcher
│   ├── Summarize/            # PromptBuilder, SummaryProvider protocol + implementations
│   └── Export/               # MeetingStore, MarkdownExporter, JSONExporter
├── Core/
│   ├── Models/               # Data models (Meeting, Segment, Speaker, Summary)
│   ├── Storage/              # Database layer (GRDB wrapper)
│   ├── Security/             # Encryption, Keychain helpers
│   ├── ModelManager/         # ML model lifecycle management
│   └── Logging/              # Structured logging (no content in logs)
├── Resources/
│   ├── Prompts/              # Summary prompt templates
│   └── Assets/               # App icons, images
└── Tests/
    ├── PipelineTests/
    ├── CoreTests/
    └── FeatureTests/
```

---

## Constraints

- macOS 13+ (Ventura) — minimum for ScreenCaptureKit audio-only capture
- Apple Silicon only — ML models optimized for Neural Engine / GPU
- Swift 5.9+ / Xcode 15+
- No third-party UI frameworks — SwiftUI only
- No Electron, no web views
- All dependencies must be auditable (prefer source-available)
