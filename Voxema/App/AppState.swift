import Foundation
import Combine
import UserNotifications
import GRDB
import AVFoundation
import AppKit
// MARK: - Permission alert kind

/// Identifies which permission is missing when the user tries to start recording.
public enum PermissionRequired: Equatable {
    case systemAudioRecording
    case microphone
}

// MARK: - AppState

/// Central observable state for the Voxema app.
///
/// Bridges `PipelineCoordinator` and `MeetingStore` to SwiftUI.
/// Created once in `VoxemaApp` and injected via `.environmentObject`.
@MainActor
public final class AppState: ObservableObject {

    // MARK: - Published State

    /// Live pipeline state — mirrors `coordinator.state`.
    @Published public private(set) var pipelineState: PipelineState = .idle
    /// Live processing progress — mirrors `coordinator.progress`.
    @Published public private(set) var pipelineProgress: PipelineProgress = .initial
    /// Meetings loaded from `MeetingStore`, ordered by `recordedAt` descending.
    @Published public private(set) var meetings: [Meeting] = []
    /// Currently selected meeting in the library.
    @Published public var selectedMeetingId: UUID?
    /// Active search query — empty string means "show all".
    @Published public var searchQuery: String = "" {
        didSet { applySearch() }
    }
    /// Elapsed seconds since recording started (driven by `timerTask`).
    @Published public private(set) var recordingDuration: TimeInterval = 0
    /// Elapsed seconds since processing started (driven by `processingTimerTask`).
    /// Counts up from 0 while `pipelineState` is `.processing(...)` so the UI
    /// can show a live "processing for Xs…" indicator instead of a static subtitle.
    @Published public private(set) var processingElapsed: Int = 0
    /// Number of background processing jobs in flight. Sidebar uses this to show
    /// a "Processing…" row even when pipelineState is back to .idle.
    @Published public private(set) var backgroundProcessingCount: Int = 0
    /// Last pipeline error surfaced to the UI.
    @Published public var pipelineError: PipelineError?
    /// `true` while notifications permission is being requested.
    @Published public private(set) var notificationsAuthorized = false
    /// Set before recording starts when a required permission is missing.
    @Published public var permissionRequired: PermissionRequired? = nil
    #if DEBUG
    @Published public var sckDiagnostics: String = "not checked"
    #endif

    // MARK: - Dependencies

    public private(set) var coordinator: PipelineCoordinator
    private let store: MeetingStore
    private let log = VoxemaLogger.make(category: "app.state")

    // MARK: - Private

    private var cancellables = Set<AnyCancellable>()
    /// Separate bag for coordinator-only Combine subscriptions so `refreshPipeline()`
    /// can cancel only those without touching unrelated subscriptions.
    private var coordinatorSubscriptions = Set<AnyCancellable>()
    private var timerTask: Task<Void, Never>?
    private var processingTimerTask: Task<Void, Never>?

    // MARK: - Init

    /// Production factory — creates real pipeline stages and opens the database.
    /// Stage configurations are read from `AppPreferences.shared`.
    public static func production() -> AppState {
        do {
            let store = try MeetingStore(databasePath: ExportConfiguration.default.databasePath)
            let coordinator = makeCoordinator(profilePersistence: store)
            return AppState(coordinator: coordinator, store: store)
        } catch {
            let coordinator = makeCoordinator(profilePersistence: nil)
            return AppState(coordinator: coordinator, store: MeetingStore.failing)
        }
    }

    // MARK: - Coordinator factory (reads AppPreferences)

