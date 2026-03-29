# Lessons learned

Project-specific log of what went wrong in completed workflows, what review feedback repeated, and what worked. **Append-only** by default — do not delete history; Iteration Manager may add a short "superseded by" note if a lesson no longer applies.

**Maintainer:** Iteration Manager appends a new section after each workflow that reached completion (Reviewer approved) or was explicitly closed with a documented outcome.

**Audience:** Every agent reads this file (with `KNOWN_PATTERNS.md`) before starting work, per `AGENTS.md`.

---

## How to write an entry

Use one block per closed workflow. Keep it factual and short.

```markdown
## YYYY-MM-DD — <task id or short title>

**Workflow outcome:** completed | closed (other)

### What went wrong
- ...

### Repeated must_fix / review / security themes
- ... (quote or paraphrase recurring themes from Spec Reviewer, Reviewer, Security Reviewer)

### What worked well
- ... (optional; durable wins also belong in `KNOWN_PATTERNS.md`)

### Follow-ups
- ... (optional — links to `docs/TASKS.md` entries if any)
```

---

## Entries

*(Iteration Manager appends below this line.)*

## 2026-03-29 — Xcode build: Sparkle binary artifact corruption

**Workflow outcome:** closed (environment fix, no code changes)

### What went wrong
- After FIX-1 (Xcode project creation via UI), a prior Xcode session partially resolved Sparkle 2.9.0 via SPM — it downloaded the CLI tools (`bin/generate_appcast`, etc.) but failed to extract `Sparkle.xcframework` from the `Sparkle-for-Swift-Package-Manager.zip` binary artifact. The stale `SourcePackages/artifacts/sparkle/Sparkle/` directory contained only the tools, not the xcframework.
- `xcodebuild` tried to copy the non-existent `Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework` and failed with `No such file or directory`. This cascaded into a `__preview.dylib` linker error.

### Fix
- Deleted `DerivedData` and `SourcePackages` entirely. A clean build succeeded immediately because the xcodeproj source files are currently scaffold/stubs that do not yet import GRDB or Sparkle.

### Important follow-up pattern
- `Voxema.xcodeproj` does NOT have GRDB or Sparkle added as package dependencies in its project settings — they only exist in `Package.swift`. Before implementing TASK-2 through TASK-7, GRDB and Sparkle must be added to the xcodeproj via Xcode UI (File → Add Package Dependencies).

### Follow-ups
- TASK-2: before starting, add GRDB + Sparkle to xcodeproj via Xcode UI

---

## 2026-03-29 — PRD-update-v2 (PRD major revision)

**Workflow outcome:** completed

### What went wrong
- none

### Repeated must_fix / review / security themes
- MVP scope inconsistency: Core Capabilities and User Flows described features (JSON export) not listed in MVP scope. Spec Reviewer caught the mismatch. Lesson: when adding capabilities to the PRD body, always cross-check the MVP scope list.
- Data model cardinality must match PIPELINE_CONTRACTS.md. PRD stated Meeting→Summary as 1→1 but pipeline contracts define summary as optional. Lesson: any entity relationships in PRD must be validated against pipeline contracts before committing.

### What worked well
- User provided detailed change requirements upfront, which enabled a single Product pass with no ambiguity.
- Quality loop resolved both must_fix items in one Reviser iteration (7.8 → 8.3).
- Spec Reviewer caught a real source conflict (PRD vs PIPELINE_CONTRACTS.md cardinality) that would have caused schema issues downstream.

### Follow-ups
- FEAT-1: Discovery for monetization strategy
- FEAT-2: Discovery for model packaging strategy
- Spec Reviewer should_fix: clarify summary failure path in Typical Recording Flow; clarify Activation metric when summarization fails; add C++ bridging risk; add ECAPA-TDNN model availability risk; clarify Speaker entity vs SpeakerIdentity distinction

## 2026-03-29 — PRD-update-v3 (Backend Services, CloudProvider dual-mode)

**Workflow outcome:** completed

### What went wrong
- CloudProvider description was rewritten to describe only the backend-proxied mode, creating an MVP scope inconsistency (CloudProvider in MVP scope but requiring post-MVP backend). Exact repeat of the pattern from PRD-update-v2: capabilities described in the body that conflict with MVP scope list.

