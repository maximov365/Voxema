import XCTest
@testable import Voxema

// MARK: - Mock provider

private final class MockSummaryProvider: SummaryProviderProtocol {
    var result: MeetingSummary?
    var error: Error?
    var failFirstNTimes: Int = 0
    private(set) var callCount = 0
    private(set) var unloadCalled = false

    func summarize(prompt: String, meetingId: UUID) async throws -> MeetingSummary {
        callCount += 1
        if callCount <= failFirstNTimes {
            throw error ?? PipelineError.summarizeMalformedOutput
        }
        if let err = error { throw err }
        return result ?? MeetingSummary(
            meetingId: meetingId,
            summaryText: "mock summary",
            providerUsed: .local,
            modelName: "mock"
        )
    }

    func unload() { unloadCalled = true }
}

// MARK: - Helpers

private func makeConfig(maxRetries: Int = 1) -> SummarizeConfiguration {
    SummarizeConfiguration(
        provider: .local,
        modelName: "test",
        promptTemplate: "Transcript: {{transcript}}",
        maxRetries: maxRetries
    )
}

private func makeStage(provider: MockSummaryProvider, maxRetries: Int = 1) -> SummarizeStage {
    SummarizeStage(providerFactory: { _ in provider }, config: makeConfig(maxRetries: maxRetries))
}

private func makeSeg(label: String = "You", text: String = "hello", start: Float = 0, end: Float = 1) -> DiarizedSegment {
    DiarizedSegment(
        segmentId: UUID(),
        startTime: start,
        endTime: end,
        text: text,
        speaker: SpeakerIdentity(label: label, isUser: true, confidence: 1.0, isKnown: true),
        channel: .local
    )
}

private let validJSON = """
{"summary":"Test summary.","key_decisions":["Decision A"],"action_items":[{"description":"Follow up","assignee":"Alice","deadline":"Friday"}],"open_questions":["What next?"]}
"""

// MARK: - Tests

final class SummarizeStageTests: XCTestCase {

    // ── 1. Empty segments ────────────────────────────────────────────────────

    func testEmptySegmentsReturnBlankSummary() async throws {
        let provider = MockSummaryProvider()
        let stage = makeStage(provider: provider)
        let result = try await stage.run([])
        XCTAssertEqual(result.summaryText, "")
        XCTAssertEqual(provider.callCount, 0, "Provider must not be called for empty input")
    }

    func testEmptySegmentsDoNotCallUnload() async throws {
        let provider = MockSummaryProvider()
        // providerFactory not invoked for empty segments
        var factoryCalled = false
        let stage = SummarizeStage(providerFactory: { _ in
            factoryCalled = true
            return provider
        }, config: makeConfig())
        _ = try await stage.run([])
        XCTAssertFalse(factoryCalled)
    }

    // ── 2. Happy path ────────────────────────────────────────────────────────

    func testRunWithSegmentsCallsProvider() async throws {
        let provider = MockSummaryProvider()
        let stage = makeStage(provider: provider)
        _ = try await stage.run([makeSeg()])
        XCTAssertEqual(provider.callCount, 1)
    }

    func testRunReturnsProviderResult() async throws {
        let provider = MockSummaryProvider()
        provider.result = MeetingSummary(
            meetingId: UUID(), summaryText: "custom", providerUsed: .local, modelName: "m"
        )
        let stage = makeStage(provider: provider)
        let result = try await stage.run([makeSeg()])
        XCTAssertEqual(result.summaryText, "custom")
    }

    // ── 3. Resource safety ───────────────────────────────────────────────────

    func testUnloadCalledAfterSuccess() async throws {
        let provider = MockSummaryProvider()
        let stage = makeStage(provider: provider)
        _ = try await stage.run([makeSeg()])
        XCTAssertTrue(provider.unloadCalled)
    }

    func testUnloadCalledAfterError() async throws {
        let provider = MockSummaryProvider()
        provider.error = PipelineError.summarizeMalformedOutput
        let stage = makeStage(provider: provider)
        do { _ = try await stage.run([makeSeg()]) } catch { }
        XCTAssertTrue(provider.unloadCalled)
    }

    // ── 4. Retry logic ───────────────────────────────────────────────────────

    func testRetrySucceedsAfterTransientFailure() async throws {
        let provider = MockSummaryProvider()
        provider.failFirstNTimes = 2
        // maxRetries = 3 → first 2 fail, 3rd succeeds
        let stage = makeStage(provider: provider, maxRetries: 3)
        let result = try await stage.run([makeSeg()])
        XCTAssertEqual(provider.callCount, 3)
        XCTAssertEqual(result.summaryText, "mock summary")
    }

