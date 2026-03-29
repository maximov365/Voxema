# Pipeline Contracts — Voxema

This document defines the input/output contracts for each pipeline stage. Contracts are stable interfaces — changes require a pipeline version bump.

**Pipeline version:** 0.1.0

```
Capture → Transcribe → Diarize → Summarize → Export
```

---

## Data Representations

### AudioStream

```
AudioStream {
  stream_id: UUID
  channel: "local" | "remote"
  format: PCM 16kHz mono
  file_path: String           # encrypted temp file
  duration_seconds: Float
  device_name: String
  recorded_at: Date
}
```

### TranscribedSegment

```
TranscribedSegment {
  segment_id: UUID
  channel: "local" | "remote"
  start_time: Float           # seconds from recording start
  end_time: Float
  text: String
  language: String            # detected language code
  confidence: Float           # 0.0–1.0, Whisper segment confidence
}
```

### DiarizedSegment

```
DiarizedSegment {
  segment_id: UUID            # same as TranscribedSegment.segment_id
  start_time: Float
  end_time: Float
  text: String
  speaker: SpeakerIdentity
  channel: "local" | "remote"
}
```

### SpeakerIdentity

```
SpeakerIdentity {
  speaker_id: UUID
  label: String               # user-assigned name or temporary label
  is_user: Bool               # true for local channel
  confidence: Float           # cosine similarity score (0.0–1.0)
  is_known: Bool              # matched against voice profile DB
}
```

### MeetingSummary

```
MeetingSummary {
  meeting_id: UUID
  summary_text: String
  key_decisions: [String]
  action_items: [ActionItem]
  open_questions: [String]
  provider_used: "local" | "cloud" | "on_prem"
  model_name: String
  generated_at: Date
}
```

### ActionItem

```
ActionItem {
  description: String
  assignee: String?           # speaker label if identifiable
  deadline: String?           # extracted from conversation if mentioned
}
```

### Meeting

```
Meeting {
  meeting_id: UUID
  title: String               # auto-generated or user-set
  recorded_at: Date
  duration_seconds: Float
  transcript: [DiarizedSegment]
  summary: MeetingSummary?
  speakers: [SpeakerIdentity]
  audio_deleted: Bool         # true after temp audio cleanup
  metadata: MeetingMetadata
}
```

### MeetingMetadata

```
MeetingMetadata {
  whisper_model: String
  summary_provider: String
  language_detected: String
  segment_count: Int
  word_count: Int
}
```

---

## Stage Contracts

### Stage 1: Capture

**Input:**
- User action: start recording
- Audio device configuration (microphone selection)

**Output:**
- `[AudioStream]` — exactly two streams: one `local`, one `remote`

**Responsibilities:**
- Initialize ScreenCaptureKit for system audio capture
- Initialize AVAudioEngine for microphone capture
- Maintain two independent streams at 16kHz mono PCM
- Encrypt temporary audio files at rest
- Handle device disconnection gracefully (pause/resume or error)
- Provide recording duration and status

**Not responsible for:**
- Transcription or any text processing
- Speaker identification
- Audio format conversion beyond the target PCM format
- Persisting audio beyond temporary files

**Error conditions:**
- ScreenCaptureKit permission denied → clear error, link to System Settings
- Microphone permission denied → clear error, link to System Settings
- Audio device disconnected → stop recording, preserve captured data
- Disk space insufficient → stop recording, preserve captured data

**LLM usage:** None. This stage is deterministic.

---

### Stage 2: Transcribe

**Input:**
- `[AudioStream]` — two PCM audio streams from Capture

**Output:**
- `[TranscribedSegment]` — per channel, timestamped

**Responsibilities:**
- Load Whisper model (configurable size)
- Transcribe each channel independently
- Produce timestamped segments with text and confidence
- Detect language per channel
- Unload Whisper model after completion

**Not responsible for:**
- Speaker identification (handled by Diarize)
- Summarization
- Audio capture
- Merging channels

**Error conditions:**
- Model file missing or corrupt → error with instructions to re-download
- Audio file corrupt or empty → skip channel, report in metadata
- Out of memory → suggest smaller model size

**LLM usage:** None. Whisper is a speech recognition model, not an LLM.

---

### Stage 3: Diarize

**Input:**
- `[TranscribedSegment]` — from Transcribe (both channels)

**Output:**
- `[DiarizedSegment]` — each segment attributed to a speaker

**Responsibilities:**
- Local channel: attribute all segments to the user (no embedding needed)
- Remote channel: extract voice embedding per segment via ECAPA-TDNN
- Match embeddings against VoiceProfileStore (cosine similarity ≥ 0.75)
- Assign known speaker labels or temporary labels
- Cluster unknown speakers (distinguish Speaker A from Speaker B)
- Optionally update voice profile database with new embeddings
- Unload embedding model after completion

**Not responsible for:**
- Transcription (text comes from Transcribe stage)
- Summarization
- Audio capture
- Modifying transcript text

**Error conditions:**
- Embedding model missing → error with instructions to download
- Voice profile DB corrupt → initialize fresh DB, warn user
- All segments below confidence threshold → assign temporary labels, flag for user review

**LLM usage:** None. Speaker embedding is a deterministic ML model.

---

### Stage 4: Summarize

**Input:**
- `[DiarizedSegment]` — full speaker-attributed transcript

**Output:**
- `MeetingSummary` — structured summary with decisions, actions, questions

**Responsibilities:**
- Assemble full transcript from diarized segments (chronological order)
- Build dynamic prompt from template + project context + few-shot examples
- Invoke selected SummaryProvider
- Parse structured output into MeetingSummary fields
- Handle provider errors with bounded retries

**Not responsible for:**
- Transcription
- Speaker identification
- Audio capture
- Persisting results (handled by Export)

**Error conditions:**
- LocalProvider: model too large for available RAM → suggest smaller model or cloud
- CloudProvider: API error → retry with exponential backoff (max 3 retries)
- CloudProvider: user has not consented → block, prompt for consent
- OnPremProvider: endpoint unreachable → retry, then fallback suggestion
- Malformed LLM output → retry with stricter prompt, then return partial summary

**LLM usage:** Yes — this is the only stage that invokes an LLM.

---

### Stage 5: Export

**Input:**
- `[DiarizedSegment]` — full transcript
- `MeetingSummary` — generated summary
- `MeetingMetadata` — processing metadata

**Output:**
- `Meeting` — persisted in SQLite
- Optional: `.md` or `.json` export file

**Responsibilities:**
- Persist meeting record to SQLite database
- Index transcript for full-text search
- Generate Markdown export on demand
- Generate JSON export on demand
- Delete temporary audio files after successful persistence
- Support complete meeting deletion (hard delete)

**Not responsible for:**
- Transcription
- Summarization
- Speaker identification
- Audio capture
- Cloud sync (not in MVP)

**Error conditions:**
- Database write failure → retry, report error, do not delete temp audio
- Export file write failure → report error (meeting data safe in DB)
- Disk space insufficient → report error before attempting write

**LLM usage:** None. This stage is deterministic.

---

## Cross-Stage Rules

1. Each stage receives immutable input and produces new output — no in-place mutation
2. Stages do not call each other directly — orchestrated by PipelineCoordinator
3. Errors raised at stage boundaries with structured error types
4. Error messages never contain transcript text, audio content, or PII
5. Models loaded only during their stage, unloaded after (8GB RAM discipline)
6. Pipeline version bumped when contracts, stage order, or data representations change
