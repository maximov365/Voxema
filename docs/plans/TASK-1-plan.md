# Implementation Plan — TASK-1: Xcode Project Scaffold

**Produced by:** Architect  
**Date:** 2026-03-29  
**Task:** TASK-1 — Xcode Project Scaffold  
**Status:** produced  
**Quality loop iteration:** 0

---

## Task Restatement

Create a compilable, correctly-configured Xcode project that establishes the full folder structure from `docs/ARCHITECTURE.md`, correct entitlements and Info.plist keys, SPM dependencies for GRDB and Sparkle 2, an ONNX Runtime placeholder, and empty test scaffolding — with zero business logic.

---

## Assumptions Made

1. **Bundle ID:** `com.voxema.app` — no conflicting decision found in `docs/DECISIONS.md`; stated clearly and applied consistently.

2. **Single test target with subdirectories:** All downstream tasks in `docs/plans/phase1-tasks.md` (Tasks 2–7) place test files at paths like `VoxemaTests/CoreTests/SecurityTests.swift` and `VoxemaTests/PipelineTests/CaptureTests.swift`. Creating separate targets (`VoxemaPipelineTests`, `VoxemaCoreTests`, `VoxemaFeatureTests`) would break all those file references. This plan uses a **single `VoxemaTests` target** with three Xcode group subdirectories (`PipelineTests/`, `CoreTests/`, `FeatureTests/`). This is the correct interpretation for downstream compatibility.

3. **App Sandbox disabled:** Voxema distributes via DMG (not Mac App Store). Direct-distribution apps do not require the App Sandbox entitlement. `com.apple.security.app-sandbox = false` is the correct posture. Entitlements like `com.apple.security.device.audio-input` are sandbox-only and are NOT required here.

4. **`com.apple.security.screen-recording` is NOT a real entitlement key.** Screen Recording permission is requested at runtime via `NSScreenCaptureUsageDescription` in Info.plist. No entitlement file key is needed for non-sandboxed apps.

5. **Xcode project file approach:** The project is created as `Voxema.xcodeproj` (no workspace) since SPM is handled via Xcode's integrated package resolution (no separate `Package.swift` for the app target). Xcode generates an `.xcworkspace` automatically when SPM packages are resolved.

6. **GRDB version:** `.upToNextMajor(from: "6.0.0")` (latest stable GRDB 6.x as of plan date). Builder should verify the latest 6.x tag before adding.

7. **Sparkle version:** `.upToNextMajor(from: "2.0.0")` (latest stable Sparkle 2.x). Builder should verify the latest 2.x tag.

8. **Test placeholder files:** Each test subdirectory gets a single empty `XCTestCase` subclass file so that Xcode recognizes the group and the test target compiles with at least one (empty) test. These files contain no assertions — they are scaffolding only.

---

## Plan

### Step 1 — Create the Xcode project [small]

