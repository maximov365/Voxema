import Foundation
import whisper

// MARK: - WhisperSegment

/// Raw transcription result from a single Whisper segment.
public struct WhisperSegment: Equatable, Sendable {
    /// Start time in milliseconds.
    public let startMs: Int64
    /// End time in milliseconds.
    public let endMs: Int64
    /// Transcribed text, trimmed of leading/trailing whitespace.
    public let text: String
    /// Whisper no-speech probability in [0, 1].  High value = likely silence.
    public let noSpeechProb: Float
}

// MARK: - WhisperEngineProtocol

/// Abstraction over the whisper.cpp C library.
/// Enables testing `TranscribeStage` with a mock engine without real inference.
public protocol WhisperEngineProtocol: AnyObject {
    /// Loads the GGUF model file at `url` into memory.
    func loadModel(at url: URL) throws
    /// Transcribes `samples` (mono float32, 16kHz) and returns raw segments.
    /// `language`: BCP-47 code or `nil` for auto-detect.
    func transcribe(samples: [Float], language: String?) throws -> [WhisperSegment]
    /// Releases the model from memory. Safe to call when no model is loaded.
    func unloadModel()
}

// MARK: - WhisperEngine

/// Real implementation backed by the whisper.cpp C library (via `CWhisper`).
///
/// Swift imports the opaque `whisper_context *` as `OpaquePointer?`.
///
/// Thread safety: one instance per channel — do not share across threads.
public final class WhisperEngine: WhisperEngineProtocol {

    // whisper_context * is an opaque C struct → Swift imports as OpaquePointer
    private var ctx: OpaquePointer?
    private let log = VoxemaLogger.make(category: "transcribe.engine")

    public init() {}

    deinit { unloadModel() }

    public func loadModel(at url: URL) throws {
        unloadModel()
        let loaded: OpaquePointer? = url.withUnsafeFileSystemRepresentation { path in
            guard let path else { return nil }
            return whisper_init_from_file(path)
        }
        guard let loaded else {
            log.error("whisper_init_from_file returned nil")
            throw PipelineError.transcribeModelNotFound(modelName: url.lastPathComponent)
        }
        ctx = loaded
        log.info("WhisperEngine model loaded")
    }

    public func transcribe(samples: [Float], language: String?) throws -> [WhisperSegment] {
        guard let ctx else {
            throw PipelineError.transcribeModelNotFound(modelName: "")
        }
        guard !samples.isEmpty else { return [] }

        var params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
        params.n_threads        = Int32(min(ProcessInfo.processInfo.processorCount, 8))
        params.print_progress   = false
        params.print_realtime   = false
        params.print_timestamps = false
        params.no_context       = true
        params.no_speech_thold  = 0.6

        // language is `const char *` in real whisper.cpp — must remain valid
        // for the entire duration of whisper_full. Keep langStr alive in scope.
        let langStr = language ?? "auto"
        return try langStr.withCString { langPtr in
            params.language = langPtr

            let result = samples.withUnsafeBufferPointer { buf in
                whisper_full(ctx, params, buf.baseAddress, Int32(buf.count))
            }
            guard result == 0 else {
                log.error("whisper_full returned \(result)")
                return []
            }

            let n = Int(whisper_full_n_segments(ctx))
            var segments: [WhisperSegment] = []
            segments.reserveCapacity(n)

            for i in 0 ..< n {
                let text: String
                if let rawText = whisper_full_get_segment_text(ctx, Int32(i)) {
                    text = String(cString: rawText).trimmingCharacters(in: .whitespaces)
                } else {
                    text = ""
                }
                let t0  = whisper_full_get_segment_t0(ctx, Int32(i))
                let t1  = whisper_full_get_segment_t1(ctx, Int32(i))
                let nsp = whisper_full_get_segment_no_speech_prob(ctx, Int32(i))

                segments.append(WhisperSegment(
                    startMs: t0 * 10,   // whisper returns centiseconds → ms
                    endMs:   t1 * 10,
                    text:    text,
                    noSpeechProb: nsp
                ))
            }
            return segments
        }
    }

    public func unloadModel() {
        guard let ctx else { return }
        whisper_free(ctx)
        self.ctx = nil
        log.info("WhisperEngine model unloaded")
    }
}