### Repeated must_fix / review / security themes
- MVP scope inconsistency (second occurrence). Lesson reinforced: when modifying a capability description in the PRD body, ALWAYS check whether the MVP scope list still matches. This is now a documented recurring pattern.
- Adding a new deployment/infrastructure model (backend proxy) changes the semantics of existing components (CloudProvider). All references to the changed component must be updated consistently — Summarization, Monetization, Offline-First UX, Privacy guardrails.

### What worked well
- Spec Reviewer caught the CloudProvider scope inconsistency on iteration 1 — no downstream confusion.
- Dual-mode CloudProvider (direct API for MVP, Voxema proxy for Pro) resolved the tension cleanly: MVP stays self-contained, Pro adds managed experience.
- Quality loop resolved both must_fix items in one Reviser pass (6.6 → 7.6).

### Follow-ups
- FEAT-3: Discovery for backend technology stack
- FEAT-4: ARCHITECTURE.md update for CloudProvider dual-mode
- Spec Reviewer should_fix: qualify Vision statement re cloud opt-in; qualify MVP scope CloudProvider as direct-API-only; plan PIPELINE_CONTRACTS.md update for provider_used granularity

## 2026-03-29 — PRD-update-v4 (Versioning & Update Strategy, Accessibility)

**Workflow outcome:** completed

### What went wrong
- none

### Repeated must_fix / review / security themes
- none (accepted on first pass; MVP scope cross-check lesson applied proactively — no scope inconsistencies introduced)

### What worked well
- Proactive MVP scope cross-checking (lesson from v2 and v3) prevented any must_fix items. First PRD update to pass quality loop on the first iteration.
- Small, focused changes are lower risk and faster through the quality loop.

### Follow-ups
- FEAT-5: Discovery for Sparkle integration
- Spec Reviewer should_fix: tighten Sparkle MVP scope bullet wording to distinguish "check-for-updates" vs "full auto-update"; consider testable acceptance criterion for update mechanism

## 2026-03-29 — FEAT-1 Discovery + PRD monetization update

**Workflow outcome:** completed

### What went wrong
- MVP scope inconsistency (third occurrence): Monetization Free tier claimed "All Whisper model sizes" while MVP scope lists "tiny/base/small". Also Admin Dashboard described as "F&F beta stage" but MVP has no backend.

### Repeated must_fix / review / security themes
- MVP scope vs body mismatch is now a **three-time recurring pattern**. Every PRD update that adds capabilities to the body risks this. Lesson: before submitting ANY PRD change for review, run a literal line-by-line check of MVP In scope and Not in scope against every claim in the body.

### What worked well
- Discovery FEAT-1 produced comprehensive market research (7 competitors, concrete pricing data) and a clear recommendation (39/40 score).
- Subscription-only Pro is the simplest viable choice — no pipeline changes, gating at UI layer only.
- Lemon Squeezy's JWT offline validation aligns perfectly with offline-first design.

### Follow-ups
- FEAT-3: Backend tech stack Discovery (must account for Lemon Squeezy webhook integration)
- Should_fix: qualify Free tier Whisper wording to lead with MVP scope; align Admin Dashboard "post-beta" phrasing

---

## FEAT-2 — Discovery: Model packaging strategy

**Workflow:** Discovery → PRD update (direct, no quality loop — changes limited to two table cells replacing "Requires Discovery" with concrete strategy)
**Date:** 2026-03-29

### Errors / unexpected
- None. Changes were scoped to replacing placeholder text; no new capabilities or scope items added, so MVP scope inconsistency risk was minimal.

### Repeated themes
- None this cycle.

### What worked well
- Discovery produced actionable research from 4 competitors (MacWhisper, Superwhisper, WhisperKit, speech-swift) confirming industry-standard hybrid bundle approach.
- Explicit decision stability annotations (stable vs. temporary) help future agents know which decisions to revisit.
- Pre-commit MVP scope verification check prevented potential issues — pattern from previous cycles applied proactively.