Using Xcode 15+ UI or `xcodegen` / manual `.xcodeproj` authoring (Builder's choice — Xcode UI is simplest and least error-prone for a one-time scaffold):

- **Project name:** `Voxema`
- **Organization identifier:** `com.voxema`
- **Bundle identifier:** `com.voxema.app`
- **Interface:** SwiftUI
- **Language:** Swift
- **Lifecycle:** SwiftUI App
- **Include Tests:** Yes (creates `VoxemaTests` target)
- **Minimum Deployment:** macOS 13.0
- **Swift version:** Swift 5 (maps to Swift 5.9+ in `SWIFT_VERSION = 5.0` build setting)

After creation, verify in the target's **General** tab:
- Deployment info → macOS 13.0
- Minimum macOS is 13.0 in `MACOSX_DEPLOYMENT_TARGET`

Rename the default `VoxemaTests` test target if Xcode named it differently.

**Files produced by this step (Xcode-managed):**
- `Voxema.xcodeproj/`
- `Voxema/VoxemaApp.swift` (Xcode default — will be moved/replaced in Step 5)
- `Voxema/ContentView.swift` (Xcode default — will be replaced in Step 5)
- `VoxemaTests/VoxemaTests.swift` (default test file — will be replaced in Step 6)

---

### Step 2 — Configure build settings for Hardened Runtime and code signing [small]

In the **Voxema** app target's **Signing & Capabilities** tab:

1. Enable **Hardened Runtime** (click "+ Capability" → Hardened Runtime).
2. Under Hardened Runtime, leave all exception boxes **unchecked for now** — the Sparkle-required exception (`Disable Library Validation`) will be controlled via the entitlements file instead (Step 3).
3. Set **Signing Certificate** to `Sign to Run Locally` (development) or `Apple Development` for the scaffold. Production Developer ID signing is a release pipeline concern, not a scaffold concern.
4. Enable **Automatically manage signing** with team ID (or set to manual for CI compatibility — either is acceptable at scaffold stage).

In the **Build Settings** tab, verify:
- `SWIFT_VERSION` = `5.0`
- `MACOSX_DEPLOYMENT_TARGET` = `13.0`
- `ENABLE_HARDENED_RUNTIME` = `YES`
- `CODE_SIGN_ENTITLEMENTS` = `Voxema/Voxema.entitlements` (will be created in Step 3)

---

### Step 3 — Create `Voxema/Voxema.entitlements` [small]

Create `Voxema/Voxema.entitlements` with the following content:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <false/>
    <key>com.apple.security.cs.disable-library-validation</key>
    <true/>
</dict>
</plist>
```

**Entitlement rationale:**

| Key | Value | Reason |
|-----|-------|--------|
| `com.apple.security.app-sandbox` | `false` | Direct DMG distribution; App Sandbox is a Mac App Store requirement. ScreenCaptureKit audio-only capture works in non-sandboxed apps via System Settings Screen Recording permission (`NSScreenCaptureUsageDescription`). |
| `com.apple.security.cs.disable-library-validation` | `true` | **Required for Sparkle 2.** Sparkle dynamically loads its `Sparkle.framework` and XPC helper bundles at runtime. Without this, Hardened Runtime will block the dynamic load and Sparkle auto-update will fail silently. Per DEC-4: Sparkle 2 via SPM + notarization. |

**Entitlements NOT required (and why):**

| Key | Status | Reason |
|-----|--------|--------|
| `com.apple.security.cs.allow-jit` | Not needed | Whisper.cpp and llama.cpp use Metal/ANE, not JIT compilation. Add only if a future dependency requires JIT. |
| `com.apple.security.cs.allow-unsigned-executable-memory` | Not needed | No unsigned executable memory is mapped by any current dependency. |
| `com.apple.security.device.audio-input` | Not needed | This is a **sandbox-only** entitlement. Non-sandboxed apps request microphone access via `NSMicrophoneUsageDescription` at runtime. |
| `com.apple.security.screen-recording` | Not a real entitlement key | Screen Recording permission is requested at runtime via `NSScreenCaptureUsageDescription` in Info.plist and granted by the user in System Settings. No entitlement file key exists for this in non-sandboxed apps. |

**Note for Task 7 (Capture):** If ScreenCaptureKit audio-only capture on macOS 13+ requires any additional entitlement not listed here, that is the Capture Architect's responsibility to identify. This scaffold establishes the minimum known-correct entitlement set.

In Xcode, set `CODE_SIGN_ENTITLEMENTS = Voxema/Voxema.entitlements` in Build Settings for the Voxema target (both Debug and Release configurations).

---

### Step 4 — Configure `Info.plist` [small]

Xcode 13+ uses a generated Info.plist by default. Add the following keys via the target's **Info** tab, or by editing the `Info.plist` file directly if it exists as a file on disk:

| Key | Type | Value |
|-----|------|-------|
| `NSScreenCaptureUsageDescription` | String | `"Voxema records system audio to capture meeting participants. Audio is processed entirely on your device."` |
| `NSMicrophoneUsageDescription` | String | `"Voxema records your microphone to capture your voice during meetings. Audio is processed entirely on your device."` |
| `NSHumanReadableCopyright` | String | `"Copyright © 2026 Voxema. All rights reserved."` |
| `CFBundleShortVersionString` | String | `"0.1.0"` |
| `CFBundleVersion` | String | `"1"` |

**Note:** If the project uses Xcode's auto-generated Info.plist (no `Info.plist` file on disk), add these keys via the target's Info tab in Xcode. If a file-based `Info.plist` was created at project time, edit it directly. Do not create a duplicate `Info.plist`.

---

### Step 5 — Create `App/` placeholder files [small]

Delete or replace the Xcode-generated `VoxemaApp.swift` and `ContentView.swift` files. Place them under `Voxema/App/` (Xcode group: `App`):

**`Voxema/App/VoxemaApp.swift`:**
```swift
import SwiftUI

@main
struct VoxemaApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
```

**`Voxema/App/ContentView.swift`:**
```swift
import SwiftUI

struct ContentView: View {
    var body: some View {
        Text("Voxema")
            .font(.largeTitle)
            .padding()
    }
}
```

Remove any files Xcode generated outside `App/` for these (the default `Voxema/VoxemaApp.swift` and `Voxema/ContentView.swift` at the root of the source folder).

In Xcode's project navigator, ensure these files are under the `App` group (not at the `Voxema` root group level).

---

### Step 6 — Create the full folder structure with placeholder files [medium]

Create every directory listed below as an **Xcode group** (not a filesystem-only folder). In Xcode, groups backed by real filesystem folders ("folder references") are preferred for clarity — use **New Group with Folder** to keep the navigator and filesystem in sync.

For each group, create the placeholder `.swift` file listed. These placeholder files exist solely to prevent Xcode from ignoring empty groups. They must contain only a minimal comment — no imports, no logic.

**Convention for placeholder files:**
```swift
// Placeholder — implementation pending.
```

**Complete group and placeholder file list:**

| Xcode Group Path | Filesystem Path | Placeholder File |
|---|---|---|
| `Voxema/App` | `Voxema/App/` | *(already populated by Step 5 — no additional placeholder needed)* |
| `Voxema/Features` | `Voxema/Features/` | — |
| `Voxema/Features/Recording` | `Voxema/Features/Recording/` | `Recording+Placeholder.swift` |
| `Voxema/Features/MeetingLibrary` | `Voxema/Features/MeetingLibrary/` | `MeetingLibrary+Placeholder.swift` |
| `Voxema/Features/MeetingDetail` | `Voxema/Features/MeetingDetail/` | `MeetingDetail+Placeholder.swift` |
| `Voxema/Features/Settings` | `Voxema/Features/Settings/` | `Settings+Placeholder.swift` |
| `Voxema/Features/Onboarding` | `Voxema/Features/Onboarding/` | `Onboarding+Placeholder.swift` |
| `Voxema/Pipeline` | `Voxema/Pipeline/` | — |
| `Voxema/Pipeline/Coordinator` | `Voxema/Pipeline/Coordinator/` | `Coordinator+Placeholder.swift` |
| `Voxema/Pipeline/Capture` | `Voxema/Pipeline/Capture/` | `Capture+Placeholder.swift` |
| `Voxema/Pipeline/Transcribe` | `Voxema/Pipeline/Transcribe/` | `Transcribe+Placeholder.swift` |
| `Voxema/Pipeline/Diarize` | `Voxema/Pipeline/Diarize/` | `Diarize+Placeholder.swift` |
| `Voxema/Pipeline/Summarize` | `Voxema/Pipeline/Summarize/` | `Summarize+Placeholder.swift` |
| `Voxema/Pipeline/Export` | `Voxema/Pipeline/Export/` | `Export+Placeholder.swift` |
| `Voxema/Core` | `Voxema/Core/` | — |
| `Voxema/Core/Models` | `Voxema/Core/Models/` | `Models+Placeholder.swift` |
| `Voxema/Core/Storage` | `Voxema/Core/Storage/` | `Storage+Placeholder.swift` |
| `Voxema/Core/Security` | `Voxema/Core/Security/` | `Security+Placeholder.swift` |
| `Voxema/Core/ModelManager` | `Voxema/Core/ModelManager/` | `ONNXRuntimePlaceholder.swift` *(see Step 7)* |
| `Voxema/Core/Networking` | `Voxema/Core/Networking/` | `Networking+Placeholder.swift` |
| `Voxema/Core/LicenseManager` | `Voxema/Core/LicenseManager/` | `LicenseManager+Placeholder.swift` |
| `Voxema/Core/UpdateManager` | `Voxema/Core/UpdateManager/` | `UpdateManager+Placeholder.swift` |
| `Voxema/Core/Logging` | `Voxema/Core/Logging/` | `Logging+Placeholder.swift` |
| `Voxema/Resources` | `Voxema/Resources/` | — |
| `Voxema/Resources/Prompts` | `Voxema/Resources/Prompts/` | `.gitkeep` *(see note below)* |
| `Voxema/Resources/Models` | `Voxema/Resources/Models/` | `.gitkeep` *(see note below)* |
| `Voxema/Resources/Assets` | `Voxema/Resources/Assets/` | *(backed by `Assets.xcassets` — see Step 8)* |

**Note on `Resources/Prompts/` and `Resources/Models/`:** These directories hold non-Swift assets. Xcode groups for resource folders can be added as folder references. Use a `.gitkeep` file to ensure git tracks the empty directory. Do NOT add `.gitkeep` to the Xcode target's compile sources.

**Note on `Voxema/Resources/Models/`:** This folder holds bundled ML models (Whisper tiny, ECAPA-TDNN). It must be added to `Copy Bundle Resources` in Build Phases (not Compile Sources). At scaffold stage, the directory exists but contains no actual model files — those are added in Task 5 (ModelManager). The `.gitignore` (Step 10) excludes the contents of this directory.

**All `*+Placeholder.swift` files** must be added to the **Voxema** app target (Compile Sources) so Xcode treats them as source files and keeps the groups visible in the navigator.

---

### Step 7 — Create `ONNXRuntimePlaceholder.swift` [small]

Create `Voxema/Core/ModelManager/ONNXRuntimePlaceholder.swift` with the following content:

```swift
// TODO: ONNX Runtime integration — manual setup required.
//
// ONNX Runtime is not available via Swift Package Manager.
// The Diarize stage (ECAPA-TDNN speaker embeddings) requires ONNX Runtime
// with CoreML Execution Provider for ANE/GPU delegation (DEC-2).
//
// Integration approach to be defined in the DIARIZE Architect plan.
// Steps required before the DIARIZE task begins:
//   1. Download the ONNX Runtime for Apple Silicon release from:
//      https://github.com/microsoft/onnxruntime/releases
//   2. Add OnnxRuntime.xcframework to Frameworks, Libraries, and Embedded Content
//      in the Voxema target.
//   3. Add a bridging header or Swift C interop wrapper in this module.
//   4. Embed the framework and set correct signing settings.
//
// Do not add any ONNX Runtime code here until the DIARIZE Architect plan
// defines the full integration contract.
```

This file is added to the Voxema app target (Compile Sources) so that `Core/ModelManager/` is a non-empty, navigable group in Xcode.

---

### Step 8 — Add SPM dependencies: GRDB and Sparkle 2 [small]

Add both packages via Xcode's **File → Add Package Dependencies…** dialog.

**GRDB.swift:**
- URL: `https://github.com/groue/GRDB.swift`
- Dependency rule: Up to Next Major Version, from `6.0.0`
- Add product `GRDB` to the **Voxema** app target
- Do NOT add to the test target (tests in Task 2–7 mock the storage layer)

**Sparkle:**
- URL: `https://github.com/sparkle-project/Sparkle`
- Dependency rule: Up to Next Major Version, from `2.0.0`
- Add product `Sparkle` to the **Voxema** app target

**Sparkle XPC service setup (required for Sparkle to function):**

After adding the Sparkle package, Xcode requires two additional XPC service bundle configurations. These are part of Sparkle's standard SPM integration:

1. In the **Voxema** target's **Build Phases**, ensure the Sparkle `run_after_build_phases.sh` script (or Sparkle's SPM build phase) runs after compilation. Sparkle's SPM integration includes a run-script build phase (`Copy Sparkle Resources`); verify it is present after adding the package.

