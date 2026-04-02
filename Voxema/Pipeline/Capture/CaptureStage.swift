import Foundation

// MARK: - AudioCapturer

/// Internal abstraction for a single audio capture channel.
/// Enables constructor injection for testing (MockAudioCapturer).
protocol AudioCapturer: AnyObject {
    /// Starts capturing audio and writes PCM samples to `url`.
    func startCapture(to url: URL) async throws
    /// Stops capture and returns the duration of audio written in seconds.
    func stopCapture() async throws -> TimeInterval
    /// Cancels capture immediately; partial data at `url` should be discarded.
    func cancel()
}

// MARK: - CaptureConfiguration

/// Configures the Capture stage: temp directory, encryption key, and optional mic device.
public struct CaptureConfiguration: Sendable {
    /// Directory where temporary (pre-encryption) WAV files are written.
    public let tempDirectory: URL
    /// Keychain identifier used by `EncryptionManager` to encrypt audio at rest.
    public let encryptionKeyId: String
    /// Specific microphone device UID; `nil` selects the system default.
    public let microphoneDeviceUID: String?

    /// Default configuration using the system temp directory.
    public static let `default` = CaptureConfiguration(
        tempDirectory: (FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? FileManager.default.temporaryDirectory)
            .appendingPathComponent("Voxema/Audio", isDirectory: true),
        encryptionKeyId: "com.voxema.app.capture-audio-key",
        microphoneDeviceUID: nil
    )

    public init(
        tempDirectory: URL,
        encryptionKeyId: String,
        microphoneDeviceUID: String? = nil
    ) {
        self.tempDirectory = tempDirectory
        self.encryptionKeyId = encryptionKeyId
        self.microphoneDeviceUID = microphoneDeviceUID
    }
}

// MARK: - CaptureStage

/// Orchestrates system audio (Core Audio tap) and microphone (AVAudioEngine) capture.
///
/// Produces exactly two `AudioStream` objects — `.remote` (system audio) and `.local`
/// (microphone) — with temporary WAV files encrypted at rest by `EncryptionManager`.
/// All plaintext audio is deleted immediately after encryption.
public final class CaptureStage: CaptureStageProtocol {

    private let systemAudio: any AudioCapturer
    private let microphone: any AudioCapturer
    private let config: CaptureConfiguration
    private let log = VoxemaLogger.make(category: "capture.stage")

    // State held during an active recording
    private var activeRecordingId: UUID?
    private var systemAudioURL: URL?
    private var microphoneURL: URL?
    private var recordingStartTime: Date?

    // MARK: - Init

    /// Production initialiser uses Core Audio tap (system audio) + AVAudioEngine (microphone).
    public convenience init(config: CaptureConfiguration = .default) {
        self.init(
            systemAudio: SystemAudioCapture(),
            microphone: MicrophoneCapture(),
            config: config
        )
    }

    /// Injectable initialiser for tests.
    init(
        systemAudio: any AudioCapturer,
        microphone: any AudioCapturer,
        config: CaptureConfiguration = .default
    ) {
        self.systemAudio = systemAudio
        self.microphone = microphone
        self.config = config
    }

    // MARK: - CaptureStageProtocol

    public func startCapture() async throws {
        let id = UUID()
        let sysURL = config.tempDirectory
            .appendingPathComponent("\(id)-remote.wav")
        let micURL = config.tempDirectory
            .appendingPathComponent("\(id)-local.wav")

        try FileManager.default.createDirectory(
            at: config.tempDirectory,
            withIntermediateDirectories: true
        )

        do {
            // Start both channels concurrently; cancel both on any failure
            async let sysStart: Void = systemAudio.startCapture(to: sysURL)
            async let micStart: Void = microphone.startCapture(to: micURL)
            try await sysStart
            try await micStart
        } catch {
            systemAudio.cancel()
            microphone.cancel()
            cleanupTempFiles(sysURL: sysURL, micURL: micURL)
            throw error
        }

        activeRecordingId = id
        systemAudioURL = sysURL
        microphoneURL = micURL
        recordingStartTime = Date()
        log.info("CaptureStage started")
    }

    public func stopCapture() async throws -> [AudioStream] {
        guard
            activeRecordingId != nil,
            let sysURL = systemAudioURL,
            let micURL = microphoneURL
        else {
            log.error("stopCapture called while not recording")
            throw PipelineError.captureDiskSpaceInsufficient
        }

        let capturedAt = recordingStartTime ?? Date()
        clearState()

        // Stop both channels concurrently
        async let sysDuration: TimeInterval = systemAudio.stopCapture()
        async let micDuration: TimeInterval = microphone.stopCapture()
        let (remoteSecs, localSecs) = try await (sysDuration, micDuration)

        // Encrypt & delete plaintext files on a plain GCD thread — same reason as
        // transcription: DispatchQueue.global() is entirely outside Swift's actor
        // system, so no @MainActor inference can hop the work back to the main thread.
        let keyId = config.encryptionKeyId
        let (encSysURL, encMicURL): (URL, URL) = try await withCheckedThrowingContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let encSys = try CaptureStage.encryptAndDeletePlaintext(at: sysURL, keyId: keyId)
                    let encMic = try CaptureStage.encryptAndDeletePlaintext(at: micURL, keyId: keyId)
                    cont.resume(returning: (encSys, encMic))
                } catch {
                    cont.resume(throwing: error)
                }
            }
        }

        log.info("CaptureStage stopped")

        return [
            AudioStream(
                streamId: UUID(),
                channel: .remote,
                format: "PCM 16kHz mono",
                filePath: encSysURL.path,
                durationSeconds: Float(remoteSecs),
                deviceName: "System Audio",
                recordedAt: capturedAt
            ),
            AudioStream(
                streamId: UUID(),
                channel: .local,
                format: "PCM 16kHz mono",
                filePath: encMicURL.path,
                durationSeconds: Float(localSecs),
                deviceName: "Microphone",
                recordedAt: capturedAt
            ),
        ]
    }

    public func cancel() {
        systemAudio.cancel()
        microphone.cancel()
        // Delete plaintext temp files immediately — no audio should persist unencrypted
        if let sysURL = systemAudioURL { try? FileManager.default.removeItem(at: sysURL) }
        if let micURL = microphoneURL  { try? FileManager.default.removeItem(at: micURL) }
        clearState()
        log.info("CaptureStage cancelled")
    }

    // MARK: - Private helpers

    private func clearState() {
        activeRecordingId = nil
        systemAudioURL = nil
        microphoneURL = nil
        recordingStartTime = nil
    }

    private func cleanupTempFiles(sysURL: URL, micURL: URL) {
        try? FileManager.default.removeItem(at: sysURL)
        try? FileManager.default.removeItem(at: micURL)
    }

    /// Encrypts the plaintext file at `url`, writes `.enc` beside it, then deletes the original.
    /// Static so it can be captured by Task.detached without capturing self.
    private static func encryptAndDeletePlaintext(at url: URL, keyId: String) throws -> URL {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw PipelineError.captureDiskSpaceInsufficient
        }
        let plaintext = try Data(contentsOf: url, options: .mappedIfSafe)
        let encrypted = try EncryptionManager.encrypt(plaintext, keyIdentifier: keyId)
        let encURL = url.deletingPathExtension().appendingPathExtension("enc")
        try encrypted.write(to: encURL, options: .atomic)
        try FileManager.default.removeItem(at: url)
        return encURL
    }
}
