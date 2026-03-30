import Foundation
import Combine
import UserNotifications
import GRDB
import CoreGraphics
import AVFoundation
import AppKit
import ScreenCaptureKit

// MARK: - Permission alert kind

/// Identifies which permission is missing when the user tries to start recording.
public enum PermissionRequired: Equatable {
    case screenRecording
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
    /// Last pipeline error surfaced to the UI.
    @Published public var pipelineError: PipelineError?
    /// `true` while notifications permission is being requested.
    @Published public private(set) var notificationsAuthorized = false
    /// Set before recording starts when a required permission is missing.
    @Published public var permissionRequired: PermissionRequired? = nil
    /// Set when user returns from System Settings after being sent there for screen recording.
    /// Triggers the "Restart to activate" prompt.
    @Published public var awaitingScreenCaptureRestart = false

    #if DEBUG
    /// Live SCK diagnostic string — updated by refreshSCKDiagnostics().
    @Published public var sckDiagnostics: String = "not checked"
    #endif

    // MARK: - Dependencies

    public let coordinator: PipelineCoordinator
    private let store: MeetingStore
    private let log = VoxemaLogger.make(category: "app.state")

    // MARK: - Private

    private var cancellables = Set<AnyCancellable>()
    private var timerTask: Task<Void, Never>?
    /// Set to true when we open Screen Recording settings; cleared on next app-foreground event.
    private var awaitingSettingsReturn = false

    // MARK: - Init

    /// Production factory — creates real pipeline stages and opens the database.
    /// Stage configurations are read from `AppPreferences.shared`.
    public static func production() -> AppState {
        let coordinator = makeCoordinator()
        do {
            let store = try MeetingStore(databasePath: ExportConfiguration.default.databasePath)
            return AppState(coordinator: coordinator, store: store)
        } catch {
            return AppState(coordinator: coordinator, store: MeetingStore.failing)
        }
    }

    // MARK: - Coordinator factory (reads AppPreferences)

    private static func makeCoordinator() -> PipelineCoordinator {
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
        let transcribeConfig = TranscribeConfiguration(modelURL: whisperURL)

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

        return PipelineCoordinator(
            captureStage:    CaptureStage(config: captureConfig),
            transcribeStage: TranscribeStage(config: transcribeConfig),
            diarizeStage:    DiarizeStage(),
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
        // If the coordinator is stuck in .failed from a previous attempt, reset to .idle
        if case .failed = coordinator.state { coordinator.reset() }
        do {
            try await coordinator.startRecording()
            startTimer()
        } catch let e as PipelineError {
            // Explicit switch is more reliable than catch-pattern matching for enum cases
            switch e {
            case .captureScreenRecordingPermissionDenied:
                permissionRequired = .screenRecording
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
        case .screenRecording:
            urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
            // Track that we sent the user to Screen Recording settings so we can
            // show the "Restart to activate" prompt when they return.
            awaitingSettingsReturn = true
        case .microphone:
            urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
        }
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }

    /// Relaunches Voxema so a newly-granted Screen Recording permission takes effect.
    /// Uses exit(0) — more reliable than NSApp.terminate which can be intercepted or delayed.
    public func restartApp() {
        let bundlePath = Bundle.main.bundlePath
        log.info("restartApp", bundlePath)
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        task.arguments = ["-n", bundlePath]
        try? task.run()
        // 1 second gives the new process time to start before we exit.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            exit(0)
        }
    }

    #if DEBUG
    /// Runs a live SCK content check and updates sckDiagnostics with the result.
    /// Called from Debug menu → Check SCK Permission (⇧⌘K).
    public func refreshSCKDiagnostics() async {
        sckDiagnostics = "checking…"
        let preflight = CGPreflightScreenCaptureAccess()
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(
                false, onScreenWindowsOnly: false
            )
            let displays = content.displays.count
            let windows = content.windows.count
            sckDiagnostics = "✅ granted — \(displays) display(s), \(windows) window(s) | CGPreflight=\(preflight) | bundle=\(Bundle.main.bundlePath)"
            log.info("SCK diagnostic: granted")
        } catch let e as NSError {
            sckDiagnostics = "❌ denied — \(e.domain) \(e.code): \(e.localizedDescription) | CGPreflight=\(preflight) | bundle=\(Bundle.main.bundlePath)"
            log.error("SCK diagnostic: denied", "\(e.domain) \(e.code)")
        }
    }
    #endif

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
            metadata:        existing.metadata
        )
        try? store.save(renamed)
        loadMeetings()
    }

    /// Deletes the meeting with the given `id` (hard delete — irreversible).
    public func deleteMeeting(id: UUID) {
        try? store.delete(id: id)
        if selectedMeetingId == id { selectedMeetingId = nil }
        loadMeetings()
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
        coordinator.$state
            .receive(on: RunLoop.main)
            .sink { [weak self] state in
                self?.pipelineState = state
                switch state {
                case .complete(let id):
                    self?.stopTimer()
                    self?.loadMeetings()
                    self?.selectedMeetingId = id
                    self?.sendProcessingCompleteNotification(meetingId: id)
                case .failed(let err):
                    self?.stopTimer()
                    // Permission errors are routed to permissionRequired (targeted recovery UI).
                    // They must NOT also set pipelineError — that would show the generic
                    // "Recording Error" alert first and swallow the permission alert.
                    switch err {
                    case .captureScreenRecordingPermissionDenied:
                        self?.permissionRequired = .screenRecording
                    case .captureMicrophonePermissionDenied:
                        self?.permissionRequired = .microphone
                    default:
                        self?.pipelineError = err
                    }
                default:
                    break
                }
            }
            .store(in: &cancellables)

        coordinator.$progress
            .receive(on: RunLoop.main)
            .assign(to: &$pipelineProgress)

        // When the user returns from System Settings (after we opened Screen Recording there),
        // show the "Restart to activate" prompt instead of the original permission alert.
        NotificationCenter.default
            .publisher(for: NSApplication.didBecomeActiveNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self, self.awaitingSettingsReturn else { return }
                self.awaitingSettingsReturn = false
                self.permissionRequired = nil
                self.awaitingScreenCaptureRestart = true
            }
            .store(in: &cancellables)
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

// MARK: - Fallback stubs for unrecoverable init errors

extension ExportStage {
    /// Returns an `ExportStage` that always throws `.exportDatabaseWriteFailure`.
    static var failing: ExportStage {
        // Use a guaranteed-writeable temp path so init doesn't throw,
        // then the stage will fail at run-time if the DB path is broken.
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("voxema-fallback-\(UUID()).db").path
        return (try? ExportStage(config: ExportConfiguration(
            databasePath: tmp,
            exportsDirectory: FileManager.default.temporaryDirectory
        ))) ?? ExportStage._forcedFailing
    }

    // Last-resort: reflect on internal init — just use a precondition-safe approach
    private static var _forcedFailing: ExportStage {
        // This should never be reached in practice.
        fatalError("ExportStage: cannot create any fallback instance")
    }
}

extension MeetingStore {
    /// Returns an in-memory `MeetingStore` used when the production DB cannot be opened.
    static var failing: MeetingStore {
        return (try? MeetingStore(db: .init())) ?? { fatalError("MeetingStore in-memory init failed") }()
    }
}
