import Foundation
import AVFoundation
import Accelerate

// MARK: - TranscribeConfiguration

/// Configuration for the Transcribe stage.
public struct TranscribeConfiguration: Sendable {
    /// URL of the GGUF Whisper model file to use.
    public let modelURL: URL
    /// BCP-47 language override. `nil` enables auto-detection per channel.
    public let language: String?
    /// Segments with `noSpeechProb` above this value are discarded (silence gate).
    public let noSpeechThreshold: Float
    /// Audio RMS energy gate: channels whose mean RMS is below this value are
    /// skipped entirely before Whisper is even loaded. Prevents Whisper hallucinations
    /// on silent or near-silent system-audio when no call is active.
    /// Typical speech RMS: 0.05–0.3.  Ambient noise/silence: < 0.002.
    public let minAudioRMS: Float
    /// Keychain key identifier used to decrypt audio files from the Capture stage.
    public let encryptionKeyId: String
    /// Optional context hint passed to Whisper as `initial_prompt` for the first
    /// 30-second chunk. Reduces hallucinations and anchors vocabulary to meeting
    /// domain. `nil` disables the prompt (Whisper default behaviour).
    public let initialPrompt: String?

    public static let `default` = TranscribeConfiguration(
        modelURL: URL(fileURLWithPath: ""),  // replaced at runtime by PipelineCoordinator
        language: nil,
        noSpeechThreshold: 0.5,
        minAudioRMS: 0.004,
        encryptionKeyId: "com.voxema.app.capture-audio-key",
        initialPrompt: "Meeting transcript:"
    )

    public init(
        modelURL: URL,
        language: String? = nil,
        noSpeechThreshold: Float = 0.5,
        minAudioRMS: Float = 0.004,
        encryptionKeyId: String = "com.voxema.app.capture-audio-key",
        initialPrompt: String? = "Meeting transcript:"
    ) {
        self.modelURL = modelURL
        self.language = language
        self.noSpeechThreshold = noSpeechThreshold
        self.minAudioRMS = minAudioRMS
        self.encryptionKeyId = encryptionKeyId
        self.initialPrompt = initialPrompt
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

    private let engineFactory: @Sendable () -> any WhisperEngineProtocol
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
        engineFactory: @escaping @Sendable () -> any WhisperEngineProtocol,
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
        let encURL        = URL(fileURLWithPath: stream.filePath)
        let channel       = stream.channel
        let modelURL      = config.modelURL
        let encryptionKey = config.encryptionKeyId
        let language      = config.language
        let noSpeechGate  = config.noSpeechThreshold
        let minRMS        = config.minAudioRMS
        let initialPrompt = config.initialPrompt
        let engine        = engineFactory()

        // Use withCheckedThrowingContinuation + DispatchQueue.global() instead of
        // Task.detached. This puts the work on a plain GCD thread that has zero
        // interaction with Swift's actor system, eliminating any risk of the compiler's
        // @MainActor inference causing these methods to dispatch back to the main thread.
        let rawSegments: [WhisperSegment] = try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let samples = try AudioSampleDecoder.decode(
                        from: encURL, encryptionKeyId: encryptionKey)
                    guard !samples.isEmpty else {
                        continuation.resume(returning: [])
                        return
                    }
                    // RMS energy gate: skip Whisper entirely on silent audio.
                    // Prevents hallucinations (e.g. Russian subtitle credits) when the
                    // remote channel is quiet and no real speech is present.
                    var rms: Float = 0
                    vDSP_rmsqv(samples, 1, &rms, vDSP_Length(samples.count))
                    guard rms >= minRMS else {
                        continuation.resume(returning: [])
                        return
                    }
                    // RMS normalisation: scale audio to targetRMS when it is
                    // quieter than the target. Whisper is sensitive to input
                    // level — under-gain causes missed words; over-gain is safe
                    // because we clamp output to [-1, 1].
                    let targetRMS: Float = 0.1
                    let transcribeSamples: [Float]
                    if rms > 0 && rms < targetRMS {
                        var scale = targetRMS / rms
                        var normalised = [Float](repeating: 0, count: samples.count)
                        vDSP_vsmul(samples, 1, &scale, &normalised, 1, vDSP_Length(samples.count))
                        var lower: Float = -1.0
                        var upper: Float =  1.0
                        vDSP_vclip(normalised, 1, &lower, &upper, &normalised, 1, vDSP_Length(normalised.count))
                        transcribeSamples = normalised
                    } else {
                        transcribeSamples = samples
                    }
                    try engine.loadModel(at: modelURL)
                    defer { engine.unloadModel() }
                    let segs = try engine.transcribe(samples: transcribeSamples, language: language, initialPrompt: initialPrompt)
                    continuation.resume(returning: segs)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }

        guard !rawSegments.isEmpty else { return [] }

        let detectedLanguage = language ?? "und"
        return rawSegments
            .filter { $0.noSpeechProb < noSpeechGate }
            .compactMap { seg -> TranscribedSegment? in
                guard !seg.text.isEmpty else { return nil }
                return TranscribedSegment(
                    segmentId: UUID(),
                    channel:   channel,
                    startTime: Float(seg.startMs) / 1000.0,
                    endTime:   Float(seg.endMs)   / 1000.0,
                    text:      seg.text,
                    language:  detectedLanguage,
                    confidence: max(0, 1.0 - seg.noSpeechProb)
                )
            }
    }
}
