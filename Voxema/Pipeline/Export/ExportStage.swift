import Foundation

/// Export stage stub.
/// Full implementation pending (GRDB SQLite persistence + file exporters).
public final class ExportStage: ExportStageProtocol {

    private let log = VoxemaLogger.make(category: "export")

    public init() {}

    public func run(_ input: ExportStageInput) async throws -> Meeting {
        log.info("ExportStage.run — stub, not yet implemented")
        throw PipelineError.exportDatabaseWriteFailure
    }

    public func cancel() {
        log.info("ExportStage.cancel — stub")
    }
}