    private static func makeCoordinator(profilePersistence: (any SpeakerProfilePersistence)?) -> PipelineCoordinator {
        let prefs = AppPreferences.shared
        let mm    = ModelManager.shared

        // Microphone: empty UID = system default
        let micUID: String? = prefs.microphoneDeviceUID.isEmpty ? nil : prefs.microphoneDeviceUID
        let captureConfig = CaptureConfiguration(
            tempDirectory: CaptureConfiguration.default.tempDirectory,
            encryptionKeyId: CaptureConfiguration.default.encryptionKeyId,
            microphoneDeviceUID: micUID
        )

        // Whisper: resolve model ID → local file URL via ModelManager
        let whisperURL: URL = {
            let id = prefs.whisperModelId
            guard !id.isEmpty,
                  let model = mm.manifest.models.first(where: { $0.id == id && $0.family == .whisper })
            else { return URL(fileURLWithPath: "") }
            return mm.localURL(for: model)
        }()
        let langPref = prefs.whisperLanguage
        let languageOverride: String? = (langPref == "auto" || langPref.isEmpty) ? nil : langPref
        let transcribeConfig = TranscribeConfiguration(modelURL: whisperURL, language: languageOverride)

        // Summarization: resolve provider + LLM model
        let provider: ProviderType = prefs.summarizationProvider == "cloud" ? .cloud : .local
        let llmURL: URL = {
            let id = prefs.llmModelId
            guard !id.isEmpty,
                  let model = mm.manifest.models.first(where: { $0.id == id && $0.family == .llm })
            else { return URL(fileURLWithPath: "") }
            return mm.localURL(for: model)
        }()
        let summarizeConfig = SummarizeConfiguration(
            provider: provider,
            modelName: prefs.llmModelId,
            promptTemplate: PromptBuilder.defaultTemplate(),
            consentGranted: false,
            localModelURL: llmURL
        )

        // Diarize: resolve ecapa-tdnn.mlpackage from bundle (CoreML Phase 2).
        // Empty URL → MFCC fallback inside voxema_ecapa_coreml.m (no crash, no config needed).
        let ecapaURL: URL = Bundle.main
            .url(forResource: "ecapa-tdnn", withExtension: "mlpackage")
            ?? URL(fileURLWithPath: "")
        let diarizeConfig = DiarizeConfiguration(modelURL: ecapaURL)

        return PipelineCoordinator(
            captureStage:    CaptureStage(config: captureConfig),
            transcribeStage: TranscribeStage(config: transcribeConfig),
            diarizeStage:    DiarizeStage(config: diarizeConfig, profilePersistence: profilePersistence),
            summarizeStage:  SummarizeStage(config: summarizeConfig),
            exportStage:     (try? ExportStage()) ?? ExportStage.failing
        )
    }

    /// Designated init — accepts injected dependencies (also used in tests).
    public init(coordinator: PipelineCoordinator, store: MeetingStore) {
        self.coordinator = coordinator
        self.store = store
        observeCoordinator()
        loadMeetings()
        cleanupExpiredAudio()
    }

    // MARK: - Recording

    /// Starts audio capture. No-op if already recording.
    ///
    /// No permission pre-flight here — CaptureStage checks SCK/AVFoundation internally
    /// and throws typed PipelineErrors on denial. Handling them here lets us surface
    /// targeted recovery UI (Settings deep-link + Restart) without a separate pre-check
    /// that may not reflect macOS 15's new TCC key.
    public func startRecording() async {
        pipelineError = nil
        permissionRequired = nil
        recordingDuration = 0

        // Pre-flight: verify the selected Whisper model file is on disk before
        // starting capture. Failing here is instant; failing after capture wastes
        // the entire recording session.
        let mm = ModelManager.shared
        let whisperModelId = AppPreferences.shared.whisperModelId
        if !whisperModelId.isEmpty,
           mm.manifest.models.contains(where: { $0.id == whisperModelId && $0.family == .whisper }) {
            let status = mm.statuses[whisperModelId] ?? .missing
            switch status {
            case .missing, .corrupt:
                pipelineError = .transcribeModelNotFound(modelName: whisperModelId)
                log.warning("startRecording blocked: whisper model not on disk")
                return
            default:
                break
            }
        }

        // Reset any terminal state (failed, complete, or cancelled) before starting.
        switch coordinator.state {
        case .failed, .complete, .cancelled:
            coordinator.reset()
        default:
            break
        }
        do {
            try await coordinator.startRecording()
            startTimer()
        } catch let e as PipelineError {
            // Explicit switch is more reliable than catch-pattern matching for enum cases
            switch e {
            case .captureSystemAudioPermissionDenied:
                permissionRequired = .systemAudioRecording
            case .captureMicrophonePermissionDenied:
                permissionRequired = .microphone
            default:
                pipelineError = e
            }
        } catch {
            log.error("startRecording unexpected error")
        }
    }