### Follow-ups
- FEAT-3: Backend tech stack Discovery (next)
- Default LLM (Qwen 2.5 3B) marked as temporary — needs benchmarking with real transcripts post-Builder

---

## FEAT-2 refinement — LLM selection UX

**Workflow:** User feedback → DEC-2 update (no quality loop — UX refinement within existing decision scope)
**Date:** 2026-03-29

### Errors / unexpected
- None.

### What worked well
- User caught a UX gap (hardcoded default vs. user choice) before it became an implementation assumption. Refining decisions during Discovery phase is cheaper than changing them during Build.

---

## FEAT-3 — Discovery: Backend technology stack

**Workflow:** Discovery → PRD update (direct, no quality loop — single table cell replacement)
**Date:** 2026-03-29

### Errors / unexpected
- None. Change was scoped to replacing "Requires Discovery" placeholder in Technical Constraints.

### Repeated themes
- None this cycle. MVP scope check passed — backend is explicitly "Not in scope (MVP)", new content stays in that boundary.

### What worked well
- Cost model in DEC-3 validates DEC-1 pricing ($12/mo, $8/mo annual) with concrete margin data (86–94%).
- Decision stability annotations distinguish what to lock in (language, DB, auth) from what to revisit (hosting, LLM provider).

### Follow-ups
- FEAT-4: ARCHITECTURE.md update for CloudProvider dual-mode
- FEAT-5: Sparkle framework integration Discovery

---

## FEAT-4 — Comprehensive ARCHITECTURE.md update

**Workflow:** Architect → Spec Reviewer → Gatekeeper (accept with should-fix) → direct fixes
**Date:** 2026-03-29

### Errors / unexpected
- None major. Spec Review found 5 should-fix items (no must-fix): missing `generated_at` field in data model, omitted cross-stage rule #6, prompt template path inconsistency, Settings MVP annotations, data flow diagram completeness. All resolved in one pass.

### Repeated themes
- None this cycle. MVP scope boundaries were correctly marked throughout the document (9/10 score from Spec Reviewer).

### What worked well
- Comprehensive Architect update (238 → 489 lines) incorporated DEC-1/2/3 and FEAT-4 in a single pass, avoiding piecemeal doc updates.
- Spec Reviewer caught the `prompts/` vs `Resources/Prompts/` path inconsistency between ARCHITECTURE_GUARDRAILS and ARCHITECTURE.md — important to resolve before Builder phase.
- Observation about AudioSessionManager vs CoreAudio on macOS is useful context for Builder (implementation detail, not architectural concern).
- Pre-existing gap noted: Diarize stage contract in PIPELINE_CONTRACTS.md lists only [TranscribedSegment] as input, but ECAPA-TDNN needs audio. This is a PIPELINE_CONTRACTS issue to address in a future task.

### Follow-ups
- FEAT-5: Sparkle framework integration Discovery (pending)
- PIPELINE_CONTRACTS.md: Diarize stage input may need to include audio file path for ECAPA-TDNN embedding extraction (pre-existing gap)
- AudioSessionManager: verify correct macOS API during Builder phase (CoreAudio vs AVAudioSession)

---

## FEAT-5 — Discovery: Sparkle framework integration

**Workflow:** Discovery → PRD + ARCHITECTURE.md update (direct, no quality loop — straightforward replacement of "Requires Discovery" placeholders + UpdateManager section update)
**Date:** 2026-03-29

### Errors / unexpected
- None. All changes replaced placeholders or updated architectural slots with concrete decisions.

### Repeated themes
- None this cycle. MVP scope check passed — Sparkle was already in MVP scope.

### What worked well
- Discovery identified a critical operational risk (EdDSA key loss) that wasn't in the original PRD risks section. Important to capture early.
- GitHub Pages + GitHub Releases as zero-cost hosting aligns with the project's minimal-infrastructure philosophy.
- Decision to defer delta updates reduces MVP release pipeline complexity significantly.

### Follow-ups
- PIPELINE_CONTRACTS.md: Diarize stage input may need audio file path for ECAPA-TDNN (pre-existing gap)
- AudioSessionManager: verify correct macOS API during Builder phase
- All Discovery tasks (FEAT-1 through FEAT-5) complete — ready for implementation task breakdown

