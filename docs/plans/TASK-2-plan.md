# TASK-2 Implementation Plan — Core Data Types and Structured Logging

**Agent:** Architect  
**Date:** 2026-03-29  
**Task:** TASK-2 — Core data types and structured logging  
**Status:** plan-ready  

---

## Context

TASK-1 (Xcode scaffold) is complete and the project builds. TASK-2 establishes the shared data vocabulary used by every pipeline stage. All types are pure Swift value types — no GRDB, no ScreenCaptureKit, no network code.

The existing placeholder files to replace:
- `Voxema/Core/Models/Models.swift` → replaced by 11 separate files (one per type)
- `Voxema/Core/Logging/Logger.swift` → replaced with structured logging wrapper
- `VoxemaTests/CoreTests/CoreTests.swift` → replaced by `DataTypesTests.swift`

---

## Constraints

- Field names must exactly match `docs/PIPELINE_CONTRACTS.md` (use snake_case in JSON via `CodingKeys`, camelCase in Swift)
- All types: `Codable`, `Equatable`, `Sendable`
- `AudioChannel` defined once, shared — not duplicated
- `Logger` must not expose any method accepting free-form `String` content
- No new SPM dependencies
- No GRDB, no framework imports — pure Swift + Foundation only
- New files must be added to `Voxema.xcodeproj` Xcode target

---

## Implementation Plan

### Step 1 — `AudioChannel` enum (small)

**File:** `Voxema/Core/Models/AudioChannel.swift` (new)

```swift
enum AudioChannel: String, Codable, Equatable, Sendable {
    case local
    case remote
}
```

Defines the `"local"` / `"remote"` discriminator used in `AudioStream`, `TranscribedSegment`, and `DiarizedSegment`. Must be defined first so subsequent types can reference it.

---

### Step 2 — Pipeline data structs (small each)

One file per type. All fields match `PIPELINE_CONTRACTS.md` exactly. Swift property names are camelCase; JSON keys map to snake_case via `CodingKeys`. All structs use `Foundation` types only (`UUID`, `Date`, `Float`, `String`, `Bool`).

**Files to create:**

| File | Type | PIPELINE_CONTRACTS.md fields |
|---|---|---|
| `AudioStream.swift` | struct | stream_id, channel, format, file_path, duration_seconds, device_name, recorded_at |
| `TranscribedSegment.swift` | struct | segment_id, channel, start_time, end_time, text, language, confidence |
| `DiarizedSegment.swift` | struct | segment_id, start_time, end_time, text, speaker (SpeakerIdentity), channel |
| `SpeakerIdentity.swift` | struct | speaker_id, label, is_user, confidence, is_known |
| `MeetingSummary.swift` | struct | meeting_id, summary_text, key_decisions, action_items, open_questions, provider_used, model_name, generated_at |
| `ActionItem.swift` | struct | description, assignee (optional), deadline (optional) |
| `Meeting.swift` | struct | meeting_id, title, recorded_at, duration_seconds, transcript, summary (optional), speakers, audio_deleted, metadata |
| `MeetingMetadata.swift` | struct | whisper_model, summary_provider, language_detected, segment_count, word_count |

**`MeetingSummary.provider_used`** — represented as a `ProviderType` enum (not a raw `String`) to prevent typos. Values: `"local"`, `"cloud"`, `"on_prem"`. This is a local design improvement; the JSON value matches the contract string.

**`format` in `AudioStream`** — represented as `String` (value: `"PCM 16kHz mono"`). A typed `AudioFormat` enum is deferred until Capture stage to avoid premature abstraction.

---

### Step 3 — `PipelineError` enum (small)

**File:** `Voxema/Core/Models/PipelineError.swift` (new)

```swift
enum PipelineError: Error, LocalizedError, Equatable, Sendable {
    case captureError(reason: String)
    case transcribeError(reason: String)
    case diarizeError(reason: String)
    case summarizeError(reason: String)
    case exportError(reason: String)
}
```

`errorDescription` returns `"[stage] error: \(reason)"` — structural context only, no content. `Equatable` conformance compares both case and reason.

---

### Step 4 — `Logger` struct (small)

**File:** `Voxema/Core/Logging/Logger.swift` (replace placeholder)

Design constraints:
- Wraps `os.Logger` (OSLog, no import of `os.log` string interpolation)
- Subsystem: `"com.voxema.app"` (constant)
- Category: per-instance, set via `Logger.make(category:)`
- Methods accept `StaticString` for format + one `@autoclosure () -> CVarArg` structural value (stage name, count, etc.) — intentionally prevents passing transcript text
- Actually, to fully prevent content leakage, methods should take `StaticString` only for message templates. Review: `os.Logger` already enforces privacy via `%{public}` vs `%{private}` annotations. For this implementation, use `os.Logger` with `.public` for stage/category info and no arbitrary string slots.

**API:**
```swift
struct Logger: Sendable {
    static func make(category: String) -> Logger
    func debug(_ message: StaticString, _ context: @autoclosure () -> some CustomStringConvertible = "")
    func info(_ message: StaticString, _ context: @autoclosure () -> some CustomStringConvertible = "")
    func warning(_ message: StaticString, _ context: @autoclosure () -> some CustomStringConvertible = "")
    func error(_ message: StaticString, _ context: @autoclosure () -> some CustomStringConvertible = "")
}
```

The `StaticString` requirement for `message` enforces that log templates are compile-time constants — no runtime string construction with transcript content. The `context` parameter provides structural metadata (stage name, count) not content.

---

### Step 5 — Remove `Models.swift` placeholder; wire new files in xcodeproj (small)

