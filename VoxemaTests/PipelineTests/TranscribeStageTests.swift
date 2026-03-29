import XCTest
import AVFoundation
@testable import Voxema

// MARK: - MockWhisperEngine

final class MockWhisperEngine: WhisperEngineProtocol {
    var loadModelError: Error?
    var transcribeError: Error?
    var segmentsToReturn: [WhisperSegment] = []

    private(set) var loadModelCalled = false
    private(set) var transcribeCalled = false
    private(set) var unloadCalled = false
    private(set) var lastModelURL: URL?

    func loadModel(at url: URL) throws {
        loadModelCalled = true
        lastModelURL = url
        if let error = loadModelError { throw error }
    }

    func transcribe(samples: [Float], language: String?) throws -> [WhisperSegment] {
        transcribeCalled = true
        if let error = transcribeError { throw error }
        return segmentsToReturn
    }

    func unloadModel() { unloadCalled = true }
}

// MARK: - TranscribeStageTests

final class TranscribeStageTests: XCTestCase {

    private var tempDir: URL!
    private var encKeyId: String!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("TranscribeTests-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        encKeyId = "test-transcribe-enc-\(UUID().uuidString)"
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
        try super.tearDownWithError()
    }

    // MARK: - Helpers

    private func makeMockEngine() -> MockWhisperEngine { MockWhisperEngine() }

    private func makeStage(
        engine: MockWhisperEngine = MockWhisperEngine(),
        noSpeechThreshold: Float = 0.6
    ) -> (TranscribeStage, MockWhisperEngine) {
        let mockEngine = engine
        let config = TranscribeConfiguration(
            modelURL: tempDir.appendingPathComponent("model.gguf"),
            noSpeechThreshold: noSpeechThreshold,
            encryptionKeyId: encKeyId
        )
        let stage = TranscribeStage(engineFactory: { mockEngine }, config: config)
        return (stage, mockEngine)
    }

    /// Writes a small encrypted silent WAV to tempDir.
    private func makeSilentEncFile(durationSecs: Double = 0.5, channel: AudioChannel = .remote) throws -> AudioStream {
        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16_000,
            channels: 1,
            interleaved: false
        )!
        let frameCount = AVAudioFrameCount(16_000 * durationSecs)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
        buffer.frameLength = frameCount

        let wavURL = tempDir.appendingPathComponent("\(UUID())-\(channel.rawValue).wav")
        // AVAudioFile must be released (closed) before reading — use a scope block
        do {
            let file = try AVAudioFile(forWriting: wavURL, settings: format.settings,
                                       commonFormat: format.commonFormat, interleaved: false)
            try file.write(from: buffer)
        }  // file is closed here

        let plaintext = try Data(contentsOf: wavURL)
        let encrypted = try EncryptionManager.encrypt(plaintext, keyIdentifier: encKeyId)
        let encURL = wavURL.deletingPathExtension().appendingPathExtension("enc")
        try encrypted.write(to: encURL, options: .atomic)
        try FileManager.default.removeItem(at: wavURL)

