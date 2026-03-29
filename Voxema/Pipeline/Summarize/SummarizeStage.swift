import Foundation

/// Summarize stage stub.
/// Full implementation pending (LocalProvider llama.cpp + CloudProvider URLSession).
public final class SummarizeStage: SummarizeStageProtocol {

    private let log = VoxemaLogger.make(category: "summarize")

    public init() {}

    public func run(_ segments: [DiarizedSegment]) async throws -> MeetingSummary {
        log.info("SummarizeStage.run — stub, not yet implemented")
        throw PipelineError.summarizeMalformedOutput
    }

    public func cancel() {
        log.info("SummarizeStage.cancel — stub")
    }
}
