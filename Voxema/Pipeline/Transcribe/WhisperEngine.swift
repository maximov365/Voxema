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
        // 4 CPU threads for preprocessing/postprocessing alongside Metal GPU.
        // 2 was too conservative — on M-series, 4 threads + Metal gives best
        // throughput without saturating the efficiency cores used by UI.
        params.n_threads = 4

        // ── Quality tuning ───────────────────────────────────────────────────
        // beam_size=5: standard research setting; -1 (auto) maps to same value
        // but making it explicit prevents future whisper.cpp default changes.
        params.beam_search.beam_size = 5
        // suppress_non_speech_tokens: removes filler tokens ([BLANK_AUDIO],
        // breathing, laughter markers) that pollute meeting transcripts.
        params.suppress_non_speech_tokens = true
        // entropy_thold: keep at default (2.4) to avoid triggering temperature
        // fallback retries. Each retry reruns the full beam search, so a tighter
        // threshold can multiply inference time by 3-6×. Hallucination suppression
        // is handled by the RMS gate and noSpeechProb post-filter instead.
        // params.entropy_thold = 2.4  ← this is the default, no need to set

        // no_speech_thold: Whisper's internal no-speech gate (default 0.6).
        // Slight tighten to 0.45 is cheap — it only skips output, no retry cost.
        params.no_speech_thold = 0.45

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