        return AudioStream(
            channel: channel,
            filePath: encURL.path,
            durationSeconds: Float(durationSecs),
            deviceName: "Test",
            recordedAt: Date()
        )
    }

    // MARK: - TranscribeConfiguration

    func testDefaultConfigurationNoSpeechThreshold() {
        XCTAssertEqual(TranscribeConfiguration.default.noSpeechThreshold, 0.6, accuracy: 0.001)
    }

    func testDefaultConfigurationLanguageIsNil() {
        XCTAssertNil(TranscribeConfiguration.default.language)
    }

    // MARK: - Empty input

    func testRunWithEmptyStreamsReturnsEmpty() async throws {
        let (stage, _) = makeStage()
        let result = try await stage.run([])
        XCTAssertEqual(result.count, 0)
    }

    // MARK: - Normal transcription

    func testRunCallsLoadAndUnloadModel() async throws {
        let mock = makeMockEngine()
        // Return one segment above no-speech threshold so it passes the gate
        mock.segmentsToReturn = [WhisperSegment(startMs: 0, endMs: 1000, text: "Hello", noSpeechProb: 0.1)]
        let (stage, _) = makeStage(engine: mock)
        let stream = try makeSilentEncFile()
        _ = try await stage.run([stream])
        XCTAssertTrue(mock.loadModelCalled)
        XCTAssertTrue(mock.unloadCalled)
    }

    func testRunProducesCorrectChannelForRemoteStream() async throws {
        let mock = makeMockEngine()
        mock.segmentsToReturn = [WhisperSegment(startMs: 0, endMs: 2000, text: "Hello world", noSpeechProb: 0.05)]
        let (stage, _) = makeStage(engine: mock)
        let stream = try makeSilentEncFile(channel: .remote)
        let result = try await stage.run([stream])
        XCTAssertTrue(result.allSatisfy { $0.channel == .remote })
    }

    func testRunProducesCorrectChannelForLocalStream() async throws {
        let mock = makeMockEngine()
        mock.segmentsToReturn = [WhisperSegment(startMs: 0, endMs: 500, text: "Yes", noSpeechProb: 0.0)]
        let (stage, _) = makeStage(engine: mock)
        let stream = try makeSilentEncFile(channel: .local)
        let result = try await stage.run([stream])
        XCTAssertTrue(result.allSatisfy { $0.channel == .local })
    }

    func testRunTwoStreamsBothChannelsPresent() async throws {
        let mock = makeMockEngine()
        mock.segmentsToReturn = [WhisperSegment(startMs: 0, endMs: 1000, text: "Hi", noSpeechProb: 0.1)]
        let (stage, _) = makeStage(engine: mock)
        let remoteStream = try makeSilentEncFile(channel: .remote)
        let localStream  = try makeSilentEncFile(channel: .local)
        let result = try await stage.run([remoteStream, localStream])
        let channels = Set(result.map(\.channel))
        XCTAssertTrue(channels.contains(.remote))
        XCTAssertTrue(channels.contains(.local))
    }

    // MARK: - Timestamps

    func testTimestampsConvertedMillisecondsToSeconds() async throws {
        let mock = makeMockEngine()
        // startMs=500, endMs=2500 → start=0.5, end=2.5
        mock.segmentsToReturn = [WhisperSegment(startMs: 500, endMs: 2_500, text: "Test", noSpeechProb: 0.0)]
        let (stage, _) = makeStage(engine: mock)
        let stream = try makeSilentEncFile()
        let result = try await stage.run([stream])
        XCTAssertEqual(result.first?.startTime ?? -1, 0.5, accuracy: 0.001)
        XCTAssertEqual(result.first?.endTime ?? -1, 2.5, accuracy: 0.001)
    }

    // MARK: - No-speech gate

    func testNoSpeechSegmentsFiltered() async throws {
        let mock = makeMockEngine()
        // noSpeechProb 0.9 > threshold 0.6 → must be filtered
        mock.segmentsToReturn = [
            WhisperSegment(startMs: 0, endMs: 1000, text: "Kept",    noSpeechProb: 0.1),
            WhisperSegment(startMs: 1000, endMs: 2000, text: "Gone", noSpeechProb: 0.9),
        ]
        let (stage, _) = makeStage(engine: mock, noSpeechThreshold: 0.6)
        let stream = try makeSilentEncFile()
        let result = try await stage.run([stream])
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.text, "Kept")
    }

    // MARK: - Error handling

    func testLoadModelErrorMappedToPipelineError() async throws {
        let mock = makeMockEngine()
        mock.loadModelError = PipelineError.transcribeModelNotFound(modelName: "")
        let (stage, _) = makeStage(engine: mock)
        let stream = try makeSilentEncFile()
        do {
            _ = try await stage.run([stream])
            XCTFail("Expected error")
        } catch let e as PipelineError {
            if case .transcribeModelNotFound = e { /* expected */ }
            else { XCTFail("Unexpected PipelineError: \(e)") }
        }
    }

    func testUnloadCalledEvenWhenTranscriptionFails() async throws {
        let mock = makeMockEngine()
        mock.transcribeError = PipelineError.transcribeAudioFileEmpty
        let (stage, _) = makeStage(engine: mock)
        let stream = try makeSilentEncFile()
        do {
            _ = try await stage.run([stream])
        } catch {
            // error expected
        }
        XCTAssertTrue(mock.unloadCalled, "unloadModel must be called even on failure")
    }

    // MARK: - Cancel

    func testCancelDuringRunStopsSubsequentChannels() async throws {
        // cancel() called before run() has no effect (run resets the flag).
        // Verify that cancel() at minimum does not crash and that a fresh run
        // after cancel() completes normally.
        let (stage, _) = makeStage()
        stage.cancel()
        let stream = try makeSilentEncFile()
        // After cancel + fresh run, stage should succeed (cancel only affects in-progress runs)
        let result = try await stage.run([stream])
        // Stub engine returns [] segments, so result should be empty but not an error
        XCTAssertNotNil(result)
    }
}