- Delete content of `Voxema/Core/Models/Models.swift` (keep file, empty it with a redirect comment, or delete and remove from xcodeproj — **delete** is preferred since all types are in separate files)
- Run `scripts/setup_xcodeproj.py` equivalent to add new files to the Xcode target (or do it via Python directly)
- Verify project still compiles: `xcodebuild BUILD SUCCEEDED`

**Note for Builder:** The existing `Models.swift` file is registered in `Voxema.xcodeproj`. Do not simply overwrite it with new content — delete its content, then add new files to the project. The Python xcodeproj scripts in `scripts/` are available for file wiring.

---

### Step 6 — Unit tests (medium)

**File:** `VoxemaTests/CoreTests/DataTypesTests.swift` (new; replaces placeholder `CoreTests.swift`)

Tests per acceptance criteria:

1. **Struct creation** — `AudioStream(...)` initializes without crash; all fields readable
2. **Codable round-trip** — for each of the 8 struct types: `JSONEncoder().encode(value)` → `JSONDecoder().decode(T.self, from: data)` → `XCTAssertEqual(decoded, original)`
3. **CodingKeys snake_case mapping** — encode `AudioStream` and verify JSON contains `"stream_id"` not `"streamId"` 
4. **`PipelineError` localizedDescription** — does not contain the word `"content"` (guards no-content policy)
5. **`PipelineError` equatability** — `.captureError(reason: "x") == .captureError(reason: "x")`, `.captureError(reason: "x") != .transcribeError(reason: "x")`
6. **`Logger.make(category:)`** — returns a `Logger` without crashing; calling `info("stage started")` does not crash
7. **`Logger` no-content API** — `Logger.info` does not compile with a runtime `String` argument (this is a compile-time guarantee; document it in a comment, no runtime test needed)

---

### Step 7 — Wire test file in xcodeproj and verify full build (small)

- Add `DataTypesTests.swift` to `VoxemaTests` target in xcodeproj
- Remove `CoreTests.swift` from target (or clear it)
- Run: `xcodebuild -scheme Voxema test` (or compile-only if test runner unavailable in sandbox)
- Confirm `BUILD SUCCEEDED`, zero errors

---

## Files to Create / Modify

| File | Action | Size |
|---|---|---|
| `Voxema/Core/Models/AudioChannel.swift` | new | tiny |
| `Voxema/Core/Models/AudioStream.swift` | new | small |
| `Voxema/Core/Models/TranscribedSegment.swift` | new | small |
| `Voxema/Core/Models/DiarizedSegment.swift` | new | small |
| `Voxema/Core/Models/SpeakerIdentity.swift` | new | small |
| `Voxema/Core/Models/MeetingSummary.swift` | new | small |
| `Voxema/Core/Models/ActionItem.swift` | new | small |
| `Voxema/Core/Models/Meeting.swift` | new | small |
| `Voxema/Core/Models/MeetingMetadata.swift` | new | small |
| `Voxema/Core/Models/PipelineError.swift` | new | small |
| `Voxema/Core/Logging/Logger.swift` | replace placeholder | small |
| `Voxema/Core/Models/Models.swift` | delete content / remove | tiny |
| `VoxemaTests/CoreTests/DataTypesTests.swift` | new | medium |
| `VoxemaTests/CoreTests/CoreTests.swift` | delete content / remove | tiny |
| `Voxema.xcodeproj/project.pbxproj` | add new files to targets | via script |

**Total new files: 11 source + 1 test = 12.** The 6–10 file threshold in `.cursor/rules.md` is exceeded; justification: PIPELINE_CONTRACTS.md mandates one type per file (single-responsibility, independently readable). This is the minimum file count for the defined scope.

---

## Acceptance Criteria (from TASK-2 spec)

- [ ] All struct fields exactly match `docs/PIPELINE_CONTRACTS.md` (field names, types, optionality)
- [ ] All types conform to `Codable`, `Equatable`, `Sendable`
- [ ] Codable round-trip tests pass for all 8 data types
- [ ] `PipelineError` cases cover all 5 pipeline stages
- [ ] `Logger.make(category:)` returns a configured logger without crashing
- [ ] No struct or enum imports GRDB, ScreenCaptureKit, AVFoundation, or external framework
- [ ] `ProviderType` enum values match PIPELINE_CONTRACTS.md strings (`"local"`, `"cloud"`, `"on_prem"`)
- [ ] All unit tests pass
- [ ] `xcodebuild BUILD SUCCEEDED`

---

## Non-Goals (from TASK-2 spec)

- No persistence (no GRDB)
- No network types
- No ML types
- No SwiftUI wrappers
- No voice profile or encryption types (TASK-3)

---

## Risks

- **`Sendable` + `Date`**: `Date` is `Sendable` in Swift 5.7+, so no issue. `UUID` is also `Sendable`. All fields are value types.
- **Logger API strictness**: `StaticString` for message parameter prevents dynamic string construction. Builder must verify the `os.Logger` call syntax is correct (Xcode will catch if wrong).
- **`description` field in `ActionItem`**: Swift's `String` property named `description` conflicts with `CustomStringConvertible.description`. Use property name `text` in Swift with `CodingKeys` mapping to `"description"` for JSON. **Decision: rename Swift property to `actionDescription` with CodingKey `"description"` to avoid protocol conflict.**

---

## Dependencies

- TASK-1 complete ✅ — project compiles
- No GRDB/Sparkle required for this task (explicitly in Non-Goals)

---

```json
{
  "handoff": {
    "from": "architect",
    "to": "iteration-manager",
    "task": "TASK-2",
    "status": "plan-ready",
    "artifact": "docs/plans/TASK-2-plan.md",
    "next_agent": "builder",
    "notes": "Plan is complete. Builder should follow steps 1–7 in order. Key risk: ActionItem.description name conflict resolved by using actionDescription + CodingKey. Logger uses StaticString to enforce no-content policy at compile time."
  }
}
```