    /// Opens the System Settings pane for the specified permission.
    public func openPermissionSettings(for kind: PermissionRequired) {
        let urlString: String
        switch kind {
        case .systemAudioRecording:
            urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
        case .microphone:
            urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
        }
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }


    #if DEBUG
    /// Checks system audio recording permission status via AVFoundation.
    /// Called from Debug menu → Check Audio Permission (⇧⌘K).
    public func refreshSCKDiagnostics() async {
        sckDiagnostics = "checking…"
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        switch status {
        case .authorized:
            sckDiagnostics = "✅ audio authorized | bundle=\(Bundle.main.bundlePath)"
        case .denied:
            sckDiagnostics = "❌ audio denied | bundle=\(Bundle.main.bundlePath)"
        case .restricted:
            sckDiagnostics = "⚠️ audio restricted | bundle=\(Bundle.main.bundlePath)"
        case .notDetermined:
            sckDiagnostics = "⏳ audio not determined | bundle=\(Bundle.main.bundlePath)"
        @unknown default:
            sckDiagnostics = "? unknown status"
        }
    }
    #endif

    /// Cancels an active recording or processing run and returns to idle on next start.
    public func cancelProcessing() {
        coordinator.cancel()
        stopTimer()
        stopProcessingTimer()
    }

    /// Stops capture and triggers the processing pipeline.
    public func stopRecording() async {
        stopTimer()
        do {
            try await coordinator.stopRecording()
        } catch let e as PipelineError {
            pipelineError = e
        } catch {
            log.error("stopRecording unexpected error")
        }
    }

    // MARK: - Library

    /// Reloads all meetings from the database (or applies `searchQuery` if set).
    public func loadMeetings() {
        applySearch()
    }

    /// Renames the meeting with the given `id`.
    public func renameMeeting(id: UUID, title: String) {
        guard let existing = meetings.first(where: { $0.meetingId == id }) else { return }
        let renamed = Meeting(
            meetingId:       existing.meetingId,
            title:           title,
            recordedAt:      existing.recordedAt,
            durationSeconds: existing.durationSeconds,
            transcript:      existing.transcript,
            summary:         existing.summary,
            speakers:        existing.speakers,
            audioDeleted:    existing.audioDeleted,
            audioFilePaths:  existing.audioFilePaths,
            metadata:        existing.metadata
        )
        try? store.save(renamed)
        loadMeetings()
    }

    /// Deletes the meeting with the given `id` (hard delete — irreversible).
    /// Also deletes any retained audio files for that meeting.
    public func deleteMeeting(id: UUID) {
        if let meeting = meetings.first(where: { $0.meetingId == id }) {
            deleteAudioFiles(for: meeting)
        }
        try? store.delete(id: id)
        if selectedMeetingId == id { selectedMeetingId = nil }
        loadMeetings()
    }

    /// Deletes only the audio files for a meeting without removing the meeting record.
    public func deleteAudio(for meetingId: UUID) {
        guard let meeting = meetings.first(where: { $0.meetingId == meetingId }) else { return }
        deleteAudioFiles(for: meeting)
        let updated = Meeting(
            meetingId:       meeting.meetingId,
            title:           meeting.title,
            recordedAt:      meeting.recordedAt,
            durationSeconds: meeting.durationSeconds,
            transcript:      meeting.transcript,
            summary:         meeting.summary,
            speakers:        meeting.speakers,
            audioDeleted:    true,
            audioFilePaths:  [],
            metadata:        meeting.metadata
        )
        try? store.save(updated)
        loadMeetings()
    }

