# Voxema

Privacy-first macOS meeting recorder, transcriber, and analyzer. All processing on-device.

## Prerequisites

- macOS 13.0 (Ventura) or later (for running)
- macOS 14.0 (Sonoma) or later recommended for development
- Xcode 15 or later
- Apple Silicon Mac (M1 or later)

## Setup

1. Clone the repository:
   ```
   git clone <repo-url>
   cd Voxema
   ```

2. Open the project:
   ```
   open Voxema.xcodeproj
   ```
   Or use SPM directly:
   ```
   open Package.swift
   ```

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
