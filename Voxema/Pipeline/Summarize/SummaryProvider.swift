import Foundation
import CLlama

// MARK: - SummaryProviderProtocol

/// Abstraction over local (llama.cpp) and cloud (URLSession) LLM providers.
/// Enables testing SummarizeStage with a mock without real inference or network calls.
public protocol SummaryProviderProtocol: AnyObject {
    /// Sends `prompt` to the LLM and returns a parsed `MeetingSummary`.
    func summarize(prompt: String, meetingId: UUID) async throws -> MeetingSummary
    /// Releases any model resources (idempotent).
    func unload()
}

// MARK: - SummaryOutputParser

/// Pure-Swift parser that extracts a structured `MeetingSummary` from raw LLM text output.
/// Handles output with or without leading preamble text.
public enum SummaryOutputParser {

    private struct RawOutput: Decodable {
        let summary: String
        let keyDecisions: [String]
        let actionItems: [RawActionItem]
        let openQuestions: [String]

        private enum CodingKeys: String, CodingKey {
            case summary
            case keyDecisions   = "key_decisions"
            case actionItems    = "action_items"
            case openQuestions  = "open_questions"
        }
    }

    private struct RawActionItem: Decodable {
        let description: String
        let assignee: String?
        let deadline: String?
    }

    /// Parses `text` (which may contain preamble) into a `MeetingSummary`.
    /// Throws `PipelineError.summarizeMalformedOutput` on failure.
    public static func parse(
        _ text: String,
        meetingId: UUID,
        provider: ProviderType,
        model: String
    ) throws -> MeetingSummary {
        guard let jsonString = extractJSON(from: text),
              let data = jsonString.data(using: .utf8) else {
            throw PipelineError.summarizeMalformedOutput
        }

        let raw: RawOutput
        do {
            raw = try JSONDecoder().decode(RawOutput.self, from: data)
        } catch {
            throw PipelineError.summarizeMalformedOutput
        }

        let items = raw.actionItems.map {
            ActionItem(actionDescription: $0.description, assignee: $0.assignee, deadline: $0.deadline)
        }

        return MeetingSummary(
            meetingId:    meetingId,
            summaryText:  raw.summary,
            keyDecisions: raw.keyDecisions,
            actionItems:  items,
            openQuestions: raw.openQuestions,
            providerUsed: provider,
            modelName:    model
        )
    }

    /// Finds the first complete `{...}` JSON object in `text`.
    static func extractJSON(from text: String) -> String? {
        guard let start = text.firstIndex(of: "{") else { return nil }
        var depth = 0
        var end: String.Index? = nil
        var inString = false
        var escaped = false

        var i = start
        while i < text.endIndex {
            let ch = text[i]
            if escaped {
                escaped = false
            } else if ch == "\\" && inString {
                escaped = true
            } else if ch == "\"" {
                inString.toggle()
            } else if !inString {
                if ch == "{" { depth += 1 }
                else if ch == "}" {
                    depth -= 1
                    if depth == 0 { end = text.index(after: i); break }
                }
            }
            i = text.index(after: i)
        }

        guard let end else { return nil }
        return String(text[start ..< end])
    }
}

// MARK: - LocalProvider

/// On-device LLM inference via the `CLlama` C bridge (llama.cpp stub).
/// Model is loaded lazily on first `summarize` call and released via `unload()`.
public final class LocalProvider: SummaryProviderProtocol {

    private let modelURL: URL
    private let contextSize: Int
    private let maxNewTokens: Int
    private var ctx: OpaquePointer?
    private let log = VoxemaLogger.make(category: "summarize.local")

    public init(modelURL: URL, contextSize: Int = 8192, maxNewTokens: Int = 512) {
        self.modelURL = modelURL
        self.contextSize = contextSize
        self.maxNewTokens = maxNewTokens
    }

    deinit { unload() }

    public func summarize(prompt: String, meetingId: UUID) async throws -> MeetingSummary {
        if ctx == nil { try loadModel() }
        guard let ctx else { throw PipelineError.summarizeLocalModelTooLargeForRAM(
            modelName: modelURL.lastPathComponent, requiredGB: 0)
        }

        var outputBuf = [CChar](repeating: 0, count: Int(VOXEMA_LLM_MAX_OUTPUT_BYTES))
        let result = prompt.withCString { promptPtr in
            outputBuf.withUnsafeMutableBufferPointer { bufPtr in
                voxema_llm_generate(ctx, promptPtr, bufPtr.baseAddress, Int32(bufPtr.count), Int32(maxNewTokens))
            }
        }
        guard result == 0 else { throw PipelineError.summarizeMalformedOutput }
        let outputText = String(cString: outputBuf)
        log.info("LocalProvider: inference complete")
        return try SummaryOutputParser.parse(outputText, meetingId: meetingId, provider: .local, model: modelURL.lastPathComponent)
    }