    /// Reruns the full processing pipeline on a meeting's retained audio files.
    /// No-op if audio has been deleted or the pipeline is currently active.
    public func reprocessMeeting(id: UUID) async {
        guard case .idle = pipelineState else {
            log.warning("reprocessMeeting: pipeline not idle")
            return
        }
        guard let meeting = meetings.first(where: { $0.meetingId == id }),
              !meeting.audioFilePaths.isEmpty,
              !meeting.audioDeleted else {
            log.warning("reprocessMeeting: no audio available for meeting", "\(id)")
            return
        }

        // Verify files exist on disk
        let existingPaths = meeting.audioFilePaths.filter {
            FileManager.default.fileExists(atPath: $0)
        }
        guard !existingPaths.isEmpty else {
            log.warning("reprocessMeeting: audio files missing from disk")
            // Mark as deleted so UI stops offering reprocess
            deleteAudio(for: id)
            return
        }

        // Reconstruct AudioStream objects from saved paths
        let streams: [AudioStream] = existingPaths.compactMap { path in
            let isRemote = path.contains("-remote")
            return AudioStream(
                streamId: UUID(),
                channel: isRemote ? .remote : .local,
                format: "PCM 16kHz mono",
                filePath: path,
                durationSeconds: meeting.durationSeconds,
                deviceName: isRemote ? "System Audio" : "Microphone",
                recordedAt: meeting.recordedAt
            )
        }

        log.info("reprocessMeeting: starting pipeline for meeting", "\(id)")
        coordinator.reset()
        pipelineError = nil

        // Delete old meeting record so export creates a fresh one
        try? store.delete(id: id)
        if selectedMeetingId == id { selectedMeetingId = nil }
        loadMeetings()

        // Run pipeline as background task (same as normal processing)
        coordinator.backgroundProcessingCount += 1
        Task { [weak self] in
            guard let self else { return }
            do {
                try await self.coordinator.runProcessingPipelinePublic(streams: streams)
            } catch {
                self.log.error("reprocessMeeting: pipeline failed")
            }
            self.coordinator.backgroundProcessingCount -= 1
        }
    }

