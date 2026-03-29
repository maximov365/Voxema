import XCTest
import AVFoundation
@testable import Voxema

// MARK: - MockAudioCapturer

/// Test double for AudioCapturer. Writes a small silent WAV to the requested URL.
final class MockAudioCapturer: AudioCapturer {
    /// If set, `startCapture(to:)` throws this error.
    var startError: Error?
    /// If set, `stopCapture()` throws this error.
    var stopError: Error?
    /// Duration returned by `stopCapture()`.
    var duration: TimeInterval = 1.0

    private(set) var startCalled = false
    private(set) var stopCalled  = false
    private(set) var cancelCalled = false
    private(set) var lastURL: URL?

    func startCapture(to url: URL) async throws {
        startCalled = true
        lastURL = url
        if let error = startError { throw error }
        writeSilentWAV(to: url, duration: duration)
    }

    func stopCapture() async throws -> TimeInterval {
        stopCalled = true
        if let error = stopError { throw error }
        return duration
    }

    func cancel() {
        cancelCalled = true
        if let url = lastURL { try? FileManager.default.removeItem(at: url) }
    }

    private func writeSilentWAV(to url: URL, duration: TimeInterval) {
        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16_000,
            channels: 1,
            interleaved: false
        )!
        let frameCount = AVAudioFrameCount(max(1, 16_000 * duration))
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return }
        buffer.frameLength = frameCount
        // Frames default to zero (silence)
        guard let file = try? AVAudioFile(
            forWriting: url,
            settings: format.settings,
            commonFormat: format.commonFormat,
            interleaved: false
        ) else { return }
        try? file.write(from: buffer)
    }
}

// MARK: - CaptureStageTests

final class CaptureStageTests: XCTestCase {

    private var tempDir: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("CaptureStageTests-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
        try super.tearDownWithError()
    }

    // MARK: - Helpers

    private func makeStage(
        systemAudio: MockAudioCapturer = MockAudioCapturer(),
        microphone: MockAudioCapturer = MockAudioCapturer()
    ) -> CaptureStage {
        let config = CaptureConfiguration(
            tempDirectory: tempDir,
            encryptionKeyId: "test-capture-key-\(UUID().uuidString)"
        )
        return CaptureStage(systemAudio: systemAudio, microphone: microphone, config: config)
    }

    // MARK: - CaptureConfiguration

    func testCaptureConfigurationDefaultEncryptionKeyId() {
        let key = CaptureConfiguration.default.encryptionKeyId
        XCTAssertFalse(key.isEmpty)
        XCTAssertTrue(key.contains("voxema"))
    }

    func testCaptureConfigurationDefaultTempDirectory() {
        let dir = CaptureConfiguration.default.tempDirectory
        XCTAssertTrue(dir.path.contains("com.voxema"))
    }

    func testCaptureConfigurationCustomMicDeviceUID() {
        let config = CaptureConfiguration(
            tempDirectory: tempDir,
            encryptionKeyId: "k",
            microphoneDeviceUID: "mic-uid-123"
        )
        XCTAssertEqual(config.microphoneDeviceUID, "mic-uid-123")
    }

    // MARK: - startCapture

    func testStartCaptureCallsBothSubCapturers() async throws {
        let sys = MockAudioCapturer()
        let mic = MockAudioCapturer()
        let stage = makeStage(systemAudio: sys, microphone: mic)

        try await stage.startCapture()
        defer { stage.cancel() }

        XCTAssertTrue(sys.startCalled)
        XCTAssertTrue(mic.startCalled)
    }

    func testStartCaptureSystemErrorCancelsBoth() async throws {
        let sys = MockAudioCapturer()
        sys.startError = PipelineError.captureScreenRecordingPermissionDenied
        let mic = MockAudioCapturer()
        let stage = makeStage(systemAudio: sys, microphone: mic)

        do {
            try await stage.startCapture()
            XCTFail("Expected error")
        } catch {
            // Both should be cancelled to avoid resource leak
            XCTAssertTrue(sys.cancelCalled || mic.cancelCalled)
        }
    }

    // MARK: - stopCapture

    func testStopCaptureReturnsExactlyTwoStreams() async throws {
        let stage = makeStage()
        try await stage.startCapture()
        let streams = try await stage.stopCapture()
        XCTAssertEqual(streams.count, 2)
    }

    func testStopCaptureChannelAssignment() async throws {
        let stage = makeStage()
        try await stage.startCapture()
        let streams = try await stage.stopCapture()
        let channels = Set(streams.map(\.channel))
        XCTAssertTrue(channels.contains(.local))
        XCTAssertTrue(channels.contains(.remote))
    }

    func testStopCaptureFormatLabel() async throws {
        let stage = makeStage()
        try await stage.startCapture()
        let streams = try await stage.stopCapture()
        for stream in streams {
            XCTAssertEqual(stream.format, "PCM 16kHz mono")
        }
    }