    func testNonRetryableConsentErrorThrowsImmediately() async throws {
        let provider = MockSummaryProvider()
        provider.error = PipelineError.summarizeCloudConsentNotGranted
        let stage = makeStage(provider: provider, maxRetries: 3)
        do {
            _ = try await stage.run([makeSeg()])
            XCTFail("Expected error")
        } catch PipelineError.summarizeCloudConsentNotGranted {
            XCTAssertEqual(provider.callCount, 1, "Must not retry on consent error")
        }
    }

    func testNonRetryableModelTooLargeThrowsImmediately() async throws {
        let provider = MockSummaryProvider()
        provider.error = PipelineError.summarizeLocalModelTooLargeForRAM(modelName: "m", requiredGB: 8)
        let stage = makeStage(provider: provider, maxRetries: 3)
        do {
            _ = try await stage.run([makeSeg()])
            XCTFail("Expected error")
        } catch PipelineError.summarizeLocalModelTooLargeForRAM {
            XCTAssertEqual(provider.callCount, 1)
        }
    }

    func testMaxRetriesExceededThrows() async throws {
        let provider = MockSummaryProvider()
        provider.error = PipelineError.summarizeMalformedOutput
        let stage = makeStage(provider: provider, maxRetries: 2)
        do {
            _ = try await stage.run([makeSeg()])
            XCTFail("Expected error")
        } catch PipelineError.summarizeMaxRetriesExceeded {
            XCTAssertEqual(provider.callCount, 2)
        }
    }

    // ── 5. SummaryOutputParser ───────────────────────────────────────────────

    func testParserExtractsSummaryText() throws {
        let id = UUID()
        let result = try SummaryOutputParser.parse(validJSON, meetingId: id, provider: .local, model: "m")
        XCTAssertEqual(result.summaryText, "Test summary.")
    }

    func testParserExtractsKeyDecisions() throws {
        let result = try SummaryOutputParser.parse(validJSON, meetingId: UUID(), provider: .local, model: "m")
        XCTAssertEqual(result.keyDecisions, ["Decision A"])
    }

    func testParserExtractsActionItemWithAssignee() throws {
        let result = try SummaryOutputParser.parse(validJSON, meetingId: UUID(), provider: .local, model: "m")
        XCTAssertEqual(result.actionItems.count, 1)
        XCTAssertEqual(result.actionItems[0].assignee, "Alice")
        XCTAssertEqual(result.actionItems[0].deadline, "Friday")
    }

    func testParserThrowsOnMalformedInput() throws {
        do {
            _ = try SummaryOutputParser.parse("not json at all", meetingId: UUID(), provider: .local, model: "m")
            XCTFail("Expected error")
        } catch PipelineError.summarizeMalformedOutput {
            // expected
        }
    }

    func testParserExtractsJSONEmbeddedInPreamble() throws {
        let preamble = "Here is the summary:\n" + validJSON + "\n\nThank you."
        let result = try SummaryOutputParser.parse(preamble, meetingId: UUID(), provider: .local, model: "m")
        XCTAssertEqual(result.summaryText, "Test summary.")
    }

    // ── 6. PromptBuilder ─────────────────────────────────────────────────────

    func testPromptBuilderIncludesSpeakerLabel() {
        let seg = makeSeg(label: "Alice", text: "Let's start")
        let result = PromptBuilder.build(segments: [seg], template: "{{transcript}}")
        XCTAssertTrue(result.contains("Alice"), "Prompt must include speaker label")
    }

    func testPromptBuilderIncludesSegmentText() {
        let seg = makeSeg(text: "important decision here")
        let result = PromptBuilder.build(segments: [seg], template: "{{transcript}}")
        XCTAssertTrue(result.contains("important decision here"))
    }

    func testPromptBuilderWithEmptySegmentsNocrash() {
        let result = PromptBuilder.build(segments: [], template: "T: {{transcript}}")
        XCTAssertFalse(result.isEmpty)
        XCTAssertTrue(result.contains("T:"))
    }

    // ── 7. CloudProvider consent ─────────────────────────────────────────────

    func testCloudProviderThrowsConsentErrorWhenNotGranted() async throws {
        let provider = CloudProvider(target: .anthropic, modelName: "claude-3", consentGranted: false)
        do {
            _ = try await provider.summarize(prompt: "hello", meetingId: UUID())
            XCTFail("Expected consent error")
        } catch PipelineError.summarizeCloudConsentNotGranted {
            // expected
        }
    }

    // ── 8. SummarizeConfiguration defaults ───────────────────────────────────

    func testConfigDefaultMaxRetries() {
        XCTAssertEqual(SummarizeConfiguration.default.maxRetries, 3)
    }

    func testConfigDefaultProviderIsLocal() {
        XCTAssertEqual(SummarizeConfiguration.default.provider, .local)
    }
}
