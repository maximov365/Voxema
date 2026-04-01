import Foundation

// MARK: - PromptBuilder

/// Assembles the LLM prompt from a template and the meeting's diarized transcript.
/// All methods are pure functions — no side effects.
public enum PromptBuilder {

    static let transcriptPlaceholder = "{{transcript}}"

    /// Substitutes `{{transcript}}` in `template` with the formatted meeting transcript.
    public static func build(segments: [DiarizedSegment], template: String) -> String {
        let transcript = formatTranscript(segments: segments)
        return template.replacingOccurrences(of: transcriptPlaceholder, with: transcript)
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
    Analyze this meeting transcript and respond with a JSON object containing:
    summary, key_decisions (array), action_items (array of {description, assignee, deadline}), open_questions (array).
    Respond with only the JSON.

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
        maxNewTokens: 2048,
        maxRetries: 3,
        consentGranted: false,
        localModelURL: URL(fileURLWithPath: "")
    )

    public init(
        provider: ProviderType,
        modelName: String,
        promptTemplate: String,
        maxNewTokens: Int = 2048,
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

    public func run(_ segments: [DiarizedSegment]) async throws -> MeetingSummary {
        isCancelled = false

        guard !segments.isEmpty else {
            log.info("SummarizeStage: empty input — returning blank summary")
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