    public func unload() {
        guard let ctx else { return }
        voxema_llm_free(ctx)
        self.ctx = nil
        log.info("LocalProvider: model unloaded")
    }

    private func loadModel() throws {
        let loaded: OpaquePointer? = modelURL.withUnsafeFileSystemRepresentation { path in
            guard let path else { return nil }
            return voxema_llm_init(path, Int32(contextSize))
        }
        guard let loaded else {
            throw PipelineError.summarizeLocalModelTooLargeForRAM(
                modelName: modelURL.lastPathComponent, requiredGB: 0)
        }
        ctx = loaded
        log.info("LocalProvider: model loaded")
    }
}

// MARK: - CloudProvider

/// Cloud LLM provider using the user's own API key (stored in Keychain).
/// Supports Anthropic (Claude) and OpenAI (GPT) determined by key prefix.
/// Requires explicit `consentGranted` before sending any transcript text.
public final class CloudProvider: SummaryProviderProtocol {

    public enum APITarget { case anthropic, openAI }

    private enum KeychainKey {
        static let service = "com.voxema.app"
        static let account = "api-key"
    }

    // MARK: API key Keychain helpers

    /// Persists the user's cloud API key in the Keychain.
    /// Called by the onboarding flow when the user completes setup with the Cloud tier selected.
    public static func storeAPIKey(_ key: String) throws {
        try KeychainManager.storeString(key, service: KeychainKey.service, account: KeychainKey.account)
    }

    /// Loads the stored cloud API key from the Keychain.
    /// Returns `nil` if no key has been stored yet.
    public static func loadAPIKey() -> String? {
        try? KeychainManager.retrieveString(service: KeychainKey.service, account: KeychainKey.account)
    }

    /// Removes the stored cloud API key from the Keychain.
    public static func deleteAPIKey() throws {
        try KeychainManager.delete(service: KeychainKey.service, account: KeychainKey.account)
    }

    private let target: APITarget
    private let modelName: String
    private let consentGranted: Bool
    private let session: URLSession
    private let log = VoxemaLogger.make(category: "summarize.cloud")

    public init(
        target: APITarget,
        modelName: String,
        consentGranted: Bool,
        session: URLSession = .shared
    ) {
        self.target = target
        self.modelName = modelName
        self.consentGranted = consentGranted
        self.session = session
    }

    /// Convenience: infers `APITarget` from the API key prefix in Keychain.
    public static func makeFromKeychain(
        modelName: String,
        consentGranted: Bool,
        keychainService: String = "com.voxema.app",
        keychainAccount: String = "api-key",
        session: URLSession = .shared
    ) throws -> CloudProvider {
        let key = try KeychainManager.retrieveString(service: keychainService, account: keychainAccount)
        let target: APITarget = key.hasPrefix("sk-ant-") ? .anthropic : .openAI
        return CloudProvider(target: target, modelName: modelName, consentGranted: consentGranted, session: session)
    }

    public func summarize(prompt: String, meetingId: UUID) async throws -> MeetingSummary {
        guard consentGranted else { throw PipelineError.summarizeCloudConsentNotGranted }

        let apiKey: String
        do {
            apiKey = try KeychainManager.retrieveString(service: KeychainKey.service, account: KeychainKey.account)
        } catch {
            throw PipelineError.summarizeCloudConsentNotGranted
        }

        let requestBody: [String: Any]
        let url: URL

        switch target {
        case .anthropic:
            url = URL(string: "https://api.anthropic.com/v1/messages")!
            requestBody = [
                "model": modelName,
                "max_tokens": 2048,
                "messages": [["role": "user", "content": prompt]]
            ]
        case .openAI:
            url = URL(string: "https://api.openai.com/v1/chat/completions")!
            requestBody = [
                "model": modelName,
                "messages": [["role": "user", "content": prompt]],
                "max_tokens": 2048
            ]
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        switch target {
        case .anthropic:
            request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        case .openAI:
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }

        request.httpBody = try? JSONSerialization.data(withJSONObject: requestBody)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw PipelineError.summarizeMalformedOutput }
        guard (200 ..< 300).contains(http.statusCode) else {
            throw PipelineError.summarizeCloudAPIError(statusCode: http.statusCode)
        }

        let text = extractCompletionText(data: data)
        log.info("CloudProvider: response received")
        return try SummaryOutputParser.parse(text, meetingId: meetingId, provider: .cloud, model: modelName)
    }

    public func unload() { /* No resources to release for URLSession */ }

    private func extractCompletionText(data: Data) -> String {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return "" }

        // Anthropic: response.content[0].text
        if let content = json["content"] as? [[String: Any]],
           let first = content.first,
           let text = first["text"] as? String {
            return text
        }
        // OpenAI: response.choices[0].message.content
        if let choices = json["choices"] as? [[String: Any]],
           let first = choices.first,
           let message = first["message"] as? [String: Any],
           let content = message["content"] as? String {
            return content
        }
        return ""
    }
}