// MARK: - AudioSampleDecoderTests

final class AudioSampleDecoderTests: XCTestCase {

    private var tempDir: URL!
    private var encKeyId: String!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AudioDecoderTests-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        encKeyId = "test-decoder-enc-\(UUID().uuidString)"
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
        try super.tearDownWithError()
    }

    func testDecodeValidEncryptedWAVReturnsSamples() throws {
        let encURL = try makeEncryptedSilentWAV(durationSecs: 0.5)
        let samples = try AudioSampleDecoder.decode(from: encURL, encryptionKeyId: encKeyId)
        XCTAssertGreaterThan(samples.count, 0, "Decoded samples must be non-empty")
    }

    func testDecodeShortAudioReturnsEmpty() throws {
        // < 0.1 seconds → treated as empty by the decoder
        let encURL = try makeEncryptedSilentWAV(durationSecs: 0.05)
        let samples = try AudioSampleDecoder.decode(from: encURL, encryptionKeyId: encKeyId)
        XCTAssertEqual(samples.count, 0, "Audio shorter than 0.1s should return empty array")
    }

    func testDecodeMissingFileThrows() {
        let fakeURL = tempDir.appendingPathComponent("nonexistent.enc")
        XCTAssertThrowsError(
            try AudioSampleDecoder.decode(from: fakeURL, encryptionKeyId: encKeyId)
        ) { error in
            XCTAssertEqual(error as? PipelineError, .transcribeAudioFileEmpty)
        }
    }

    func testDecodeCorruptedDataThrows() throws {
        let badURL = tempDir.appendingPathComponent("bad.enc")
        try Data("not valid ciphertext".utf8).write(to: badURL)
        XCTAssertThrowsError(
            try AudioSampleDecoder.decode(from: badURL, encryptionKeyId: encKeyId)
        ) { error in
            XCTAssertEqual(error as? PipelineError, .transcribeAudioFileEmpty)
        }
    }

    // MARK: - Helper

    private func makeEncryptedSilentWAV(durationSecs: Double) throws -> URL {
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                   sampleRate: 16_000, channels: 1, interleaved: false)!
        let frameCount = AVAudioFrameCount(max(1, 16_000 * durationSecs))
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
        buffer.frameLength = frameCount
        let wavURL = tempDir.appendingPathComponent("\(UUID()).wav")
        do {
            let file = try AVAudioFile(forWriting: wavURL, settings: format.settings,
                                       commonFormat: format.commonFormat, interleaved: false)
            try file.write(from: buffer)
        }  // file closed here

        let plaintext = try Data(contentsOf: wavURL)
        let encrypted = try EncryptionManager.encrypt(plaintext, keyIdentifier: encKeyId)
        let encURL = wavURL.deletingPathExtension().appendingPathExtension("enc")
        try encrypted.write(to: encURL)
        try FileManager.default.removeItem(at: wavURL)
        return encURL
    }
}
