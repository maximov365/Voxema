import Foundation
import CWhisper

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
    /// `initialPrompt`: optional context hint prepended to the first 30-s chunk.
    func transcribe(samples: [Float], language: String?, initialPrompt: String?) throws -> [WhisperSegment]
    /// Releases the model from memory. Safe to call when no model is loaded.
    func unloadModel()
}

// MARK: - WhisperEngine

/// Real implementation backed by whisper.cpp v1.5.5 (via `CWhisper`).
///
/// Thread safety: one instance per channel — do not share across threads.
/// @unchecked Sendable: all mutable state (ctx) is accessed exclusively from
/// the single thread that owns each instance (enforced by TranscribeStage).
public final class WhisperEngine: WhisperEngineProtocol, @unchecked Sendable {

    private var ctx: OpaquePointer?
    private let log = VoxemaLogger.make(category: "transcribe.engine")

    public init() {}

    deinit { unloadModel() }

    public func loadModel(at url: URL) throws {
        unloadModel()
        var cparams = whisper_context_default_params()
        cparams.use_gpu = true
        let loaded: OpaquePointer? = url.withUnsafeFileSystemRepresentation { path in
            guard let path else { return nil }
            return whisper_init_from_file_with_params(path, cparams)
        }
        guard let loaded else {
            log.error("whisper_init_from_file_with_params returned nil")
            throw PipelineError.transcribeModelNotFound(modelName: url.lastPathComponent)
        }
        ctx = loaded
        log.info("WhisperEngine model loaded")
    }

    public func transcribe(samples: [Float], language: String?, initialPrompt: String?) throws -> [WhisperSegment] {
        guard let ctx else {
            throw PipelineError.transcribeModelNotFound(modelName: "")
        }
        guard !samples.isEmpty else { return [] }

        // Beam search produces noticeably better transcription than greedy,
        // especially for non-English languages. The overhead is small on GPU.
        var params = whisper_full_default_params(WHISPER_SAMPLING_BEAM_SEARCH)
        params.print_progress  = false
        params.print_realtime  = false
        params.print_special   = false
        params.print_timestamps = false
        // With Metal GPU, matrix math runs on-device; keep only 2 CPU threads
        // for preprocessing so the main actor and UI remain fully responsive.
        params.n_threads = 2

        let langStr  = language ?? "auto"
        // Non-empty prompt is passed as a C string. Nested withCString calls keep
        // both pointers alive for the full duration of whisper_full().
        let promptStr = initialPrompt ?? ""
        var segments: [WhisperSegment] = []

        let rc: Int32 = langStr.withCString { langPtr in
            promptStr.withCString { promptPtr in
                params.language      = langPtr
                params.initial_prompt = promptStr.isEmpty ? nil : promptPtr
                return samples.withUnsafeBufferPointer { buf in
                    whisper_full(ctx, params, buf.baseAddress, Int32(buf.count))
                }
            }
        }

        guard rc == 0 else {
            log.error("whisper_full returned non-zero")
            return []
        }

        let n = Int(whisper_full_n_segments(ctx))
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
                startMs: t0 * 10,
                endMs:   t1 * 10,
                text:    text,
                noSpeechProb: nsp
            ))
        }
        return segments
    }

    public func unloadModel() {
        guard let ctx else { return }
        whisper_free(ctx)
        self.ctx = nil
        log.info("WhisperEngine model unloaded")
    }
}