2. Embed the Sparkle XPC services: in the **Voxema** target → **Build Phases** → **Copy Files** (or Sparkle's automatic embed phase), verify `Autoupdater.app` and `Updater.app` (Sparkle helper bundles) are embedded. Sparkle 2's SPM integration handles this via its own build phase scripts — verify they appear automatically after the package resolves.

3. The `com.apple.security.cs.disable-library-validation = true` entitlement (Step 3) is the primary requirement for Sparkle's dynamic library loading. No additional XPC-specific entitlement keys are required for the scaffold — full Sparkle runtime configuration (SUFeedURL, EdDSA public key in Info.plist) is a concern for the UpdateManager task, not this scaffold.

**Do NOT add ONNX Runtime as an SPM dependency.** See `ONNXRuntimePlaceholder.swift` (Step 7) for the required manual integration note.

**Verification:** After package resolution, the project must compile cleanly. If Sparkle or GRDB introduce compile errors at this stage (before any usage), check that the correct product names were selected from each package.

---

### Step 9 — Set up `Assets.xcassets` and app icon placeholder [small]

The default Xcode project creates `Assets.xcassets` in the `Voxema/` root group. **Move** (or re-reference) it to `Voxema/Resources/Assets/Assets.xcassets` so it resides under the `Resources/Assets` group.

Update the app target's `ASSETCATALOG_COMPILER_APPICON_NAME` build setting to `AppIcon` (Xcode default — verify it is set).

In `Assets.xcassets`:
- `AppIcon` image set: leave all slots empty (Xcode will use the default placeholder). A solid-color icon or the Xcode placeholder icon is acceptable for the scaffold. Do not source or design a real icon in this task.
- `AccentColor` color set: leave at system default.

**Note:** `Assets.xcassets` must remain listed under **Copy Bundle Resources** in Build Phases. If moving it changes its path, update the `ASSETCATALOG_COMPILER_APPICON_NAME` reference accordingly.

---

### Step 10 — Create test target subdirectory groups [small]

In the `VoxemaTests` target, create three Xcode groups (with filesystem folders):

| Group | Filesystem Path | Placeholder File |
|---|---|---|
| `VoxemaTests/PipelineTests` | `VoxemaTests/PipelineTests/` | `PipelineTests+Placeholder.swift` |
| `VoxemaTests/CoreTests` | `VoxemaTests/CoreTests/` | `CoreTests+Placeholder.swift` |
| `VoxemaTests/FeatureTests` | `VoxemaTests/FeatureTests/` | `FeatureTests+Placeholder.swift` |

Each placeholder file contains one minimal `XCTestCase` subclass with no test methods:

**`VoxemaTests/PipelineTests/PipelineTests+Placeholder.swift`:**
```swift
import XCTest

final class PipelineTestsPlaceholder: XCTestCase {}
```

**`VoxemaTests/CoreTests/CoreTests+Placeholder.swift`:**
```swift
import XCTest

final class CoreTestsPlaceholder: XCTestCase {}
```

**`VoxemaTests/FeatureTests/FeatureTests+Placeholder.swift`:**
```swift
import XCTest

final class FeatureTestsPlaceholder: XCTestCase {}
```

Remove or repurpose the default `VoxemaTests/VoxemaTests.swift` file that Xcode generated (rename it to `VoxemaTests+Placeholder.swift` in the root of `VoxemaTests/` or delete it if the three subdirectory placeholders are sufficient for compilation).

All placeholder test files must be added to the **VoxemaTests** target (not the app target).

---

### Step 11 — Create `.gitignore` [small]

Create `.gitignore` at the repository root:

```gitignore
# Xcode
.DS_Store
*.xcuserstate
xcuserdata/
*.xcworkspace/xcuserdata/
DerivedData/
build/
*.pbxuser
*.mode1v3
*.mode2v3
*.perspectivev3

# Swift Package Manager
.build/
.swiftpm/

# Xcode SPM package resolved file — commit for apps, exclude for libraries
# (for an app, committing is recommended for reproducible builds)
# Voxema.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved

# Code signing
*.p12
*.mobileprovision

# Instruments
*.trace

# Model files — large binary files, not committed to git
# Bundled models must be managed separately (see docs/DECISIONS.md DEC-2)
Voxema/Resources/Models/
*.gguf
*.onnx
*.mlmodelc
*.bin

# Environment
.env
.env.local

# macOS
.DS_Store
.AppleDouble
.LSOverride
```

**Note on `Package.resolved`:** For app targets (as opposed to library packages), committing `Package.resolved` is recommended for reproducible builds. The line above is commented out to indicate this is a deliberate choice — do not uncomment to exclude it unless there is a specific reason.

---

### Step 12 — Create `README.md` [small]

Create `README.md` at the repository root:

```markdown
# Voxema

Privacy-first macOS meeting recorder, transcriber, and analyzer. All processing on-device.

## Prerequisites

- macOS 13.0 (Ventura) or later (for running)
- macOS 14.0 (Sonoma) or later recommended for development
- Xcode 15 or later
- Apple Silicon Mac (M1 or later)

## Setup

1. Clone the repository:
   git clone <repo-url>
   cd Voxema

2. Open the project:
   open Voxema.xcodeproj

3. Let Xcode resolve Swift Package Manager dependencies (automatic on first open).

4. Select the Voxema scheme and your Mac as the run destination.

5. Build and run (⌘R).

## Known manual integration requirements

### ONNX Runtime (required before the Diarize stage can be implemented)

ONNX Runtime is not available via Swift Package Manager. Manual integration is required
before implementing the DIARIZE pipeline stage (ECAPA-TDNN speaker embeddings).

See `Voxema/Core/ModelManager/ONNXRuntimePlaceholder.swift` for integration instructions.
Download: https://github.com/microsoft/onnxruntime/releases

### Sparkle EdDSA key (required for release builds only)

Sparkle verifies update packages using an EdDSA signature. For release builds:

1. Generate an EdDSA key pair using Sparkle's `generate_keys` tool.
2. Store the private key securely in a password manager (NOT in this repository).
   Loss of the private key prevents delivering updates to existing installations.
3. Add the public key to Info.plist under the `SUPublicEDKey` key.
4. Configure `SUFeedURL` in Info.plist to point to the appcast on GitHub Pages.

The EdDSA key is NOT required for development builds or local testing.

## Architecture

See `docs/ARCHITECTURE.md` for the full system architecture.

Pipeline: Capture → Transcribe → Diarize → Summarize → Export

## Privacy

Audio never leaves the device. Transcripts go to cloud LLM only with explicit per-session consent.
See `docs/PRD.md` for full privacy and security requirements.
```

---

## Acceptance Criteria

How Builder verifies the plan is complete:

1. **Compiles with zero errors and zero warnings (excluding expected deprecation-free scaffold):**
   - Select the `Voxema` scheme → Product → Build (⌘B) → Build Succeeded
   - No red errors in the Issue Navigator

2. **App runs and displays ContentView placeholder:**
   - Run on macOS 13+ (or macOS 14+ for development) → Window shows "Voxema" text label
   - No crash on launch

3. **All folder groups visible in Xcode navigator:**
   - Expand the `Voxema` source group in the navigator and verify all subdirectories from `docs/ARCHITECTURE.md` are present as groups: `App`, `Features/*`, `Pipeline/*`, `Core/*`, `Resources/*`

4. **Test target compiles and has three subdirectory groups:**
   - Product → Test (⌘U) → all 3 placeholder `XCTestCase` subclasses are discovered (0 failures, 0 assertions — empty test classes pass)
   - `PipelineTests/`, `CoreTests/`, `FeatureTests/` groups visible in navigator under `VoxemaTests`

5. **GRDB and Sparkle 2 link correctly:**
   - Project → Package Dependencies tab lists both packages with resolved versions
   - `import GRDB` compiles without error if added to any source file (do not commit such a test import — use a quick manual check)
   - `import Sparkle` compiles without error (same transient check)

6. **Entitlements file present and correctly referenced:**
   - `Voxema/Voxema.entitlements` exists on disk
   - `CODE_SIGN_ENTITLEMENTS = Voxema/Voxema.entitlements` in Build Settings (both Debug and Release)
   - `ENABLE_HARDENED_RUNTIME = YES`

7. **Info.plist has all required keys:**
   - `NSScreenCaptureUsageDescription` — non-empty string
   - `NSMicrophoneUsageDescription` — non-empty string
   - `NSHumanReadableCopyright` — present
   - `CFBundleShortVersionString` — `0.1.0`

8. **ONNX Runtime placeholder file exists:**
   - `Voxema/Core/ModelManager/ONNXRuntimePlaceholder.swift` exists with the `// TODO:` comment block

9. **`.gitignore` excludes build artifacts and model files:**
   - `git status` on a freshly built project does NOT show `DerivedData/`, `*.xcuserstate`, or `Voxema/Resources/Models/` as untracked

10. **`README.md` exists at the repository root** with prerequisites and manual integration notes.

---

## Non-goals

- No business logic of any kind
- No real UI beyond `Text("Voxema")` in ContentView
- No ONNX Runtime SPM resolution or any ONNX Runtime code
- No `models-manifest.json` content (Task 5)
- No Whisper or llama.cpp binaries
- No Swift files other than `VoxemaApp.swift`, `ContentView.swift`, the folder placeholder files, and `ONNXRuntimePlaceholder.swift`
- No actual test assertions or test logic (test methods are empty scaffolding)
- No Sparkle runtime configuration (`SUFeedURL`, `SUPublicEDKey` in Info.plist — those are an UpdateManager concern)
- No LicenseManager implementation (post-MVP per DEC-1)
- No CI/CD pipeline configuration

---

## Dependencies

**External:**
- Xcode 15+ (build toolchain)
- GRDB.swift 6.x (via SPM — `https://github.com/groue/GRDB.swift`)
- Sparkle 2.x (via SPM — `https://github.com/sparkle-project/Sparkle`)

**Internal:** None (this is the foundational task — no prior tasks exist)

---

## Files

| Action | Path | Reason |
|--------|------|--------|
| create | `Voxema.xcodeproj/` | Xcode project root |
| create | `Voxema/App/VoxemaApp.swift` | `@main` SwiftUI App entry point |
| create | `Voxema/App/ContentView.swift` | Minimal ContentView placeholder |
| create | `Voxema/Voxema.entitlements` | Hardened Runtime + Sparkle entitlements |
| create | `Voxema/Features/Recording/Recording+Placeholder.swift` | Group scaffold |
| create | `Voxema/Features/MeetingLibrary/MeetingLibrary+Placeholder.swift` | Group scaffold |
| create | `Voxema/Features/MeetingDetail/MeetingDetail+Placeholder.swift` | Group scaffold |
| create | `Voxema/Features/Settings/Settings+Placeholder.swift` | Group scaffold |
| create | `Voxema/Features/Onboarding/Onboarding+Placeholder.swift` | Group scaffold |
| create | `Voxema/Pipeline/Coordinator/Coordinator+Placeholder.swift` | Group scaffold |
| create | `Voxema/Pipeline/Capture/Capture+Placeholder.swift` | Group scaffold |
| create | `Voxema/Pipeline/Transcribe/Transcribe+Placeholder.swift` | Group scaffold |
| create | `Voxema/Pipeline/Diarize/Diarize+Placeholder.swift` | Group scaffold |
| create | `Voxema/Pipeline/Summarize/Summarize+Placeholder.swift` | Group scaffold |
| create | `Voxema/Pipeline/Export/Export+Placeholder.swift` | Group scaffold |
| create | `Voxema/Core/Models/Models+Placeholder.swift` | Group scaffold |
| create | `Voxema/Core/Storage/Storage+Placeholder.swift` | Group scaffold |
| create | `Voxema/Core/Security/Security+Placeholder.swift` | Group scaffold |
| create | `Voxema/Core/ModelManager/ONNXRuntimePlaceholder.swift` | ONNX Runtime integration note (Step 7) |
| create | `Voxema/Core/Networking/Networking+Placeholder.swift` | Group scaffold |
| create | `Voxema/Core/LicenseManager/LicenseManager+Placeholder.swift` | Group scaffold |
| create | `Voxema/Core/UpdateManager/UpdateManager+Placeholder.swift` | Group scaffold |
| create | `Voxema/Core/Logging/Logging+Placeholder.swift` | Group scaffold |
| create | `Voxema/Resources/Prompts/.gitkeep` | Directory scaffold for git |
| create | `Voxema/Resources/Models/.gitkeep` | Directory scaffold for git |
| create | `Voxema/Resources/Assets/Assets.xcassets` | App icon + accent color (moved from Xcode default location) |
| create | `VoxemaTests/PipelineTests/PipelineTests+Placeholder.swift` | Test group scaffold |
| create | `VoxemaTests/CoreTests/CoreTests+Placeholder.swift` | Test group scaffold |
| create | `VoxemaTests/FeatureTests/FeatureTests+Placeholder.swift` | Test group scaffold |
| create | `.gitignore` | Standard Xcode + Voxema model exclusions |
| create | `README.md` | Developer setup guide |
| read-only (referenced) | `docs/ARCHITECTURE.md` | Folder structure source of truth |
| read-only (referenced) | `docs/DECISIONS.md` | DEC-2 (ONNX Runtime), DEC-4 (Sparkle 2) |

**Total new files: ~30** (Xcode project, 2 app sources, 1 entitlements, 17 placeholder Swift files, 2 gitkeep, 1 asset catalog, 3 test placeholders, 1 .gitignore, 1 README.md). This is within scope for a foundational scaffold task. Per `.cursor/rules.md`, changes beyond 10 files require brief justification: a project scaffold is explicitly a multi-file initialization task where every file is required to establish the project structure. No file is redundant.

---

## Risks

1. **Sparkle XPC service build phases:** Sparkle 2's SPM integration requires specific build phase scripts to copy the Autoupdater and Updater helper bundles. If Xcode does not auto-add these after SPM resolution, Builder must add them manually per [Sparkle's SPM integration guide](https://sparkle-project.org/documentation/). Failure to embed the XPC helpers will not cause compile errors but will cause Sparkle to fail silently at runtime.

2. **`Assets.xcassets` path relocation:** Moving `Assets.xcassets` from the Xcode default location to `Voxema/Resources/Assets/` requires updating the `ASSETCATALOG_COMPILER_APPICON_NAME` reference and verifying the asset catalog is still listed in Copy Bundle Resources. If this causes repeated build issues, leave `Assets.xcassets` at the Xcode default location and note it as a deviation.

3. **Xcode group vs. filesystem folder sync:** Xcode groups created without a backing filesystem folder ("virtual groups") do not create physical directories. Builder must use **New Group with Folder** (or create directories first, then add them to Xcode) to ensure filesystem and navigator are in sync. If groups are virtual, subsequent tasks that create files in those directories by filesystem path will not be recognized by Xcode automatically.

4. **GRDB and Sparkle version freshness:** The versions specified (GRDB 6.0.0, Sparkle 2.0.0) are minimums. Builder should verify the latest 6.x / 2.x tags at the time of implementation and use those as the `from:` version to avoid starting behind a security or compatibility patch.

5. **`com.apple.security.cs.disable-library-validation` for Sparkle:** This is the documented requirement for Sparkle 2 + Hardened Runtime. If a future Sparkle version changes this requirement, the entitlements file must be updated. The risk is low for the scaffold stage.

---

## Architectural Notes

- This task makes no pipeline or architectural decisions. It establishes structure only.
- The `Voxema/Resources/Models/` directory maps to the bundled models path referenced in `docs/ARCHITECTURE.md` (ModelManager section) and `docs/DECISIONS.md` DEC-2. This directory is NOT committed with model files — Task 5 (ModelManager) handles model bundling.
- The `Voxema/Resources/Prompts/` directory maps to `prompts/` as referenced in `docs/ARCHITECTURE_GUARDRAILS.md` Rule 7 (prompt templates) and resolved in the FEAT-4 `LESSONS_LEARNED.md` entry. The canonical location is `Voxema/Resources/Prompts/` per `docs/ARCHITECTURE.md`.
- App Sandbox is intentionally disabled. This is the correct posture for a DMG-distributed macOS app using ScreenCaptureKit. This decision should be confirmed in `docs/DECISIONS.md` if not already recorded. No new DECISIONS.md entry is strictly required for this well-established pattern, but the Reviewer may choose to record it.
- No new `docs/DECISIONS.md` entry is proposed for this task — all relevant decisions (Sparkle DEC-4, ONNX Runtime DEC-2) are already recorded.

---

## Smallest Next Step

Builder should create the Xcode project (Step 1) in Xcode's UI, verify it compiles, then proceed through Steps 2–12 in order — each step is independently verifiable with a build.

---

## Optional Follow-ups

- After Task 5 (ModelManager): add actual bundled model files (`Whisper tiny`, `ECAPA-TDNN ONNX`) to `Voxema/Resources/Models/` and configure them in Copy Bundle Resources.
- After DEC-4 implementation in UpdateManager task: add `SUFeedURL` and `SUPublicEDKey` to Info.plist for Sparkle runtime configuration.
- Consider recording the App Sandbox = false decision explicitly in `docs/DECISIONS.md` if the Reviewer requests a formal record.
