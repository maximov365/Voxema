# Phase 1 Task Proposals — Core Pipeline Foundation

**Produced by:** Product agent  
**Date:** 2026-03-29  
**Phase:** Phase 1 — Core Pipeline (foundation)  
**Capabilities:** `PIPELINE-COORD`, `CAPTURE`, `TRANSCRIBE`, `MODELS`, `SECURITY`, `NETWORKING`

These 7 tasks represent the complete implementation proposal for Phase 1 of the Voxema MVP. They are ordered by dependency — each task depends only on tasks that appear above it in this list. All tasks are marked `[MVP]`. No IDs are assigned here — Iteration Manager assigns IDs at commit time.

---

## Task 1 — Xcode Project Scaffold [MVP]

**Task ID:** _(assigned by Iteration Manager)_  
**Status:** planned  
**Owner:** unassigned  
**Created by:** Product agent  
**Priority:** high  
**Complexity:** medium  
**Current agent:** none  
**Related PRD section:** Technical Constraints, MVP Scope  
**Pipeline stage:** cross-cutting  

---

### Goal

Create the Xcode project with correct target configuration, Swift Package Manager dependencies, and the complete folder structure defined in `docs/ARCHITECTURE.md`. This task establishes the development environment and codebase skeleton for all subsequent Phase 1 tasks — no business logic is introduced.

---

### Scope

- Xcode project targeting macOS 13.0+ (Ventura), Apple Silicon, Swift 5.9+, Xcode 15+
- SwiftUI App target with hardened runtime entitlements (required for notarization and Sparkle)
- Privacy entitlements in `Info.plist`: `NSScreenCaptureUsageDescription` (Screen Recording), `NSMicrophoneUsageDescription` (Microphone)
- App Sandbox entitlements: `com.apple.security.device.audio-input`, `com.apple.security.screen-recording`
- SPM dependencies declared in `Package.swift` or via Xcode SPM integration:
  - GRDB (latest stable) — SQLite ORM
  - Sparkle 2 (latest stable) — auto-update
  - ONNX Runtime — note: not on SPM registry; add a `// TODO: manual integration` placeholder comment in `Core/ModelManager/` until Architect resolves integration approach
- Full folder structure per `docs/ARCHITECTURE.md` file structure section:
  - `Voxema/App/`
  - `Voxema/Features/Recording/`, `MeetingLibrary/`, `MeetingDetail/`, `Settings/`, `Onboarding/`
  - `Voxema/Pipeline/Coordinator/`, `Capture/`, `Transcribe/`, `Diarize/`, `Summarize/`, `Export/`
  - `Voxema/Core/Models/`, `Storage/`, `Security/`, `ModelManager/`, `Networking/`, `LicenseManager/`, `UpdateManager/`, `Logging/`
  - `Voxema/Resources/Prompts/`, `Models/`, `Assets/`
  - `VoxemaTests/PipelineTests/`, `CoreTests/`, `FeatureTests/`
- `Voxema/App/ContentView.swift` — placeholder SwiftUI view ("Voxema" text label, no logic)
- `Voxema/App/VoxemaApp.swift` — `@main` App entry point
- `README.md` — dev setup instructions: prerequisites (Xcode 15+, macOS 13+, Apple Silicon), clone and open steps, known manual integration steps for ONNX Runtime
- `.gitignore` for Xcode projects (standard Xcode gitignore template)
- App icon placeholder in `Assets.xcassets` (solid-color placeholder acceptable)

---

### Non-Goals

- No business logic of any kind
- No UI screens beyond a single ContentView placeholder
- No SPM package resolution of ONNX Runtime (noted as placeholder only)
- No `models-manifest.json` content (empty file or no file yet)
- No Swift files other than the App entry point and ContentView placeholder
- No tests (test targets created but no test methods)

---

### Inputs

- `docs/ARCHITECTURE.md` — file structure section (canonical folder layout)
- `docs/PRD.md` — Technical Constraints table (language, minimum macOS, build toolchain, distribution, dependencies)
- `docs/DECISIONS.md` — DEC-4 (Sparkle 2 via SPM), DEC-2 (ONNX Runtime for ECAPA-TDNN)

---

### Outputs

- A compilable Xcode project at the repository root (`Voxema.xcodeproj` or `Voxema.xcworkspace`)
- Complete folder structure matching `docs/ARCHITECTURE.md`
- SPM dependencies declared for GRDB and Sparkle 2
- `README.md` and `.gitignore` in the repository root

---

### Acceptance Criteria

- Project opens in Xcode 15+ and compiles without errors
- App runs on macOS 13+ and displays the ContentView placeholder
- All folders defined in `docs/ARCHITECTURE.md` file structure are present in the project navigator
- `Info.plist` contains `NSScreenCaptureUsageDescription` and `NSMicrophoneUsageDescription` keys with non-empty string values
- Hardened Runtime entitlement is set on the app target
- GRDB and Sparkle 2 are declared as SPM dependencies and resolve successfully
- ONNX Runtime is noted as a placeholder with a clear `// TODO:` comment explaining manual integration is required
- `README.md` documents prerequisites and setup steps
- `.gitignore` excludes standard Xcode build artifacts (`DerivedData/`, `.xcuserstate`, etc.)
- Test targets exist for `VoxemaTests/PipelineTests/`, `CoreTests/`, `FeatureTests/` (empty, but present)

---

### Constraints

- Must follow the folder structure exactly as defined in `docs/ARCHITECTURE.md` — no improvisation
- Hardened Runtime must be enabled from the start (required for notarization per DEC-4)
- No new dependencies beyond GRDB, Sparkle 2, and the ONNX Runtime placeholder
- Swift 5.9+ only — no Objective-C files introduced in this task

---

### Dependencies

- None (this is the foundational task)

---

### Risks

- ONNX Runtime SPM integration is unresolved — placeholder approach prevents blocking, but Architect must resolve this before the TASK-5 (ModelManager) implementation plan
- Sparkle 2 entitlement configuration (XPC service entitlements) may require additional entitlement keys beyond the base hardened runtime; Architect should verify during planning for the UPDATE capability task

---

### Implementation Notes

Architect should verify the exact entitlement keys required for ScreenCaptureKit audio-only capture on macOS 13+ — specifically whether `com.apple.security.screen-recording` is the correct entitlement key or whether a different key applies to audio-only capture via ScreenCaptureKit (as opposed to full-screen capture). This is a known macOS API nuance noted in `docs/LESSONS_LEARNED.md` (AudioSessionManager / CoreAudio note from FEAT-4).

---

### Architect Plan

- none (not yet planned)

---

### Files Likely Affected