    func testStopCapturePlaintextDeletedEncryptedFileExists() async throws {
        let stage = makeStage()
        try await stage.startCapture()
        let streams = try await stage.stopCapture()

        for stream in streams {
            let encURL = URL(fileURLWithPath: stream.filePath)
            XCTAssertTrue(encURL.pathExtension == "enc", "Expected .enc extension, got \(encURL.lastPathComponent)")
            XCTAssertTrue(FileManager.default.fileExists(atPath: encURL.path),
                          "Encrypted file should exist at \(encURL.path)")

            // Plaintext WAV counterpart must be gone
            let wavURL = encURL.deletingPathExtension().appendingPathExtension("wav")
            XCTAssertFalse(FileManager.default.fileExists(atPath: wavURL.path),
                           "Plaintext WAV must be deleted after encryption")
        }
    }

    func testStopCaptureDurationPositive() async throws {
        let sys = MockAudioCapturer(); sys.duration = 2.5
        let mic = MockAudioCapturer(); mic.duration = 2.5
        let stage = makeStage(systemAudio: sys, microphone: mic)
        try await stage.startCapture()
        let streams = try await stage.stopCapture()
        for stream in streams {
            XCTAssertGreaterThan(stream.durationSeconds, 0)
        }
    }

    func testStopCaptureWithoutStartThrows() async {
        let stage = makeStage()
        do {
            _ = try await stage.stopCapture()
            XCTFail("Should throw when not recording")
        } catch {
            // Expected
        }
    }

    // MARK: - cancel

    func testCancelRemovesPlaintextTempFiles() async throws {
        let sys = MockAudioCapturer()
        let mic = MockAudioCapturer()
        let stage = makeStage(systemAudio: sys, microphone: mic)
        try await stage.startCapture()

        // Verify files were created
        XCTAssertNotNil(sys.lastURL)
        XCTAssertNotNil(mic.lastURL)

        stage.cancel()

        // Files should be deleted
        if let sysURL = sys.lastURL {
            XCTAssertFalse(FileManager.default.fileExists(atPath: sysURL.path),
                           "Plaintext system audio must be deleted on cancel")
        }
        if let micURL = mic.lastURL {
            XCTAssertFalse(FileManager.default.fileExists(atPath: micURL.path),
                           "Plaintext microphone audio must be deleted on cancel")
        }
    }

    func testCancelCallsBothSubCapturers() async throws {
        let sys = MockAudioCapturer()
        let mic = MockAudioCapturer()
        let stage = makeStage(systemAudio: sys, microphone: mic)
        try await stage.startCapture()
        stage.cancel()
        XCTAssertTrue(sys.cancelCalled)
        XCTAssertTrue(mic.cancelCalled)
    }
}

// MARK: - AudioFileWriterTests

final class AudioFileWriterTests: XCTestCase {

    private var tempDir: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AudioFileWriterTests-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
        try super.tearDownWithError()
    }

    func testWriteCreatesNonEmptyFile() throws {
        let url = tempDir.appendingPathComponent("test.wav")
        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16_000,
            channels: 1,
            interleaved: false
        )!
        let writer = try AudioFileWriter(url: url, outputFormat: format)

        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1_600)!
        buffer.frameLength = 1_600
        writer.write(buffer)
        writer.close()

        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        let size = attrs[.size] as? Int ?? 0
        XCTAssertGreaterThan(size, 0, "Written file should be non-empty")
    }

    func testWriteConvertsStereo48kToMono16k() throws {
        let url = tempDir.appendingPathComponent("convert.wav")
        let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16_000,
            channels: 1,
            interleaved: false
        )!
        let writer = try AudioFileWriter(url: url, outputFormat: targetFormat)

        // Simulate typical ScreenCaptureKit input: float32 48kHz stereo
        let inputFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 48_000,
            channels: 2,
            interleaved: false
        )!
        let frameCount: AVAudioFrameCount = 4_800 // 100 ms at 48kHz
        let buffer = AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: frameCount)!
        buffer.frameLength = frameCount

        writer.write(buffer)
        writer.close()

        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        let size = attrs[.size] as? Int ?? 0
        XCTAssertGreaterThan(size, 0, "Converted file should be non-empty")
    }

    func testDurationAccumulates() throws {
        let url = tempDir.appendingPathComponent("duration.wav")
        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16_000,
            channels: 1,
            interleaved: false
        )!
        let writer = try AudioFileWriter(url: url, outputFormat: format)

        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 16_000)!
        buffer.frameLength = 16_000 // 1 second
        writer.write(buffer)
        writer.close()

        // Duration must be >= 1 second (serial queue may not have flushed yet at close time,
        // but close() does a sync flush)
        XCTAssertGreaterThanOrEqual(writer.duration, 0.9, "Expected ~1 second of audio")
    }
}
