import Foundation

/// Transcribe stage stub.
/// Full implementation pending (Whisper.cpp Swift interop).
public final class TranscribeStage: TranscribeStageProtocol {

    private let log = VoxemaLogger.make(category: "transcribe")

    public init() {}

    public func run(_ streams: [AudioStream]) async throws -> [TranscribedSegment] {
        log.info("TranscribeStage.run — stub, not yet implemented")
        throw PipelineError.transcribeAudioFileEmpty
    }

    public func cancel() {
        log.info("TranscribeStage.cancel — stub")
    }
}