- `Voxema.xcodeproj/` (new)
- `Voxema/App/VoxemaApp.swift` (new)
- `Voxema/App/ContentView.swift` (new)
- `Voxema/Resources/Assets.xcassets/` (new)
- `README.md` (new)
- `.gitignore` (new)
- All folder stubs per architecture

---

### Definition of Done

The task is considered complete when:
- Implementation satisfies all acceptance criteria
- Reviewer approves the changes
- `docs/TASKS.md` status is updated to `completed`

---

### Notes

This task intentionally has zero business logic. Its only purpose is to establish a clean, correctly-configured project skeleton so that all subsequent tasks have a verified foundation. Builder should resist the temptation to add any logic here.

---

---

## Task 2 — Core Data Types and Structured Logging [MVP]

**Task ID:** _(assigned by Iteration Manager)_  
**Status:** planned  
**Owner:** unassigned  
**Created by:** Product agent  
**Priority:** high  
**Complexity:** small  
**Current agent:** none  
**Related PRD section:** Technical Constraints, Privacy & Security Requirements, Core Capabilities — Data Model  
**Pipeline stage:** cross-cutting  

---

### Goal

Define all shared data types from `docs/PIPELINE_CONTRACTS.md` as Swift structs and enums, and implement a structured logging wrapper that enforces the no-content policy required by PRD Privacy & Security Requirements. After this task, all pipeline stages have a shared type vocabulary and a safe logging facility.

---

### Scope

- Swift structs matching exactly the `docs/PIPELINE_CONTRACTS.md` data representations:
  - `AudioStream` — in `Core/Models/AudioStream.swift`
  - `TranscribedSegment` — in `Core/Models/TranscribedSegment.swift`
  - `DiarizedSegment` — in `Core/Models/DiarizedSegment.swift`
  - `SpeakerIdentity` — in `Core/Models/SpeakerIdentity.swift`
  - `MeetingSummary` — in `Core/Models/MeetingSummary.swift`
  - `ActionItem` — in `Core/Models/ActionItem.swift`
  - `Meeting` — in `Core/Models/Meeting.swift`
  - `MeetingMetadata` — in `Core/Models/MeetingMetadata.swift`
- `PipelineError` enum — in `Core/Models/PipelineError.swift`:
  - Cases for each pipeline stage: `.captureError`, `.transcribeError`, `.diarizeError`, `.summarizeError`, `.exportError`
  - Each case carries a `reason: String` (structural context only — no content)
  - Conforms to `LocalizedError`
- `Logger` struct — in `Core/Logging/Logger.swift`:
  - Wraps `os.Logger` (OSLog framework)
  - Subsystem: `com.voxema.app`
  - Category per call site (e.g. `"capture"`, `"transcribe"`)
  - Methods: `debug(_:)`, `info(_:)`, `warning(_:)`, `error(_:)`
  - All methods accept only structural context strings — no free-form content parameters
  - Static factory: `Logger.make(category:)` returning a configured instance
- All structs and enums must conform to `Codable`, `Equatable`, and `Sendable`
- `AudioStream.channel`, `DiarizedSegment.channel`, `TranscribedSegment.channel` use a shared `AudioChannel` enum (`"local"` / `"remote"`)
- Unit tests in `VoxemaTests/CoreTests/`:
  - Data type creation and equality checks for each struct
  - Codable round-trip (encode → decode → equality) for each struct
  - `PipelineError` localizedDescription does not contain the word "content" (guards the no-content rule is considered)

---

### Non-Goals

- No persistence (no GRDB usage in this task)
- No network types
- No ML types
- No UI types
- No SwiftUI `@Observable` or `@Published` wrappers (those belong to feature modules)
- No voice profile or encryption types (those are in TASK-3)

---

### Inputs

- `docs/PIPELINE_CONTRACTS.md` — all data representation schemas (authoritative source for field names and types)
- `docs/PRD.md` — Privacy & Security Requirements ("No telemetry with content" rule)
- `docs/ARCHITECTURE.md` — Data Model entity table

---

### Outputs

- `Core/Models/` — 8 Swift source files (one per data type)
- `Core/Models/PipelineError.swift` — structured error enum
- `Core/Logging/Logger.swift` — structured logging wrapper
- Unit tests in `VoxemaTests/CoreTests/`

---

### Acceptance Criteria

- All struct fields exactly match the schemas in `docs/PIPELINE_CONTRACTS.md` (field names, types, optionality)
- All types conform to `Codable`, `Equatable`, and `Sendable`
- Codable round-trip tests pass for all 8 data types
- `PipelineError` cases cover all 5 pipeline stages
- `Logger.make(category:)` returns a configured logger without crashing
- No struct or enum imports GRDB, ScreenCaptureKit, AVFoundation, or any external framework (pure Swift value types only)
- All unit tests pass

---

### Constraints

- Field names must match `docs/PIPELINE_CONTRACTS.md` exactly — no aliasing or renaming
- `Logger` must not expose a method that accepts arbitrary `String` content (only structural metadata)
- No new SPM dependencies in this task
- `AudioChannel` enum must be defined once and shared — not duplicated per struct

---

### Dependencies

- Task 1 (Xcode Project Scaffold) — project must exist and compile

---

### Risks

- Swift `Sendable` conformance for structs containing `Date` or `UUID` is straightforward, but a future task adding mutable reference types must revisit these conformances
- `Logger` no-content policy is enforced by API design only; Builder must ensure no parameter of type `String` in logging methods could accidentally accept transcript text

---

### Implementation Notes

The `AudioChannel` enum (`local` / `remote`) is used in `AudioStream`, `TranscribedSegment`, and `DiarizedSegment`. Define it once in `Core/Models/AudioChannel.swift` and import it across the three structs. Do not duplicate the enum.

---

### Architect Plan

- none (not yet planned)

---

### Files Likely Affected

- `Voxema/Core/Models/AudioChannel.swift` (new)
- `Voxema/Core/Models/AudioStream.swift` (new)
- `Voxema/Core/Models/TranscribedSegment.swift` (new)
- `Voxema/Core/Models/DiarizedSegment.swift` (new)
- `Voxema/Core/Models/SpeakerIdentity.swift` (new)
- `Voxema/Core/Models/MeetingSummary.swift` (new)
- `Voxema/Core/Models/ActionItem.swift` (new)
- `Voxema/Core/Models/Meeting.swift` (new)
- `Voxema/Core/Models/MeetingMetadata.swift` (new)
- `Voxema/Core/Models/PipelineError.swift` (new)
- `Voxema/Core/Logging/Logger.swift` (new)
- `VoxemaTests/CoreTests/DataTypesTests.swift` (new)

