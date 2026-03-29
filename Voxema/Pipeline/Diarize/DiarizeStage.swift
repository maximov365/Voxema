import Foundation

/// Diarize stage stub.
/// Full implementation pending (ECAPA-TDNN ONNX Runtime integration).
public final class DiarizeStage: DiarizeStageProtocol {

    private let log = VoxemaLogger.make(category: "diarize")

    public init() {}

    public func run(_ segments: [TranscribedSegment]) async throws -> [DiarizedSegment] {
        log.info("DiarizeStage.run — stub, not yet implemented")
        throw PipelineError.diarizeEmbeddingModelNotFound
    }

    public func cancel() {
        log.info("DiarizeStage.cancel — stub")
    }
}
