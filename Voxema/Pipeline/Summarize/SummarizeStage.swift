import Foundation

// MARK: - PromptBuilder

/// Assembles the LLM prompt from a template and the meeting's diarized transcript.
/// All methods are pure functions — no side effects.
public enum PromptBuilder {

    static let transcriptPlaceholder = "{{transcript}}"
    static let languagePlaceholder   = "{{language}}"

    /// Rough token count estimate: 1 token ≈ 3.5 characters (conservative for Russian/English mix).
    static func estimateTokens(_ text: String) -> Int { max(1, text.count / 3) }

    /// Substitutes `{{transcript}}` and `{{language}}` in `template` with the
    /// formatted transcript and the dominant meeting language respectively.
    /// Truncates the transcript if the resulting prompt would exceed `maxPromptTokens`.
    public static func build(
        segments: [DiarizedSegment],
        template: String,
        maxPromptTokens: Int = 7200   // 8192 ctx − 512 output − ~480 system prompt
    ) -> String {
        let lang       = dominantLanguage(segments: segments)
        let langName   = languageName(for: lang)
        var transcript = formatTranscript(segments: segments)

        // Check if the full prompt fits; if not, truncate the transcript keeping
        // the first 40% and last 40% of segments (drop the middle).
        let fullPrompt = template
            .replacingOccurrences(of: languagePlaceholder,   with: langName)
            .replacingOccurrences(of: transcriptPlaceholder, with: transcript)

        if estimateTokens(fullPrompt) > maxPromptTokens, segments.count > 4 {
            let keep = max(2, segments.count * 2 / 5)  // 40% from each end
            let head = Array(segments.prefix(keep))
            let tail = Array(segments.suffix(keep))
            let truncated = head + tail
            transcript = formatTranscript(segments: truncated)
                + "\n[...middle portion omitted — meeting too long for context window...]"
        }

        return template
            .replacingOccurrences(of: languagePlaceholder,   with: langName)
            .replacingOccurrences(of: transcriptPlaceholder, with: transcript)
    }

    /// Reads the default prompt template from the app bundle.
    /// Falls back to a minimal inline template if the resource is missing.
    public static func defaultTemplate() -> String {
        guard let url = Bundle.main.url(forResource: "meeting_summary", withExtension: "md",
                                        subdirectory: "Prompts"),
              let contents = try? String(contentsOf: url, encoding: .utf8)
        else {
            return defaultInlineTemplate
        }
        return contents
    }

    /// Formats diarized segments as "[HH:MM:SS-HH:MM:SS] Speaker: text" lines.
    static func formatTranscript(segments: [DiarizedSegment]) -> String {
        guard !segments.isEmpty else { return "(empty transcript)" }
        return segments.map { seg in
            let start = formatTime(seg.startTime)
            let end   = formatTime(seg.endTime)
            return "[\(start)-\(end)] \(seg.speaker.label): \(seg.text)"
        }.joined(separator: "\n")
    }

    /// Returns the BCP-47 code of the most frequently occurring language across segments.
    static func dominantLanguage(segments: [DiarizedSegment]) -> String {
        let counts = segments.reduce(into: [String: Int]()) { dict, seg in
            guard !seg.language.isEmpty else { return }
            dict[seg.language, default: 0] += 1
        }
        return counts.max(by: { $0.value < $1.value })?.key ?? "en"
    }

    /// Maps a BCP-47 code to a full English language name suitable for LLM prompts.
    static func languageName(for code: String) -> String {
        let base = code.lowercased().components(separatedBy: "-").first ?? code
        let names: [String: String] = [
            "af": "Afrikaans", "ar": "Arabic",  "be": "Belarusian", "bg": "Bulgarian",
            "ca": "Catalan",   "cs": "Czech",   "cy": "Welsh",      "da": "Danish",
            "de": "German",    "el": "Greek",   "en": "English",    "es": "Spanish",
            "et": "Estonian",  "eu": "Basque",  "fa": "Persian",    "fi": "Finnish",
            "fr": "French",    "ga": "Irish",   "gl": "Galician",   "he": "Hebrew",
            "hi": "Hindi",     "hr": "Croatian","hu": "Hungarian",  "hy": "Armenian",
            "id": "Indonesian","is": "Icelandic","it": "Italian",   "ja": "Japanese",
            "ka": "Georgian",  "kk": "Kazakh",  "ko": "Korean",    "lt": "Lithuanian",
            "lv": "Latvian",   "mk": "Macedonian","ms": "Malay",   "mt": "Maltese",
            "nl": "Dutch",     "no": "Norwegian","pl": "Polish",   "pt": "Portuguese",
            "ro": "Romanian",  "ru": "Russian", "sk": "Slovak",    "sl": "Slovenian",
            "sq": "Albanian",  "sr": "Serbian", "sv": "Swedish",   "sw": "Swahili",
            "th": "Thai",      "tr": "Turkish", "uk": "Ukrainian", "ur": "Urdu",
            "vi": "Vietnamese","zh": "Chinese",
        ]
        return names[base] ?? code
    }

    private static func formatTime(_ seconds: Float) -> String {
        let total = Int(seconds)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, s)
            : String(format: "%02d:%02d", m, s)
    }

    private static let defaultInlineTemplate = """
    You are an expert meeting assistant. The meeting was conducted in {{language}}.
    IMPORTANT: You MUST write every field of the JSON response in {{language}}. Do NOT use English.

    Analyze the transcript and respond with only this JSON:
    {"summary":"...","key_decisions":[...],"action_items":[{"description":"...","assignee":null,"deadline":null}],"open_questions":[...]}

    ## Transcript
    \(transcriptPlaceholder)
    """
}

// MARK: - SummarizeConfiguration

