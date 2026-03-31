# Tasks

<!-- Task backlog managed by Iteration Manager. -->
<!-- See docs/TASK_TEMPLATE.md for the task proposal format. -->
<!-- See docs/TASK_BACKLOG_AUTOMATION.md for committed fields, schema, and lifecycle rules. -->

| Task ID | Title | Status | Priority | Complexity |
|---------|-------|--------|----------|------------|
| FEAT-1  | Discovery: Monetization strategy (pricing, feature gating, go-to-market) | completed | high | medium |
| FEAT-2  | Discovery: Model packaging strategy (bundled vs. first-launch download) | completed | medium | medium |
| FEAT-3  | Discovery: Backend technology stack (language, framework, hosting for auth/billing/LLM proxy) | completed | high | medium |
| FEAT-4  | Comprehensive ARCHITECTURE.md update (CloudProvider dual-mode, DEC-1/2/3 alignment, new modules) | completed | medium | medium |
| FEAT-5  | Discovery: Sparkle framework integration (auto-update, code signing, update hosting) | completed | medium | small |
| TASK-1  | Xcode project scaffold (target config, SPM deps, folder structure, entitlements) | completed | high | medium |
| FIX-1   | Create Voxema.xcodeproj: wire entitlements, Hardened Runtime, Sparkle XPC, Assets, fix .gitignore | completed | high | medium |
| TASK-2  | Core data types and structured logging (PIPELINE_CONTRACTS.md structs, PipelineError, Logger) | completed | high | small |
| TASK-3  | Security module: EncryptionManager (AES-256-GCM) and KeychainManager | completed | high | medium |
| TASK-4  | NetworkManager: NWPathMonitor reachability monitoring, offline-first state | completed | high | small |
| TASK-5  | ModelManager: models-manifest.json, hardware detection, download infrastructure | completed | high | large |
| TASK-6  | PipelineCoordinator: stage orchestration, PipelineStage protocol, cross-stage rules | completed | high | medium |
| TASK-7  | Capture module: SystemAudioCapture (ScreenCaptureKit) + MicrophoneCapture (AVAudioEngine) | completed | high | large |
| TASK-8  | Transcription module: WhisperEngine (C bridge) + TranscribeStage (AudioSampleDecoder, no-speech gate) | completed | high | large |
| TASK-9  | Diarize module: EmbeddingEngine (COnnxRuntime C bridge) + SpeakerMatcher + VoiceProfileStore + DiarizeStage | completed | high | large |
| TASK-10 | Summarize module: CLlama C bridge + SummaryProvider (LocalProvider + CloudProvider) + PromptBuilder + SummarizeStage | completed | high | large |
| TASK-11 | Export module: MeetingStore (GRDB SQLite) + MarkdownExporter + JSONExporter + ExportStage | completed | high | large |
| TASK-12 | AppState + Core UI Shell (NavigationSplitView, RecordingView, LibraryView, MeetingDetailView, MenuBarView) | completed | high | large |
| TASK-13 | Export error feedback: surface write failures in MeetingDetailView export actions | completed | low | small |
| TASK-14 | Decouple GRDB from AppState: move failing-store factory into Storage module | completed | low | small |
| TASK-15 | UI Localization: Localizable.xcstrings + EN/RU/SR translations | completed | medium | medium |
| TASK-16 | Brand assets: AppIcon.appiconset + menu bar template image + UI token alignment | completed | high | small |
| TASK-17 | Onboarding wizard: 7-step first-launch flow (permissions, model, summarization, ready) | completed | high | large |
| TASK-18 | Store cloud API key in KeychainManager (follow-up from TASK-17 security review) | completed | medium | small |
| FIX-2   | Screen recording permission flow: observeCoordinator routing bug + startup SCK registration + exit(0) restart | completed | high | small |

| TASK-19 | Settings screen: microphone, transcription model, summarization provider + fix empty model URL in pipeline | completed | high | medium |
| FIX-3   | ModelManager: verify file existence for bundled models — fixes .bundled status without actual file on disk | completed | high | small |
| TASK-20 | Migrate system audio capture from ScreenCaptureKit to Core Audio tap API; raise minimum macOS to 14.2 (DEC-7) | completed | high | medium |
| TASK-21 | Sparkle auto-update integration + DMG release pipeline (GitHub Actions + GitHub Pages appcast) | completed | high | medium |