    /// Total bytes used by all retained audio files across all meetings.
    public var audioStorageUsedBytes: Int64 {
        let audioDir = (FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? FileManager.default.temporaryDirectory)
            .appendingPathComponent("Voxema/Audio")
        guard let enumerator = FileManager.default.enumerator(
            at: audioDir,
            includingPropertiesForKeys: [.fileSizeKey],
            options: .skipsHiddenFiles
        ) else { return 0 }
        var total: Int64 = 0
        for case let url as URL in enumerator {
            if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                total += Int64(size)
            }
        }
        return total
    }

    /// Deletes audio files for meetings older than `audioRetentionDays` days.
    /// No-op when retention is -1 (keep forever) or 0 (managed by export stage).
    public func cleanupExpiredAudio() {
        let days = AppPreferences.shared.audioRetentionDays
        guard days > 0 else { return }
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        for meeting in meetings where !meeting.audioDeleted && !meeting.audioFilePaths.isEmpty {
            if meeting.recordedAt < cutoff {
                log.info("cleanupExpiredAudio: expiring audio for meeting older than retention threshold", "\(days) days")
                deleteAudio(for: meeting.meetingId)
            }
        }
    }

    /// Deletes all retained audio across all meetings immediately.
    public func deleteAllAudio() {
        for meeting in meetings where !meeting.audioDeleted && !meeting.audioFilePaths.isEmpty {
            deleteAudio(for: meeting.meetingId)
        }
    }

    private func deleteAudioFiles(for meeting: Meeting) {
        for path in meeting.audioFilePaths {
            try? FileManager.default.removeItem(atPath: path)
        }
        if !meeting.audioFilePaths.isEmpty {
            log.info("deleted audio files for meeting", "\(meeting.meetingId)")
        }
    }

    /// Returns the currently selected `Meeting`, if any.
    public var selectedMeeting: Meeting? {
        guard let id = selectedMeetingId else { return nil }
        return meetings.first { $0.meetingId == id }
    }

    // MARK: - Notifications

    /// Requests `UNUserNotificationCenter` authorization (called once on launch).
    public func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            Task { @MainActor in self.notificationsAuthorized = granted }
        }
    }

    // MARK: - Private

    private func observeCoordinator() {
        coordinatorSubscriptions.removeAll()

        coordinator.$state
            .receive(on: RunLoop.main)
            .sink { [weak self] state in
                self?.pipelineState = state
                switch state {
                case .processing:
                    self?.startProcessingTimer()
                case .complete(let id):
                    self?.stopProcessingTimer()
                    self?.stopTimer()
                    self?.loadMeetings()
                    self?.selectedMeetingId = id
                    self?.sendProcessingCompleteNotification(meetingId: id)
                case .failed(let err):
                    self?.stopProcessingTimer()
                    self?.stopTimer()
                    // Permission errors are routed to permissionRequired (targeted recovery UI).
                    // They must NOT also set pipelineError — that would show the generic
                    // "Recording Error" alert first and swallow the permission alert.
                    switch err {
                    case .captureSystemAudioPermissionDenied:
                        self?.permissionRequired = .systemAudioRecording
                    case .captureMicrophonePermissionDenied:
                        self?.permissionRequired = .microphone
                    default:
                        self?.pipelineError = err
                    }
                case .cancelled:
                    self?.stopProcessingTimer()
                default:
                    break
                }
            }
            .store(in: &coordinatorSubscriptions)

        coordinator.$progress
            .receive(on: RunLoop.main)
            .sink { [weak self] progress in
                self?.pipelineProgress = progress
            }
            .store(in: &coordinatorSubscriptions)

        coordinator.$backgroundProcessingCount
            .receive(on: RunLoop.main)
            .sink { [weak self] count in
                self?.backgroundProcessingCount = count
            }
            .store(in: &coordinatorSubscriptions)
    }

    /// Recreates the pipeline coordinator from the current `AppPreferences`.
    ///
    /// Call this after onboarding completes or when the user changes the active model
    /// in Settings. Safe to call only when `pipelineState == .idle`.
    public func refreshPipeline() {
        guard pipelineState == .idle else {
            log.warning("refreshPipeline called in non-idle state — ignored")
            return
        }
        coordinator = Self.makeCoordinator(profilePersistence: store)
        observeCoordinator()
        log.info("pipeline coordinator refreshed")
    }

    private func applySearch() {
        do {
            meetings = searchQuery.isEmpty
                ? try store.fetchAll()
                : try store.search(searchQuery)
        } catch {
            log.error("MeetingStore query failed")
            meetings = []
        }
    }

    private func startTimer() {
        timerTask?.cancel()
        timerTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                recordingDuration += 1
            }
        }
    }

    private func stopTimer() {
        timerTask?.cancel()
        timerTask = nil
    }

    private func startProcessingTimer() {
        processingElapsed = 0
        processingTimerTask?.cancel()
        processingTimerTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                processingElapsed += 1
            }
        }
    }

    private func stopProcessingTimer() {
        processingTimerTask?.cancel()
        processingTimerTask = nil
    }

    private func sendProcessingCompleteNotification(meetingId: UUID) {
        guard notificationsAuthorized else { return }
        let meeting = meetings.first { $0.meetingId == meetingId }
        let content = UNMutableNotificationContent()
        content.title = String(localized: "Meeting ready")
        let durationStr = Self.formatDuration(meeting?.durationSeconds ?? 0)
        let speakerCount = meeting?.speakers.count ?? 0
        let actionCount = meeting?.summary?.actionItems.count ?? 0
        content.body = [
            meeting?.title ?? String(localized: "New meeting"),
            durationStr,
            "\(speakerCount) speaker\(speakerCount == 1 ? "" : "s")",
            actionCount > 0 ? "\(actionCount) action item\(actionCount == 1 ? "" : "s")" : nil
        ].compactMap { $0 }.joined(separator: " · ")
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: "meeting-\(meetingId)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request) { _ in }
    }

    private static func formatDuration(_ s: Float) -> String {
        let m = Int(s) / 60; let sec = Int(s) % 60
        return sec == 0 ? "\(m) min" : "\(m)m \(sec)s"
    }
}