---

## TASK-1 — Xcode Project Scaffold

**Workflow:** Product → Architect → Builder → Security Reviewer → Reviewer (APPROVED WITH MINOR CHANGES)
**Date:** 2026-03-29

### Errors / unexpected
- Builder used `Package.swift` instead of `Voxema.xcodeproj` — correct approach for a code-only Builder (generating raw `.pbxproj` by hand is high-risk). Security Reviewer and Reviewer both noted entitlements not wired to build system. Accepted as valid deviation; FIX-1 created for Xcode project creation.
- `.gitignore` directory-level exclusion prevented `Resources/Models/.gitkeep` from being tracked. Fixed in FIX-1.
- `CFBundleVersion` missing from `Info.plist`. Fixed in FIX-1.

### Repeated themes
- None new this cycle.

### What worked well
- `Package.swift` + `swift build` gives immediate structural verification (zero errors, GRDB 6.29.3, Sparkle 2.9.0 linked).
- Reviewer adjudication pattern: accept deviation + create follow-up FIX task rather than forcing Builder to repeat risky operation.

### Follow-ups
- FIX-1: Xcode project creation (must be done via Xcode UI, not by Builder writing `.pbxproj`)
- TASK-2 can begin in parallel or after FIX-1

---

## 2026-03-29 — FIX-1: Create Voxema.xcodeproj

**Workflow outcome:** completed