/// Configuration for the Summarize stage.
public struct SummarizeConfiguration: Sendable {
    /// Selected LLM provider type.
    public let provider: ProviderType
    /// Model identifier (file name for local, API model name for cloud).
    public let modelName: String
    /// Prompt template — use `PromptBuilder.defaultTemplate()` for default.
    public let promptTemplate: String
    /// Maximum token count for LLM generation (local provider).
    public let maxNewTokens: Int
    /// Maximum retry attempts on transient errors.
    public let maxRetries: Int
    /// Required for `.cloud` provider; user must explicitly grant consent each session.
    public let consentGranted: Bool
    /// URL to the GGUF model file (local provider only).
    public let localModelURL: URL

    public static let `default` = SummarizeConfiguration(
        provider: .local,
        modelName: "Qwen2.5-3B-Instruct-Q4_K_M.gguf",
        promptTemplate: PromptBuilder.defaultTemplate(),
        maxNewTokens: 512,
        maxRetries: 3,
        consentGranted: false,
        localModelURL: URL(fileURLWithPath: "")
    )

    public init(
        provider: ProviderType,
        modelName: String,
        promptTemplate: String,
        maxNewTokens: Int = 512,
        maxRetries: Int = 3,
        consentGranted: Bool = false,
        localModelURL: URL = URL(fileURLWithPath: "")
    ) {
        self.provider       = provider
        self.modelName      = modelName
        self.promptTemplate = promptTemplate
        self.maxNewTokens   = maxNewTokens
        self.maxRetries     = maxRetries
        self.consentGranted = consentGranted
        self.localModelURL  = localModelURL
    }
}

// MARK: - SummarizeStage

/// Orchestrates prompt building and LLM inference for meeting summarization.
///
/// - Empty `segments` input returns a blank `MeetingSummary` immediately without
///   invoking the provider (avoids unnecessary model load).
/// - Transient errors are retried up to `config.maxRetries` times with exponential
///   back-off (0.5 s × 2^attempt).
/// - Non-retryable errors (consent not granted, model too large) throw immediately.
public final class SummarizeStage: SummarizeStageProtocol {

    private let providerFactory: (SummarizeConfiguration) -> SummaryProviderProtocol
    private let config: SummarizeConfiguration
    private let log = VoxemaLogger.make(category: "summarize.stage")
    private var isCancelled = false

    // MARK: - Init

    public convenience init(config: SummarizeConfiguration = .default) {
        self.init(providerFactory: { cfg in
            switch cfg.provider {
            case .local:
                return LocalProvider(modelURL: cfg.localModelURL, maxNewTokens: cfg.maxNewTokens)
            case .cloud:
                return (try? CloudProvider.makeFromKeychain(
                    modelName: cfg.modelName,
                    consentGranted: cfg.consentGranted
                )) ?? LocalProvider(modelURL: URL(fileURLWithPath: ""))
            case .onPrem:
                return LocalProvider(modelURL: URL(fileURLWithPath: ""))  // stub
            }
        }, config: config)
    }

    init(
        providerFactory: @escaping (SummarizeConfiguration) -> SummaryProviderProtocol,
        config: SummarizeConfiguration = .default
    ) {
        self.providerFactory = providerFactory
        self.config = config
    }

    // MARK: - SummarizeStageProtocol

    /// Minimum total word count across all segments required to invoke the LLM.
    /// Below this threshold the transcript is too short for meaningful summarization
    /// and small models hallucinate plausible-but-unrelated content instead.
    private static let minWordsForSummary = 25

    public func run(_ segments: [DiarizedSegment]) async throws -> MeetingSummary {
        isCancelled = false

        let totalWords = segments.reduce(0) { $0 + $1.text.split(separator: " ").count }

        guard !segments.isEmpty, totalWords >= Self.minWordsForSummary else {
            log.info("SummarizeStage: transcript too short — skipping LLM")
            return MeetingSummary(
                meetingId:    UUID(),
                summaryText:  "",
                providerUsed: config.provider,
                modelName:    config.modelName
            )
        }

        let meetingId = UUID()
        let prompt = PromptBuilder.build(segments: segments, template: config.promptTemplate)

        let provider = providerFactory(config)
        defer { provider.unload() }

        log.info("SummarizeStage: calling provider")
        let summary = try await callWithRetry(provider: provider, prompt: prompt, meetingId: meetingId)
        log.info("SummarizeStage: complete")
        return summary
    }

    public func cancel() {
        isCancelled = true
        log.info("SummarizeStage: cancelled")
    }

    // MARK: - Private

    private func callWithRetry(
        provider: SummaryProviderProtocol,
        prompt: String,
        meetingId: UUID
    ) async throws -> MeetingSummary {
        var lastError: Error = PipelineError.summarizeMaxRetriesExceeded(retries: config.maxRetries)

        for attempt in 0 ..< max(1, config.maxRetries) {
            if isCancelled { throw PipelineError.summarizeMaxRetriesExceeded(retries: attempt) }
            do {
                return try await provider.summarize(prompt: prompt, meetingId: meetingId)
            } catch PipelineError.summarizeCloudConsentNotGranted {
                throw PipelineError.summarizeCloudConsentNotGranted
            } catch PipelineError.summarizeLocalModelTooLargeForRAM(let name, let gb) {
                throw PipelineError.summarizeLocalModelTooLargeForRAM(modelName: name, requiredGB: gb)
            } catch {
                lastError = error
                if attempt < config.maxRetries - 1 {
                    let delayNs = UInt64(500_000_000) * UInt64(pow(2.0, Double(attempt)))
                    try? await Task.sleep(nanoseconds: delayNs)
                }
            }
        }
        throw lastError
    }
}
