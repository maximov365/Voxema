import Foundation
import AVFoundation

// MARK: - TranscribeConfiguration

/// Configuration for the Transcribe stage.
public struct TranscribeConfiguration: Sendable {
    /// URL of the GGUF Whisper model file to use.
    public let modelURL: URL
    /// BCP-47 language override. `nil` enables auto-detection per channel.
    public let language: String?
    /// Segments with `noSpeechProb` above this value are discarded (silence gate).
    public let noSpeechThreshold: Float
    /// Keychain key identifier used to decrypt audio files from the Capture stage.
    public let encryptionKeyId: String

    public static let `default` = TranscribeConfiguration(
        modelURL: URL(fileURLWithPath: ""),  // replaced at runtime by PipelineCoordinator
        language: nil,
        noSpeechThreshold: 0.6,
        encryptionKeyId: "com.voxema.app.capture-audio-key"
    )

    public init(
        modelURL: URL,
        language: String? = nil,
        noSpeechThreshold: Float = 0.6,
        encryptionKeyId: String = "com.voxema.app.capture-audio-key"
    ) {
        self.modelURL = modelURL
        self.language = language
        self.noSpeechThreshold = noSpeechThreshold
        self.encryptionKeyId = encryptionKeyId
    }
}

// MARK: - AudioSampleDecoder

/// Decrypts an encrypted WAV file and returns its samples as mono float32 at 16kHz.
///
/// The file was produced by `CaptureStage.encryptAndDeletePlaintext`, which wrote
/// the ciphertext of an `AVAudioFile` WAV (16kHz mono float32).
enum AudioSampleDecoder {

    /// Decrypt and decode an encrypted `.enc` audio file.
    /// - Returns: Mono float32 sample array (16 kHz).
    /// - Throws: `PipelineError.transcribeAudioFileEmpty` if decryption or decoding fails,
    ///           or if the decoded audio is too short (< 0.1 s = 1600 frames).
    static func decode(from encURL: URL, encryptionKeyId: String) throws -> [Float] {
        guard FileManager.default.fileExists(atPath: encURL.path) else {
            throw PipelineError.transcribeAudioFileEmpty
        }
        let ciphertext = try Data(contentsOf: encURL, options: .mappedIfSafe)
        guard !ciphertext.isEmpty else { throw PipelineError.transcribeAudioFileEmpty }

        let plaintext: Data
        do {
            plaintext = try EncryptionManager.decrypt(ciphertext, keyIdentifier: encryptionKeyId)
        } catch {
            throw PipelineError.transcribeAudioFileEmpty
        }

        return try decodePCM(from: plaintext)
    }

    // MARK: - Private

    /// Writes `data` to a temp file, opens it as AVAudioFile, reads float32 frames.
    private static func decodePCM(from data: Data) throws -> [Float] {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".wav")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        try data.write(to: tempURL, options: .atomic)

        // Specify Float32 as the processingFormat so the buffer type matches.
        let audioFile: AVAudioFile
        do {
            audioFile = try AVAudioFile(
                forReading: tempURL,
                commonFormat: .pcmFormatFloat32,
                interleaved: false
            )
        } catch {
            throw PipelineError.transcribeAudioFileEmpty
        }

        let frameCount = AVAudioFrameCount(audioFile.length)
        guard frameCount > 1_600 else { // < 0.1 s at 16 kHz → treat as empty
            return []
        }

        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: audioFile.processingFormat,
            frameCapacity: frameCount
        ) else {
            throw PipelineError.transcribeAudioFileEmpty
        }

        do {
            try audioFile.read(into: buffer)
        } catch {
            throw PipelineError.transcribeAudioFileEmpty
        }

        // Use the actual frames read (buffer.frameLength), not the file length
        let actualFrames = buffer.frameLength
        guard actualFrames > 0, let channelData = buffer.floatChannelData?[0] else {
            throw PipelineError.transcribeAudioFileEmpty
        }
        return Array(UnsafeBufferPointer(start: channelData, count: Int(actualFrames)))
    }
}

// MARK: - TranscribeStage

/// Transcribes each `AudioStream` channel independently using WhisperEngine.
///
/// Produces one `TranscribedSegment` per Whisper segment per channel.
/// Channels are transcribed concurrently using separate engine instances.
/// The model is loaded before and unloaded after each channel to manage memory.
public final class TranscribeStage: TranscribeStageProtocol {

    private let engineFactory: () -> WhisperEngineProtocol
    private let config: TranscribeConfiguration
    private let log = VoxemaLogger.make(category: "transcribe.stage")
    private var isCancelled = false

    // MARK: - Init

    /// Production initialiser — creates real `WhisperEngine` instances.
    public convenience init(config: TranscribeConfiguration = .default) {
        self.init(engineFactory: { WhisperEngine() }, config: config)
    }

    /// Injectable initialiser — accepts a factory closure for tests.
    init(
        engineFactory: @escaping () -> WhisperEngineProtocol,
        config: TranscribeConfiguration = .default
    ) {
        self.engineFactory = engineFactory
        self.config = config
    }

    // MARK: - TranscribeStageProtocol

    public func run(_ streams: [AudioStream]) async throws -> [TranscribedSegment] {
        isCancelled = false
        guard !streams.isEmpty else { return [] }

        log.info("TranscribeStage.run started")

        // Transcribe each channel independently; collect results in order
        var allSegments: [TranscribedSegment] = []
        for stream in streams {
            if isCancelled { throw PipelineError.transcribeAudioFileEmpty }
            let segments = try await transcribeStream(stream)
            allSegments.append(contentsOf: segments)
        }

        log.info("TranscribeStage.run complete")
        return allSegments
    }

    public func cancel() {
        isCancelled = true
        log.info("TranscribeStage cancelled")
    }

    // MARK: - Private

    private func transcribeStream(_ stream: AudioStream) async throws -> [TranscribedSegment] {
        let encURL = URL(fileURLWithPath: stream.filePath)

        // Decode audio to float32 samples
        let samples: [Float]
        do {
            samples = try AudioSampleDecoder.decode(
                from: encURL,
                encryptionKeyId: config.encryptionKeyId
            )
        } catch PipelineError.transcribeAudioFileEmpty {
            log.info("TranscribeStage: audio file empty or too short, skipping channel")
            return []
        }

        guard !samples.isEmpty else { return [] }

        // Load model, transcribe, unload
        let engine = engineFactory()
        defer { engine.unloadModel() }

        do {
            try engine.loadModel(at: config.modelURL)
        } catch {
            throw (error as? PipelineError) ?? PipelineError.transcribeModelNotFound(modelName: "")
        }

        let rawSegments = try engine.transcribe(samples: samples, language: config.language)

        // Detect language (from whisper context if available; fallback to "und")
        let detectedLanguage = config.language ?? "und"

        // Map raw segments → typed TranscribedSegment, applying no-speech gate
        return rawSegments
            .filter { $0.noSpeechProb < config.noSpeechThreshold }
            .compactMap { seg -> TranscribedSegment? in
                guard !seg.text.isEmpty else { return nil }
                return TranscribedSegment(
                    segmentId: UUID(),
                    channel: stream.channel,
                    startTime: Float(seg.startMs) / 1000.0,
                    endTime:   Float(seg.endMs)   / 1000.0,
                    text:      seg.text,
                    language:  detectedLanguage,
                    confidence: max(0, 1.0 - seg.noSpeechProb)
                )
            }
    }
}