---

### Definition of Done

The task is considered complete when:
- Implementation satisfies all acceptance criteria
- Reviewer approves the changes
- `docs/TASKS.md` status is updated to `completed`

---

### Notes

These types are the shared vocabulary for the entire pipeline. Builder must resist adding any logic beyond struct initialization and Codable conformance — no computed properties, no business logic, no persistence.

---

---

## Task 3 — Security: Encryption and Keychain [MVP]

**Task ID:** _(assigned by Iteration Manager)_  
**Status:** planned  
**Owner:** unassigned  
**Created by:** Product agent  
**Priority:** high  
**Complexity:** medium  
**Current agent:** none  
**Related PRD section:** Privacy & Security Requirements, Core Capabilities — Security & Encryption  
**Pipeline stage:** cross-cutting  

---

### Goal

Implement the Security module: CryptoKit-based AES-256-GCM encryption helpers for audio files and the database, and a Keychain wrapper for storing and retrieving sensitive values (API keys, encryption keys). After this task, the Capture stage can encrypt temporary audio files and the Settings module can safely store API keys.

---

### Scope

- `EncryptionManager` — in `Core/Security/EncryptionManager.swift`:
  - `encrypt(data: Data, key: SymmetricKey) throws -> Data` — AES-256-GCM, returns combined ciphertext + nonce + tag
  - `decrypt(data: Data, key: SymmetricKey) throws -> Data` — AES-256-GCM decryption
  - `generateKey() -> SymmetricKey` — generates a new AES-256 key
  - All operations use `CryptoKit.AES.GCM`
  - Error type: `EncryptionError` (cases: `.encryptionFailed`, `.decryptionFailed`, `.invalidData`)
- `KeychainManager` — in `Core/Security/KeychainManager.swift`:
  - `store(key: String, value: Data, service: String) throws` — stores value in Keychain
  - `retrieve(key: String, service: String) throws -> Data` — retrieves value from Keychain
  - `delete(key: String, service: String) throws` — deletes value from Keychain
  - Uses `SecItemAdd`, `SecItemCopyMatching`, `SecItemDelete` (Security framework)
  - `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` access policy (biometric / device only)
  - Error type: `KeychainError` (cases: `.notFound`, `.duplicateItem`, `.unexpectedStatus(OSStatus)`)
- Key derivation helper: `EncryptionManager.deriveKey(from password: String, salt: Data) -> SymmetricKey` using HKDF
- Unit tests in `VoxemaTests/CoreTests/SecurityTests.swift`:
  - Encrypt → decrypt round-trip: recovered plaintext equals original
  - Encrypt with wrong key: decryption throws `EncryptionError.decryptionFailed`
  - Keychain store → retrieve → delete: full lifecycle
  - Keychain retrieve on missing key: throws `KeychainError.notFound`
  - Keychain duplicate store: throws `KeychainError.duplicateItem` or overwrites (define explicit behavior)
  - Key generation produces 256-bit key

---

### Non-Goals

