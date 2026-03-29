import Foundation

/// Capture stage stub.
/// Full implementation in TASK-7 (ScreenCaptureKit + AVAudioEngine).
public final class CaptureStage: CaptureStageProtocol {

    private let log = VoxemaLogger.make(category: "capture")

    public init() {}

    public func startCapture() async throws {
        log.info("CaptureStage.startCapture — stub, not yet implemented")
        throw PipelineError.captureScreenRecordingPermissionDenied
    }

    public func stopCapture() async throws -> [AudioStream] {
        log.info("CaptureStage.stopCapture — stub, not yet implemented")
        throw PipelineError.captureDiskSpaceInsufficient
    }

    public func cancel() {
        log.info("CaptureStage.cancel — stub")
    }
}
