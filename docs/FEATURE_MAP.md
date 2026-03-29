# Feature Map — Voxema

This document defines capability blocks, their dependencies, and the canonical Capability Index used for `capability_id` references in tasks and features.

---

## Capability Index

| ID | Capability | Pipeline Stage | Description |
|---|---|---|---|
| `CAPTURE` | Audio Capture | capture | System audio + microphone recording |
| `TRANSCRIBE` | Speech-to-Text | transcribe | Whisper.cpp local transcription |
| `DIARIZE` | Speaker Identification | diarize | Voice embedding extraction and matching |
| `SUMMARIZE` | Meeting Summarization | summarize | LLM-powered summary generation |
| `EXPORT` | Storage & Export | export | SQLite persistence, Markdown/JSON export |
| `MODELS` | Model Management | cross-cutting | Download, cache, load/unload ML models |
| `SECURITY` | Security & Encryption | cross-cutting | Data encryption, Keychain, privacy enforcement |
| `UI-RECORDING` | Recording UI | cross-cutting | Recording controls, status indicator |
| `UI-LIBRARY` | Meeting Library | cross-cutting | Meeting list, search, navigation |
| `UI-DETAIL` | Meeting Detail View | cross-cutting | Transcript + summary display |
| `UI-SETTINGS` | Settings | cross-cutting | Preferences, model selection, provider config |
| `UI-ONBOARDING` | Onboarding | cross-cutting | Permission setup, first-run experience |
| `VOICE-PROFILES` | Voice Profile Management | diarize | Speaker database CRUD, merge, rename |
| `PROMPTS` | Prompt Management | summarize | Prompt templates, few-shot examples |

---

## Dependency Map

```
UI-ONBOARDING
     │
     ▼
  CAPTURE ──────────────┐
     │                  │
     ▼                  ▼
 TRANSCRIBE          MODELS
     │                  │
     ▼                  │
  DIARIZE ◄─────── VOICE-PROFILES
     │                  │
     ▼                  │
 SUMMARIZE ◄─────── PROMPTS
     │                  │
     ▼                  ▼
   EXPORT           SECURITY
     │
     ▼
  UI-LIBRARY → UI-DETAIL
     │
     ▼
 UI-SETTINGS
     │
     ▼
 UI-RECORDING
```

### Dependency Rules

- `TRANSCRIBE` depends on `CAPTURE` (needs audio streams)
- `DIARIZE` depends on `TRANSCRIBE` (needs text segments)
- `DIARIZE` depends on `VOICE-PROFILES` (needs speaker database)
- `SUMMARIZE` depends on `DIARIZE` (needs speaker-attributed transcript)
- `SUMMARIZE` depends on `PROMPTS` (needs prompt templates)
- `EXPORT` depends on `SUMMARIZE` (needs summary) and `DIARIZE` (needs transcript)
- `MODELS` is required by `TRANSCRIBE`, `DIARIZE`, and `SUMMARIZE` (model lifecycle)
- `SECURITY` is required by `CAPTURE` (audio encryption), `DIARIZE` (voice profile encryption), and `EXPORT` (database encryption)
- `UI-ONBOARDING` is the entry point — required before any recording
- `UI-RECORDING` depends on `CAPTURE`
- `UI-LIBRARY` depends on `EXPORT`
- `UI-DETAIL` depends on `UI-LIBRARY`
- `UI-SETTINGS` depends on `MODELS` and `SECURITY`

---

## MVP Capabilities

The following capabilities are required for MVP:

- `CAPTURE` — full
- `TRANSCRIBE` — full
- `DIARIZE` — basic (local = user, remote = embedding match or temp label)
- `SUMMARIZE` — LocalProvider + CloudProvider
- `EXPORT` — SQLite persistence + Markdown export
- `MODELS` — download, cache, load/unload
- `SECURITY` — encryption at rest, Keychain integration
- `UI-RECORDING` — start/stop, status indicator
- `UI-LIBRARY` — meeting list with search
- `UI-DETAIL` — transcript + summary view
- `UI-SETTINGS` — model and provider selection
- `UI-ONBOARDING` — permission setup flow
- `VOICE-PROFILES` — basic CRUD
- `PROMPTS` — default templates

### Post-MVP

- `EXPORT` — JSON export, calendar integration, task manager integration
- `SUMMARIZE` — OnPremProvider
- `DIARIZE` — advanced clustering, cross-meeting profile improvement
- `UI-DETAIL` — inline transcript editing, summary regeneration