### What went wrong
- `PBXFileSystemSynchronizedRootGroup` (Xcode 16 auto-grouping) caused duplicate file references. Had to be removed from `project.pbxproj` via script.
- Sparkle SPM binary artifact (`Sparkle.xcframework`) was missing from `SourcePackages/artifacts/` — only CLI tools had been extracted. Resolved by deleting `DerivedData` and `SourcePackages` for a clean build (stubs don't import Sparkle yet).
- `Voxema/Resources/Models/` was excluded from git by the directory-level `.gitignore` rule; fixed with `!.gitkeep` exception.
- `CFBundleVersion` was missing from `Info.plist`; added value `1`.

### What worked well
- Writing the `.pbxproj` via `scripts/fix_xcodeproj.py` (rather than by hand) gave reproducible, reviewable results.
- `ENABLE_APP_SANDBOX = NO` + `ENABLE_HARDENED_RUNTIME = YES` + `com.apple.security.cs.disable-library-validation = YES` combination correctly reflects ScreenCaptureKit + Sparkle XPC requirements.
- `xcodebuild -scheme Voxema build` reached `BUILD SUCCEEDED` on clean environment.

### Follow-ups
- TASK-2: before starting, add GRDB + Sparkle to `Voxema.xcodeproj` via Xcode UI (File → Add Package Dependencies) — they currently live only in `Package.swift`.

---

## 2026-03-29 — TASK-2: Core data types and structured logging

**Workflow outcome:** completed

### What went wrong
- `Models.swift` was not a placeholder — it already had a complete implementation from a prior Builder pass (TASK-1 scope exceeded). New separate files created conflicting declarations. Fixed by deleting new files and updating the existing `Models.swift`.
- `swift test` requires `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` when using XCTest — Command Line Tools `swift` does not include XCTest. Always run tests as `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --disable-sandbox`.
- `xcodebuild` fails when writing to `~/Library/Developer/Xcode/DerivedData/` in sandboxed shell. Fix: always use `-derivedDataPath .xcode-derived` (project-local).

### What worked well
- Existing `Models.swift` was substantially correct — adding `format` field, `CodingKeys`, `Equatable` on `PipelineError` was incremental and reviewable.
- 24 unit tests covering Codable round-trips, CodingKeys snake_case, PipelineError privacy guard, and Logger smoke test — comprehensive for pure value types.

### Follow-ups
- None blocking. TASK-3 (Security) is next.

---

## FEATURE_MAP.md — Comprehensive update

**Workflow:** Product → Spec Reviewer → Gatekeeper (accept with fixes) → direct fixes
**Date:** 2026-03-29

### Errors / unexpected
- Spec Reviewer caught a must-fix: NETWORKING was placed in Phase 4 but is required by MODELS (Phase 1) and SUMMARIZE (Phase 2). Moved to Phase 1.
- EXPORT → SUMMARIZE dependency wording overstated — summary is optional per PIPELINE_CONTRACTS.md. Clarified.

### Repeated themes
- Phase ordering contradicting dependency rules is a new pattern — similar to MVP scope inconsistencies: internal document consistency needs cross-checking.

### What worked well
- Structured capability index with MVP column prevents ambiguity.
- "Key MVP scope clarifications" block directly addresses recurring MVP scope issue — proactive defense.
- Decision References table links capabilities to DEC-1–DEC-4 for traceability.

---

## 2026-03-29 — TASK-2: Core data types and structured logging

**Workflow outcome:** completed (Reviewer APPROVED, 24/24 tests passed)

### What went wrong
- Sandbox filesystem discrepancy: Write tool and Read tool operated on a different filesystem overlay than Shell with `required_permissions: ["all"]`. This caused false `git status` output and apparent file conflicts. All final file operations were done via Shell with all permissions.
- Models.swift had already been implemented by the user (427-line comprehensive version) before the session. Initial implementation attempts created conflicting individual per-type files.
- pbxproj was transiently corrupted (Sources build phase referenced files not in PBXBuildFile/PBXFileReference sections). Fixed by reverting to committed version and not re-adding individual files.

### What worked well
- `swift test` via Package.swift caught PipelineError API mismatch (tests expected detailed typed cases, not `captureError(reason:)` style). Caught before commit.
- All 24 tests passed once Models.swift was aligned with the test file.
- Builder correctly identified that Models.swift as single source of truth is cleaner than 10 individual per-type files (avoids repeated xcodeproj registration for small value types).

### Patterns confirmed
- Use Shell with `required_permissions: ["all"]` for file reads/writes during implementation to avoid sandbox discrepancy.
- Always verify implementation with `swift test` in addition to `xcodebuild BUILD SUCCEEDED`.
- Check for user-authored implementations on disk before writing new code.

### Follow-ups
- TASK-3: Security module (EncryptionManager + KeychainManager) — next

---

## 2026-03-29 — TASK-3: Security module (EncryptionManager + KeychainManager)

**Workflow outcome:** completed (Reviewer APPROVED, 36/36 tests passed)

### What went wrong
- Nothing significant. Clean first-pass implementation.

### What worked well
- Implementing KeychainManager as enum namespace (no stored properties) satisfies both Sendable and zero-global-state requirements cleanly.
- CryptoKit `AES.GCM.seal` with no nonce argument auto-generates a random nonce per call — `combined` output embeds it, so decryption is self-contained. No manual nonce management needed.
- Test isolation via UUID-prefixed service names avoids Keychain collisions across test runs.
- `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` is the correct attribute for encryption keys: blocks iCloud migration and backup export while remaining accessible during normal use.

### Patterns confirmed
- For infrastructure that wraps OS APIs with no state: prefer `enum` namespaces over structs/classes.
- Always clean up Keychain items in `tearDown` when running tests that write to Keychain.
- AES-GCM `combined` (nonce ‖ ciphertext ‖ tag) is the correct serialisation format for on-disk encrypted blobs.

### TOCTOU note
- `loadOrCreateKey` has a low-probability TOCTOU race if two callers use the same `keyIdentifier` concurrently. Under the sequential pipeline model this is benign. If concurrent encryption is ever needed, re-read the key after a failed `SecItemAdd` (errSecDuplicateItem → retry retrieve).

### Follow-ups
- TASK-4: Audio capture module (ScreenCaptureKit + AVAudioEngine) — next

---

## 2026-03-29 — TASK-4: NetworkManager (NWPathMonitor, offline-first)

**Workflow outcome:** completed (Reviewer APPROVED, 50/50 tests passed)

### What went wrong
- Nothing significant. Clean first-pass implementation.

### What worked well
- `@MainActor final class: ObservableObject` pattern gives both thread safety and SwiftUI compatibility with minimal boilerplate.
- `Task { @MainActor in }` is the correct bridge from `NWPathMonitor`'s background dispatch queue to the main actor — avoids DispatchQueue.main.async anti-pattern in async/await context.
- Polling loop in integration test (`testMonitorDetectsConnectivityAfterStart`) is more reliable than fixed sleep: exits as soon as status updates, avoids flaky timeouts.
- `@Published` `.disconnected` as the initial value enforces offline-first in SwiftUI binding chains for free — any consumer starts in the safe state.

### Patterns confirmed
- For long-lived OS observers (NWPathMonitor, NotificationCenter): `@MainActor final class: ObservableObject` with `[weak self]` capture in the callback is the standard safe pattern.
- `NWPathMonitor.cancel()` is irreversible — document that `stopMonitoring()` means "discard this instance".

### Follow-ups
- TASK-5: ModelManager (models-manifest.json, hardware detection, download infrastructure) — next

---

## 2026-03-29 — TASK-5: ModelManager (models-manifest.json, hardware detection, download)

**Workflow outcome:** completed (Reviewer APPROVED, 77/77 tests passed)

### What went wrong
- `import Combine` missing on first build — `ObservableObject` and `@Published` require it explicitly even on macOS. Fixed immediately.

### What worked well
- `ModelManifest.decode(from: Data)` static method enables full unit-test coverage without Bundle access — all 27 tests inject manifests directly. No Package.swift changes needed.
- `Data(contentsOf:options:.mappedIfSafe)` for SHA-256 of large model files avoids loading gigabytes into RAM — OS handles paging.
- QualityTier Comparable via private `sortOrder` integer is clean and explicit; avoids raw-value ordering assumptions.
- Atomic download pattern (URLSession temp → verify → move) prevents corrupt partial files on disk.

### Security pre-release checklist (from Security Reviewer)
- Replace `placeholder-*-sha256-computed-at-release` in `models-manifest.json` with real SHA-256 values once model binaries are finalized.
- Replace `https://placeholder.voxema.app/models/ecapa-tdnn.onnx` with the real ECAPA-TDNN download URL.

### Patterns confirmed
- Always add `import Combine` when using `ObservableObject` + `@Published` in a file that otherwise doesn't need it.
- Dependency-injectable init (manifest + modelsDirectory + deviceRAMBytes) is the correct pattern for testable infrastructure classes.
- `availableLLMs.first` after sort descending = `recommendedLLM` — simple, correct, O(n log n).

### Follow-ups
- TASK-6: PipelineCoordinator — stage orchestration — next

---

## 2026-03-29 — TASK-6: PipelineCoordinator (stage orchestration, PipelineStage protocol)

**Workflow outcome:** completed (Reviewer APPROVED, 99/99 tests passed)

### What went wrong
- `PipelineStage.swift` (new file) was not in `Voxema.xcodeproj`, causing BUILD FAILED: "cannot find type CaptureStageProtocol in scope". Fixed by adding it via pbxproj Python library.
- Stage files (CaptureStage.swift, etc.) were already in the xcodeproj from FIX-1 — only the new `PipelineStage.swift` needed to be added.

### What worked well
- Per-stage specific protocols (`CaptureStageProtocol`, `TranscribeStageProtocol`, etc.) are simpler and safer than a generic existential `any PipelineStage<Input, Output>` for coordinator-level orchestration. Avoids Swift existential boxing edge cases.
- Mock stages injected into `PipelineCoordinator.init` give full control over stage behavior in tests: error injection, result control, cancel detection.
- `asPipelineError(_:fallback:)` helper enforces typed errors at stage boundaries without verbose try/catch boilerplate.
- `PipelineProgress.from(stage:stageCount:)` — stage index + progress fraction cleanly composes into overall progress without maintaining separate state.

### Patterns confirmed
- Every new Swift file must be added to Voxema.xcodeproj to be compiled by xcodebuild. Use pbxproj library for this (one-line add_file call). swift test uses Package.swift and does NOT require xcodeproj registration.
- Dependency injection for all stage dependencies enables clean unit testing without any real hardware or model files.

### Follow-ups
- TASK-7: Capture module (ScreenCaptureKit system audio + AVAudioEngine microphone) — next