- No voice profile encryption (that is part of the DIARIZE / `VOICE-PROFILES` capability, Phase 2)
- No JWT handling (that is `LICENSE`, post-MVP)
- No file-level encryption helpers beyond `Data`-in / `Data`-out (file I/O is the caller's responsibility)
- No biometric authentication prompts (only `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`)

---

### Inputs

- `docs/ARCHITECTURE.md` — Security & Encryption table (specifies CryptoKit AES-256-GCM, Keychain for keys and API keys)
- `docs/PRD.md` — Privacy & Security Requirements (voice embeddings encrypted, API keys in Keychain, logs no content)

---

### Outputs

- `Core/Security/EncryptionManager.swift`
- `Core/Security/KeychainManager.swift`
- `VoxemaTests/CoreTests/SecurityTests.swift`

---

### Acceptance Criteria

- `EncryptionManager.encrypt` / `decrypt` round-trip passes with identical plaintext output
- Decryption with a wrong key throws — does not return garbage data
- `KeychainManager.store` / `retrieve` round-trip returns the exact stored bytes
- `KeychainManager.retrieve` on a non-existent key throws `KeychainError.notFound`
- `KeychainManager.delete` after store succeeds; subsequent retrieve throws `KeychainError.notFound`
- All unit tests pass
- No use of `UserDefaults`, files, or in-memory dictionaries for sensitive value storage
- `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` is the access policy for all Keychain items

---

### Constraints

- `CryptoKit` only for encryption — no third-party crypto libraries
- `Security` framework only for Keychain — no third-party Keychain wrappers
- Keychain access policy must be `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` — not a weaker policy
- No new SPM dependencies

---

### Dependencies

- Task 1 (Xcode Project Scaffold) — project must exist
- Task 2 (Core Data Types and Logging) — `Logger` used for error logging within Security module

---

### Risks

- Keychain tests in automated CI on macOS require a correctly configured keychain; Architect should note whether tests require a dedicated test keychain or service identifier to avoid collisions
- `SecItemAdd` returns `errSecDuplicateItem` when a key already exists — Builder must decide whether to overwrite via `SecItemUpdate` or throw; this behavior must be explicit and documented in the acceptance criteria

---

### Implementation Notes

Define a shared `service` constant (e.g. `"com.voxema.app"`) as an internal constant in `KeychainManager`. All Keychain items use this service identifier. The `service` parameter in the public API allows future multi-tenant use without changing the internal default.

---

### Architect Plan

- none (not yet planned)

---

### Files Likely Affected

- `Voxema/Core/Security/EncryptionManager.swift` (new)
- `Voxema/Core/Security/KeychainManager.swift` (new)
- `VoxemaTests/CoreTests/SecurityTests.swift` (new)

---

### Definition of Done

The task is considered complete when:
- Implementation satisfies all acceptance criteria
- Reviewer approves the changes
- `docs/TASKS.md` status is updated to `completed`

---

---

## Task 4 — NetworkManager: Reachability Monitoring [MVP]

**Task ID:** _(assigned by Iteration Manager)_  
**Status:** planned  
**Owner:** unassigned  
**Created by:** Product agent  
**Priority:** high  
**Complexity:** small  
**Current agent:** none  
**Related PRD section:** Offline-First UX, Technical Constraints  
**Pipeline stage:** cross-cutting  

---

### Goal

Implement `NetworkManager` — a `NWPathMonitor`-based reachability monitor that exposes current connectivity state as a published property for offline-first behavior. After this task, `ModelManager` and the Summarize stage can check connectivity before attempting downloads or cloud API calls.

---

### Scope

- `ConnectionType` enum — in `Core/Networking/ConnectionType.swift`:
  - Cases: `.wifi`, `.cellular`, `.wiredEthernet`, `.other`, `.none`
- `NetworkManager` — in `Core/Networking/NetworkManager.swift`:
  - `@Published var isConnected: Bool`
  - `@Published var connectionType: ConnectionType`
  - Wraps `NWPathMonitor` (Network framework)
  - Debounced state updates: minimum 500ms between state change publications to prevent flapping
  - Starts monitoring on `init()` using a dedicated `DispatchQueue`
  - `deinit` cancels the monitor cleanly
  - `ObservableObject` conformance for SwiftUI integration
  - Internal: `updateState(from path: NWPath)` — maps `NWPath` to `isConnected` and `ConnectionType`
- Unit tests in `VoxemaTests/CoreTests/NetworkManagerTests.swift`:
  - State transition test: mock `NWPath` with `.satisfied` → `isConnected == true`
  - State transition test: mock `NWPath` with `.unsatisfied` → `isConnected == false`
  - `ConnectionType` mapping: wifi interface → `.wifi`, cellular → `.cellular`, other → `.other`, no interface → `.none`
  - Debounce test: rapid path changes within debounce window produce a single publication

---

### Non-Goals

- No HTTP request logic
- No download management (that is Task 5, ModelManager)
- No retry logic (retry belongs to callers — Summarize stage, ModelManager)
- No reachability for specific hosts (only path-level reachability)
- No `URLSession`-based reachability checks

---

### Inputs

- `docs/ARCHITECTURE.md` — NetworkManager section (NWPathMonitor, published `isConnected`, `connectionType`, consumers)
- `docs/PRD.md` — Offline-First UX (cloud degradation behavior table)

---

### Outputs

- `Core/Networking/ConnectionType.swift`
- `Core/Networking/NetworkManager.swift`
- `VoxemaTests/CoreTests/NetworkManagerTests.swift`

---

### Acceptance Criteria

- `NetworkManager` initializes without crash and starts monitoring
- `isConnected` reflects the current path satisfaction state within the debounce window
- `connectionType` correctly maps wifi, cellular, wired ethernet, other, and disconnected states
- Debounce: path changes within 500ms produce at most one published state update
- `deinit` cancels `NWPathMonitor` cleanly (no retain cycles, no leaked threads)
- `NWPathMonitor` can be injected (or its behavior mocked) for unit testing
- All unit tests pass

---

### Constraints

- `NWPathMonitor` only — no third-party reachability libraries (Reachability.swift, etc.)
- No new SPM dependencies
- `NetworkManager` must be `@MainActor` or publish on the main actor for SwiftUI `@Published` safety

---

### Dependencies

- Task 1 (Xcode Project Scaffold) — project must exist
- Task 2 (Core Data Types and Logging) — `Logger` available for internal logging

---

### Risks

- `NWPathMonitor` is difficult to mock directly (it's a final class with no protocol). Architect should decide whether to introduce a thin `PathMonitorProtocol` abstraction for testability, or use a different test strategy (e.g. subclassing, integration tests only). This decision should be documented in the implementation plan.
- Debounce implementation using `DispatchQueue.asyncAfter` vs Combine `.debounce` — either is acceptable; Architect should choose the simpler approach

---

### Implementation Notes

`NetworkManager` is consumed by `ModelManager` (download gating) and the Summarize stage (cloud provider fallback). It is also used by `UpdateManager` (Sparkle connectivity check). Design it as a shared singleton or injectable dependency — Architect should decide the injection approach during planning.

---

### Architect Plan

- none (not yet planned)

---

### Files Likely Affected

- `Voxema/Core/Networking/ConnectionType.swift` (new)
- `Voxema/Core/Networking/NetworkManager.swift` (new)
- `VoxemaTests/CoreTests/NetworkManagerTests.swift` (new)

---

### Definition of Done

The task is considered complete when:
- Implementation satisfies all acceptance criteria
- Reviewer approves the changes
- `docs/TASKS.md` status is updated to `completed`

---

---

## Task 5 — ModelManager: Manifest, Lifecycle, and Downloads [MVP]

**Task ID:** _(assigned by Iteration Manager)_  
**Status:** planned  
**Owner:** unassigned  
**Created by:** Product agent  
**Priority:** high  
**Complexity:** large  
**Current agent:** none  
**Related PRD section:** Technical Constraints (Model packaging), Core Capabilities — Transcription, DEC-2  
**Pipeline stage:** cross-cutting  

---

### Goal

Implement `ModelManager` — the module responsible for model catalog management, integrity verification, hardware-based LLM recommendation, and on-demand model downloads. After this task, the Transcribe and Diarize stages have a reliable, verified path to model files, and the onboarding flow has the hardware detection it needs for LLM tier recommendation.

---

### Scope

**`models-manifest.json`** — in `Voxema/Resources/models-manifest.json`:
- JSON structure with a `models` array. Each entry contains:
  - `id: String` — stable identifier (e.g. `"whisper-tiny"`, `"ecapa-tdnn"`, `"qwen-2.5-3b-q4"`)
  - `family: String` — `"whisper"` | `"ecapa-tdnn"` | `"llm"`
  - `name: String` — human-readable name
  - `quality_tier: String` — `"bundled"` | `"good"` | `"better"` | `"best"`
  - `size_bytes: Int`
  - `sha256: String` — placeholder `"TODO_SHA256"` for models not yet available; real checksum for bundled models once available
  - `ram_required_bytes: Int` — minimum RAM required to load this model
  - `bundled: Bool` — `true` for Whisper tiny and ECAPA-TDNN
  - `download_url: String?` — `null` for bundled models
  - `file_path: String` — relative path within `~/Library/Application Support/Voxema/Models/` or bundle path for bundled models
- MVP initial model list per DEC-2:
  - Whisper tiny (~75MB) — bundled, `quality_tier: "bundled"`
  - ECAPA-TDNN ONNX (~25MB) — bundled, `quality_tier: "bundled"`
  - Whisper base (~142MB) — on-demand, `quality_tier: "good"`
  - Whisper small (~466MB) — on-demand, `quality_tier: "better"`
  - Qwen 2.5 3B Q4_K_M (~1.9GB) — on-demand, `quality_tier: "good"`, `ram_required_bytes: 8GB`
  - Qwen 2.5 7B Q4_K_M (~4.5GB) — on-demand, `quality_tier: "better"`, `ram_required_bytes: 16GB`

**`ModelManager`** — in `Core/ModelManager/ModelManager.swift`:
- `loadManifest() throws -> [ModelEntry]` — reads and decodes `models-manifest.json` from app bundle
- `verifyBundledModels() throws` — SHA-256 integrity check for bundled models (skip if sha256 is placeholder)
- `detectDeviceRAM() -> UInt64` — reads `ProcessInfo.processInfo.physicalMemory`
- `recommendedLLMTier() -> String` — returns `"good"` for ≤8GB RAM, `"better"` for 16GB+
- `modelPath(for id: String) -> URL?` — returns file URL for a model: bundle path for bundled, `~/Library/Application Support/Voxema/Models/` for downloaded
- `isModelAvailable(id: String) -> Bool` — returns `true` if model file exists and passes integrity check
- `downloadModel(id: String, progress: @escaping (Double) -> Void) async throws` — downloads model via `URLSession`, streams to `~/Library/Application Support/Voxema/Models/`, verifies SHA-256 on completion, publishes download progress
- `cancelDownload(id: String)` — cancels in-progress download for a model
- `@Published var downloadStates: [String: DownloadState]` — tracks download state per model ID
- `DownloadState` enum: `.idle`, `.downloading(progress: Double)`, `.downloaded`, `.failed(Error)`
- Uses `NetworkManager.isConnected` before attempting download — throws if offline
- Enforces storage path: `~/Library/Application Support/Voxema/Models/{family}/{id}/`
- `ObservableObject` conformance

**Unit tests** in `VoxemaTests/CoreTests/ModelManagerTests.swift`:
- Manifest parsing: valid JSON → correct `[ModelEntry]` count and field values
- Manifest parsing: malformed JSON → throws
- `detectDeviceRAM()` returns a non-zero value (integration test, not mocked)
- `recommendedLLMTier()` for 8GB → `"good"`, for 16GB → `"better"`
- `modelPath(for:)` for bundled model → returns bundle URL
- `modelPath(for:)` for not-yet-downloaded model → returns expected path (even if file doesn't exist)
- `isModelAvailable(for:)` for non-existent file → `false`

---

### Non-Goals

- No actual Whisper inference (that is Task 6 and Phase 2 TRANSCRIBE tasks)
- No ONNX Runtime loading (ONNX Runtime integration is deferred — ModelManager provides file paths only)
- No llama.cpp integration
- No UI for model selection (that is `UI-ONBOARDING` and `UI-SETTINGS`, Phase 4)
- No real SHA-256 checksums in the manifest for on-demand models (placeholder values are acceptable at this stage)

---

### Inputs

- `docs/ARCHITECTURE.md` — ModelManager section (bundled models, downloaded models, storage location, integrity, hardware detection, lazy loading, 8GB discipline)
- `docs/DECISIONS.md` — DEC-2 (hybrid bundle strategy, curated model list, LLM quality tiers, storage path)
- `docs/PRD.md` — Technical Constraints (model packaging row)

---

### Outputs

- `Voxema/Resources/models-manifest.json`
- `Core/ModelManager/ModelManager.swift`
- `Core/ModelManager/ModelEntry.swift` (Codable struct for manifest entries)
- `Core/ModelManager/DownloadState.swift` (enum)
- `VoxemaTests/CoreTests/ModelManagerTests.swift`

---

### Acceptance Criteria

- `loadManifest()` successfully decodes `models-manifest.json` with all 6 MVP model entries
- `detectDeviceRAM()` returns a non-zero value on any Apple Silicon Mac
- `recommendedLLMTier()` returns `"good"` for devices with ≤8GB RAM and `"better"` for ≥16GB
- `modelPath(for: "whisper-tiny")` returns a valid bundle URL pointing to the bundled model location
- `isModelAvailable(id:)` returns `false` for a model whose file does not exist on disk
- `downloadModel` checks `NetworkManager.isConnected` before starting — throws a structured error when offline
- `downloadStates` updates to `.downloading(progress:)` during download and `.downloaded` on completion
- SHA-256 verification runs on download completion — mismatched checksum throws and removes partial file
- Models are stored in `~/Library/Application Support/Voxema/Models/{family}/{id}/`
- All unit tests pass

---

### Constraints

- No third-party download libraries — `URLSession` only
- Storage path must be exactly `~/Library/Application Support/Voxema/Models/` per DEC-2
- No model names hardcoded outside of `models-manifest.json` — all model references go through `ModelManager`
- `DownloadState` must be `@Published` per model ID (not a single global state)
- On-demand model SHA-256 values may use placeholder `"TODO_SHA256"` at this stage — but the verification logic must be implemented and active (it skips only when value is the literal placeholder)

---

### Dependencies

- Task 1 (Xcode Project Scaffold) — project must exist
- Task 2 (Core Data Types and Logging) — `Logger` available
- Task 4 (NetworkManager) — `NetworkManager.isConnected` required for download gating

---

### Risks

- ONNX Runtime integration for ECAPA-TDNN is unresolved (DEC-2). `ModelManager` provides the file path — the actual ONNX Runtime loading is deferred. The ONNX Runtime placeholder in Task 1 must be noted in the implementation plan so Architect plans the bridge for the DIARIZE task.
- Real SHA-256 checksums for Whisper and Qwen models require downloading the actual model files. Placeholder checksums are acceptable for this task; a follow-up FIX task should replace placeholders before the first public beta.
- `URLSession` background downloads on macOS behave differently from iOS — Architect should confirm whether background `URLSessionConfiguration` is appropriate for DMG apps or whether foreground download with UI progress is sufficient at MVP

---

### Implementation Notes

The `ModelManager` does not load models into memory — it only manages file paths and download lifecycle. The inference engines (Whisper.cpp, ONNX Runtime, llama.cpp) will reference `ModelManager.modelPath(for:)` during their respective pipeline stage tasks. Keep ModelManager's responsibilities strictly at the file management layer.

---

### Architect Plan

- none (not yet planned)

---

### Files Likely Affected

- `Voxema/Resources/models-manifest.json` (new)
- `Voxema/Core/ModelManager/ModelManager.swift` (new)
- `Voxema/Core/ModelManager/ModelEntry.swift` (new)
- `Voxema/Core/ModelManager/DownloadState.swift` (new)
- `VoxemaTests/CoreTests/ModelManagerTests.swift` (new)

---

### Definition of Done

The task is considered complete when:
- Implementation satisfies all acceptance criteria
- Reviewer approves the changes
- `docs/TASKS.md` status is updated to `completed`
- `models-manifest.json` is committed to the repository with all 6 MVP model entries

---

---

## Task 6 — PipelineCoordinator: Stage Orchestration [MVP]

**Task ID:** _(assigned by Iteration Manager)_  
**Status:** planned  
**Owner:** unassigned  
**Created by:** Product agent  
**Priority:** high  
**Complexity:** medium  
**Current agent:** none  
**Related PRD section:** Core Capabilities, Technical Constraints, Quality Requirements  
**Pipeline stage:** cross-cutting  

---

### Goal

Implement `PipelineCoordinator` — the sequential stage orchestrator that enforces all cross-stage rules from `docs/PIPELINE_CONTRACTS.md`. After this task, the pipeline has a working shell that Builder can plug real stage implementations into one by one: Capture stage (Task 7), then Transcribe, Diarize, Summarize, and Export in subsequent phases.

---

### Scope

**`PipelineStage` protocol** — in `Pipeline/Coordinator/PipelineStage.swift`:
- `associatedtype Input`
- `associatedtype Output`
- `func execute(_ input: Input) async throws -> Output`
- `var stageName: String { get }`

**`PipelineProgress` enum** — in `Pipeline/Coordinator/PipelineProgress.swift`:
- Cases: `.idle`, `.running(stage: String, progress: Double)`, `.completed`, `.failed(PipelineError)`
- Conforms to `Equatable`

**`PipelineCoordinator`** — in `Pipeline/Coordinator/PipelineCoordinator.swift`:
- `ObservableObject` with `@Published var progress: PipelineProgress`
- Accepts stage implementations via dependency injection in `init`:
  - `captureStage: any CaptureStageProtocol` (protocol defined in `Pipeline/Capture/`)
  - `transcribeStage: any TranscribeStageProtocol` (protocol defined in `Pipeline/Transcribe/`)
  - `diarizeStage: any DiarizeStageProtocol` (protocol defined in `Pipeline/Diarize/`)
  - `summarizeStage: any SummarizeStageProtocol` (protocol defined in `Pipeline/Summarize/`)
  - `exportStage: any ExportStageProtocol` (protocol defined in `Pipeline/Export/`)
  - `modelManager: ModelManager`
- `func run(recordingConfig: RecordingConfig) async throws -> Meeting` — runs all five stages in sequence:
  1. Calls `captureStage.execute(recordingConfig)` → `[AudioStream]`
  2. Calls `modelManager` to load Whisper model; calls `transcribeStage.execute(audioStreams)` → `[TranscribedSegment]`; unloads model
  3. Calls `modelManager` to load ECAPA-TDNN; calls `diarizeStage.execute(segments)` → `[DiarizedSegment]`; unloads model
  4. Calls `modelManager` to load LLM; calls `summarizeStage.execute(diarizedSegments)` → `MeetingSummary?`; unloads model
  5. Calls `exportStage.execute((diarizedSegments, summary, metadata))` → `Meeting`
  6. Updates `progress` at each stage boundary
- Enforces cross-stage rules from `docs/PIPELINE_CONTRACTS.md`:
  - Immutable input/output — stages receive value types; no mutation
  - No direct stage-to-stage calls — all routing through coordinator
  - Errors raised at stage boundaries with `PipelineError` — never swallowed
  - Error messages never contain content (enforced by `PipelineError` design from Task 2)
  - Model load/unload at stage boundaries via `ModelManager`
- `RecordingConfig` struct — in `Pipeline/Coordinator/RecordingConfig.swift`: `microphoneDeviceID: String`, `whisperModelID: String`, `llmModelID: String?`, `summaryProviderID: String`
- Stage protocol stubs — one protocol per pipeline stage directory (empty protocol conformances — no implementation yet):
  - `Pipeline/Capture/CaptureStageProtocol.swift`
  - `Pipeline/Transcribe/TranscribeStageProtocol.swift`
  - `Pipeline/Diarize/DiarizeStageProtocol.swift`
  - `Pipeline/Summarize/SummarizeStageProtocol.swift`
  - `Pipeline/Export/ExportStageProtocol.swift`

**Unit tests** in `VoxemaTests/PipelineTests/PipelineCoordinatorTests.swift`:
- Stage sequencing: mock stages return expected outputs; `run()` produces a `Meeting` with correct data
- Error propagation: mock capture stage throws → `progress` transitions to `.failed`, error is of type `PipelineError.captureError`
- Error propagation: mock transcribe stage throws → `.failed` with `PipelineError.transcribeError`
- Progress publishing: `progress` moves through `.running(stage:)` for each stage during execution
- No content in error messages: `PipelineError` reason strings in mock errors do not contain transcript text (structural test)

---

### Non-Goals

- No real stage implementations (Capture, Transcribe, Diarize, Summarize, Export — those are separate tasks)
- No SwiftUI views consuming `PipelineCoordinator` (that is `UI-RECORDING`, Phase 3)
- No pipeline pause/resume (not in PRD)
- No concurrent stage execution (pipeline is strictly sequential)
- No pipeline versioning enforcement (version field is in `PIPELINE_CONTRACTS.md` for documentation; runtime enforcement is future work)

---

### Inputs

- `docs/PIPELINE_CONTRACTS.md` — stage contracts, cross-stage rules, data representations
- `docs/ARCHITECTURE.md` — PipelineCoordinator section (stage execution, model lifecycle, error propagation, progress reporting)
- `docs/ARCHITECTURE_GUARDRAILS.md` — Rules 1–6 (pipeline invariants)

---

### Outputs

- `Pipeline/Coordinator/PipelineStage.swift` (protocol)
- `Pipeline/Coordinator/PipelineProgress.swift` (enum)
- `Pipeline/Coordinator/PipelineCoordinator.swift`
- `Pipeline/Coordinator/RecordingConfig.swift`
- Stage protocol stubs in each `Pipeline/` subdirectory (5 files)
- `VoxemaTests/PipelineTests/PipelineCoordinatorTests.swift`

---

### Acceptance Criteria

- `PipelineCoordinator.run()` with all mock stages succeeds and returns a `Meeting`
- `progress` transitions: `.idle` → `.running("capture")` → `.running("transcribe")` → `.running("diarize")` → `.running("summarize")` → `.running("export")` → `.completed`
- A mock stage that throws causes `progress` to transition to `.failed(PipelineError)` — pipeline stops, does not continue to next stages
- Error type is a `PipelineError` with the correct stage-specific case
- `PipelineError` messages in tests do not contain any simulated transcript content
- `ModelManager` load/unload is called at the correct stage boundaries (verifiable via mock `ModelManager`)
- All unit tests pass
- Stage protocol stubs compile without errors
- `PipelineCoordinator` compiles and initializes with mock stage conformances

---

### Constraints

- Must enforce all 6 cross-stage rules from `docs/PIPELINE_CONTRACTS.md` (immutability, no direct calls, structured errors, no content in errors, model lifecycle, version awareness)
- Stage injection is required — no hardcoded stage instantiation inside coordinator
- `PipelineCoordinator` must be usable with mock stages in tests — no untestable dependencies
- No new SPM dependencies
- The 5 stage protocol stubs define input/output types matching `docs/PIPELINE_CONTRACTS.md` exactly

---

### Dependencies

- Task 1 (Xcode Project Scaffold) — project structure
- Task 2 (Core Data Types and Logging) — `PipelineError`, all pipeline data types
- Task 5 (ModelManager) — `ModelManager` used for model lifecycle coordination

---

### Risks

- Using `any Protocol` (existentials) for stage injection in Swift 5.9 requires careful handling if stage protocols have associated types. Architect should decide between existentials (`any CaptureStageProtocol`) and generic type parameters (or a type-erased wrapper) during planning.
- Progress publishing from async context to `@MainActor @Published` requires explicit dispatch — Architect must address actor isolation in the implementation plan

---

### Implementation Notes

The stage protocol stubs in this task define only the input/output contract — they contain no implementation. Task 7 (Capture) will provide the first real conformance to `CaptureStageProtocol`. All subsequent phase tasks will provide conformances to the remaining protocols. The coordinator must be designed so that adding a real stage implementation requires no changes to `PipelineCoordinator.swift` itself.

---

### Architect Plan

- none (not yet planned)

---

### Files Likely Affected

- `Voxema/Pipeline/Coordinator/PipelineStage.swift` (new)
- `Voxema/Pipeline/Coordinator/PipelineProgress.swift` (new)
- `Voxema/Pipeline/Coordinator/PipelineCoordinator.swift` (new)
- `Voxema/Pipeline/Coordinator/RecordingConfig.swift` (new)
- `Voxema/Pipeline/Capture/CaptureStageProtocol.swift` (new stub)
- `Voxema/Pipeline/Transcribe/TranscribeStageProtocol.swift` (new stub)
- `Voxema/Pipeline/Diarize/DiarizeStageProtocol.swift` (new stub)
- `Voxema/Pipeline/Summarize/SummarizeStageProtocol.swift` (new stub)
- `Voxema/Pipeline/Export/ExportStageProtocol.swift` (new stub)
- `VoxemaTests/PipelineTests/PipelineCoordinatorTests.swift` (new)

---

### Definition of Done

The task is considered complete when:
- Implementation satisfies all acceptance criteria
- Reviewer approves the changes
- `docs/TASKS.md` status is updated to `completed`

---

---

## Task 7 — Capture Module: System Audio and Microphone [MVP]

**Task ID:** _(assigned by Iteration Manager)_  
**Status:** planned  
**Owner:** unassigned  
**Created by:** Product agent  
**Priority:** high  
**Complexity:** large  
**Current agent:** none  
**Related PRD section:** Core Capabilities — Recording, Privacy & Security Requirements, Quality Requirements (Recording startup latency ≤2s)  
**Pipeline stage:** capture  

---

### Goal

Implement the Capture pipeline stage: two-channel audio recording from system audio (ScreenCaptureKit) and microphone (AVAudioEngine), producing encrypted temporary audio files as `[AudioStream]`. After this task, the first real pipeline stage can be plugged into `PipelineCoordinator` and audio recording becomes functional end-to-end (recording only — no transcription yet).

---

### Scope

**`SystemAudioCapture`** — in `Pipeline/Capture/SystemAudioCapture.swift`:
- ScreenCaptureKit-based system audio capture (macOS 13+, `SCStream` with audio-only configuration)
- Captures remote participants' audio as 16kHz mono PCM
- Writes encrypted PCM data to a temporary file using `EncryptionManager`
- State machine: `idle → recording → stopping → idle`
- Permission check: `SCShareableContent` / `SCStreamConfiguration` permission status
- Error handling:
  - Permission denied → `PipelineError.captureError(reason: "Screen Recording permission denied")`
  - Device unavailable → stop capture, preserve data captured so far
  - Disk space insufficient → stop capture, return partial data with error

**`MicrophoneCapture`** — in `Pipeline/Capture/MicrophoneCapture.swift`:
- `AVAudioEngine`-based microphone capture
- Captures local user's microphone as 16kHz mono PCM
- Configurable microphone device via `AVAudioSessionPortDescription` device ID
- Writes encrypted PCM data to a temporary file using `EncryptionManager`
- Same state machine as `SystemAudioCapture`
- Error handling:
  - Permission denied → `PipelineError.captureError(reason: "Microphone permission denied")`
  - Device disconnected → stop capture, preserve data captured so far

**`AudioSessionManager`** — in `Pipeline/Capture/AudioSessionManager.swift`:
- Coordinates `SystemAudioCapture` and `MicrophoneCapture` as two parallel streams
- `start(config: RecordingConfig) async throws` — starts both captures simultaneously
- `stop() async throws -> [AudioStream]` — stops both captures, returns two `AudioStream` values (one `local`, one `remote`)
- Format negotiation: configures both captures to 16kHz mono PCM (Whisper.cpp requirement)
- Checks `AVCaptureDevice.authorizationStatus(for: .audio)` and SCK permission before starting
- Provides `recordingDuration: TimeInterval` (elapsed time since start)

**`CaptureStage`** — in `Pipeline/Capture/CaptureStage.swift`:
- Conforms to `CaptureStageProtocol` (defined in Task 6)
- `func execute(_ input: RecordingConfig) async throws -> [AudioStream]`
- Delegates to `AudioSessionManager`
- On success: returns exactly 2 `AudioStream` values (`.local` channel + `.remote` channel)
- On failure: throws `PipelineError.captureError`

**Permission helper** — `PermissionChecker` (or static methods on `AudioSessionManager`):
- `checkScreenRecordingPermission() -> Bool` — returns current Screen Recording permission status
- `checkMicrophonePermission() -> Bool` — returns current Microphone permission status

**Unit tests** in `VoxemaTests/PipelineTests/CaptureTests.swift`:
- State machine: `idle → recording → stopping → idle` transitions
- `AudioStream` output: correct `channel` values (`.local` and `.remote`)
- `AudioStream` output: `format` matches 16kHz mono PCM spec
- Error conditions: missing permission → `PipelineError.captureError` thrown (mocked permission status)
- `EncryptionManager` called for temp file writes (mock/verify call)
- Integration test (skip if no screen recording permission): `checkScreenRecordingPermission()` returns a Bool without crashing

---

### Non-Goals

- No transcription (that is Task TRANSCRIBE, Phase 2)
- No recording UI or start/stop controls (that is `UI-RECORDING`, Phase 3)
- No real-time transcription during capture (not in MVP scope)
- No audio format conversion beyond target PCM format
- No audio compression
- No persisting audio beyond temporary encrypted files
- No audio playback

---

### Inputs

- `RecordingConfig` (from Task 6) — `microphoneDeviceID`, model IDs
- User action (simulated in tests): start/stop recording command
- `EncryptionManager` (from Task 3) — for encrypting temp audio files
- `Logger` (from Task 2) — for structured logging

**Stage contract inputs (from `docs/PIPELINE_CONTRACTS.md`):**
- User action: start recording
- Audio device configuration (microphone selection)

---

### Outputs

- `[AudioStream]` — exactly two streams: one `local`, one `remote`
- Encrypted temporary PCM audio files at paths referenced by `AudioStream.file_path`

**Stage contract outputs (from `docs/PIPELINE_CONTRACTS.md`):**
- `[AudioStream]` — exactly two streams: `channel: "local"`, `channel: "remote"`

---

### Acceptance Criteria

- `CaptureStage.execute()` returns exactly 2 `AudioStream` values: one `.local` and one `.remote`
- Both `AudioStream` values have `format` matching `PCM 16kHz mono` (as specified in `PIPELINE_CONTRACTS.md`)
- Temporary audio files are encrypted (written via `EncryptionManager`)
- State machine: `idle → recording → stopping → idle` — no illegal transitions
- Permission denied for Screen Recording → `PipelineError.captureError` thrown, no crash
- Permission denied for Microphone → `PipelineError.captureError` thrown, no crash
- `checkScreenRecordingPermission()` and `checkMicrophonePermission()` return current permission status without crashing
- `AudioStream.stream_id` is a non-nil `UUID`
- `AudioStream.recorded_at` is set to the recording start time
- All unit tests pass

---

### Constraints

- ScreenCaptureKit audio capture requires macOS 13+ — no earlier API fallback
- Must use `EncryptionManager` from Task 3 for all temp file writes — no plaintext audio on disk
- Temp files must be written to `FileManager.default.temporaryDirectory` (not `~/Library/`)
- `AVAudioEngine` on macOS: Architect must verify correct API (`AVAudioSession` does not exist on macOS; use `AVAudioEngine` direct device configuration or `CoreAudio` — see `LESSONS_LEARNED.md` FEAT-4 note)
- No new SPM dependencies
- Capture module must not have knowledge of transcription, diarization, or any later pipeline stage

---

### Dependencies

- Task 1 (Xcode Project Scaffold) — project structure and entitlements
- Task 2 (Core Data Types and Logging) — `AudioStream`, `PipelineError`, `Logger`
- Task 3 (Security) — `EncryptionManager` for temp file encryption
- Task 6 (PipelineCoordinator) — `CaptureStageProtocol` and `RecordingConfig`

---

### Risks

- **ScreenCaptureKit audio-only capture API:** The audio-only `SCStream` API was introduced in macOS 13 and has had behavior changes across minor versions. Architect must verify the correct `SCStreamConfiguration` setup for audio-only capture (no screen content captured). This is a known complexity noted in `LESSONS_LEARNED.md` (FEAT-4: AudioSessionManager / CoreAudio note).
- **AVAudioEngine macOS device selection:** `AVAudioSession` does not exist on macOS. Device selection must use `AVAudioEngine` input node configuration or `CoreAudio` directly. Architect must confirm the correct API during planning.
- **Recording startup latency ≤2 seconds:** PRD Quality Requirement. Architect should estimate ScreenCaptureKit initialization time and flag if async content sharing picker UI might be triggered on first launch (vs. permission already granted).
- **Entitlement for audio-only SCK capture:** May require a specific entitlement beyond the standard screen recording entitlement. Architect must verify.
- **Temp file cleanup on failure:** If recording fails mid-capture, partial encrypted temp files must be deleted. Architect should define the cleanup policy in the implementation plan.

---

### Implementation Notes

This is the highest-risk task in Phase 1 due to the ScreenCaptureKit audio-only API complexity and the macOS-specific AVAudioEngine device selection. Architect should prioritize verifying the SCK audio-only path before designing the full implementation plan. A minimal spike (does `SCStream` with audio-only config produce PCM samples on macOS 13+?) would reduce risk significantly.

The `AudioSessionManager` API note from `LESSONS_LEARNED.md` (FEAT-4): "verify correct macOS API during Builder phase (CoreAudio vs AVAudioSession)" — this must be resolved by Architect before Builder begins.

---

### Architect Plan

- none (not yet planned)

---

### Files Likely Affected

- `Voxema/Pipeline/Capture/SystemAudioCapture.swift` (new)
- `Voxema/Pipeline/Capture/MicrophoneCapture.swift` (new)
- `Voxema/Pipeline/Capture/AudioSessionManager.swift` (new)
- `Voxema/Pipeline/Capture/CaptureStage.swift` (new)
- `Voxema/Pipeline/Capture/PermissionChecker.swift` (new)
- `Voxema/Pipeline/Capture/CaptureStageProtocol.swift` (update — add input/output types to stub from Task 6)
- `VoxemaTests/PipelineTests/CaptureTests.swift` (new)

---

### Definition of Done

The task is considered complete when:
- Implementation satisfies all acceptance criteria
- Reviewer approves the changes
- `docs/TASKS.md` status is updated to `completed`
- `LESSONS_LEARNED.md` updated with any new findings about ScreenCaptureKit audio-only API or macOS audio device selection

---

---

## Phase 1 Build Order Summary

The 7 tasks form a strict dependency chain. Task 1 (Xcode Scaffold) is the foundation — nothing else can start without a compilable project. Task 2 (Core Data Types and Logging) provides the shared vocabulary that every subsequent module depends on, including `PipelineError` and `Logger`. Task 3 (Security) and Task 4 (NetworkManager) are independent of each other and both depend only on Tasks 1 and 2 — they can be sequenced in either order or, if the workflow supports it, executed in close succession. Task 5 (ModelManager) depends on both Security (for bundled model integrity) and NetworkManager (for download gating), so it must follow Tasks 3 and 4. Task 6 (PipelineCoordinator) depends on Task 2 for data types and Task 5 for ModelManager lifecycle coordination — it builds the orchestration shell with mock stages and no real implementations. Task 7 (Capture) is the first real pipeline stage implementation, depending on all prior tasks: the project (1), data types (2), encryption (3), and the coordinator protocol stubs (6). The critical path is linear: 1 → 2 → 3 → 4 → 5 → 6 → 7. The highest-risk task is Task 7 (ScreenCaptureKit audio-only API complexity and macOS AVAudioEngine device selection), which is why all dependency tasks are designed to be small, verifiable, and independently reviewable before Builder reaches it.

---
