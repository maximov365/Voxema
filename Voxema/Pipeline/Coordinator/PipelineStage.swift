import Foundation

// MARK: - Stage Protocols

/// Contract for the Capture stage.
///
/// Capture differs from processing stages: it runs open-ended until the user stops recording.
/// `startCapture()` returns once capture is initialised; `stopCapture()` blocks until
/// all audio is flushed and returns exactly two streams (local + remote).
public protocol CaptureStageProtocol: AnyObject {
    /// Begins capturing system audio and microphone. Throws `PipelineError` on permission denial
    /// or device failure.
    func startCapture() async throws
    /// Stops capture, flushes buffers, encrypts temp files, and returns `[AudioStream]`
    /// (exactly one `.local` and one `.remote`).
    func stopCapture() async throws -> [AudioStream]
    /// Cancels an in-progress capture, discarding buffered data. Idempotent.
    func cancel()
}

/// Contract for the Transcribe stage.
public protocol TranscribeStageProtocol: AnyObject {
    func run(_ streams: [AudioStream]) async throws -> [TranscribedSegment]
    func cancel()
}

/// Contract for the Diarize stage.
public protocol DiarizeStageProtocol: AnyObject {
    func run(_ segments: [TranscribedSegment]) async throws -> [DiarizedSegment]
    func cancel()
}

/// Contract for the Summarize stage.
public protocol SummarizeStageProtocol: AnyObject {
    func run(_ segments: [DiarizedSegment]) async throws -> MeetingSummary
    func cancel()
}

/// Combined input to the Export stage.
/// Wraps the three inputs into a single value to keep the stage protocol uniform.
public struct ExportStageInput: Sendable {
    public let segments: [DiarizedSegment]
    public let summary: MeetingSummary?
    public let metadata: MeetingMetadata

    public init(segments: [DiarizedSegment], summary: MeetingSummary?, metadata: MeetingMetadata) {
        self.segments = segments
        self.summary = summary
        self.metadata = metadata
    }
}

/// Contract for the Export stage.
public protocol ExportStageProtocol: AnyObject {
    func run(_ input: ExportStageInput) async throws -> Meeting
    func cancel()
}

// MARK: - PipelineProcessingStage

/// The active post-capture processing stage, with per-stage 0.0–1.0 progress.
public enum PipelineProcessingStage: Equatable, Sendable {
    case transcribing(progress: Double)
    case diarizing(progress: Double)
    case summarizing(progress: Double)
    case exporting(progress: Double)

    /// Zero-indexed stage position used for overall progress calculation.
    public var index: Int {
        switch self {
        case .transcribing: return 0
        case .diarizing:    return 1
        case .summarizing:  return 2
        case .exporting:    return 3
        }
    }

    /// The 0.0–1.0 fraction for this stage.
    public var progress: Double {
        switch self {
        case .transcribing(let p), .diarizing(let p),
             .summarizing(let p), .exporting(let p):
            return p
        }
    }
}

// MARK: - PipelineState

/// The overall state of `PipelineCoordinator`.
public enum PipelineState: Equatable, Sendable {
    /// No active recording or processing.
    case idle
    /// Capture stage is active — recording in progress.
    case recording
    /// Capture is stopping — buffered audio being flushed and encrypted.
    case stopping
    /// Post-capture processing stage is active.
    case processing(PipelineProcessingStage)
    /// All stages completed successfully.
    case complete(meetingId: UUID)
    /// A stage raised an unrecoverable error. Reset the coordinator to retry.
    case failed(PipelineError)
    /// Processing was cancelled by the user.
    case cancelled
}

// MARK: - PipelineProgress

/// Progress summary for the UI processing indicator.
public struct PipelineProgress: Equatable, Sendable {
    /// The currently active processing stage (`nil` when recording, idle, or done).
    public let currentStage: PipelineProcessingStage?
    /// 0.0–1.0 composite fraction across all four processing stages.
    public let overallFraction: Double

    public static let initial = PipelineProgress(currentStage: nil, overallFraction: 0)

    public init(currentStage: PipelineProcessingStage?, overallFraction: Double) {
        self.currentStage = currentStage
        self.overallFraction = max(0, min(overallFraction, 1))
    }

    /// Builds progress from a stage's position and its internal progress fraction.
    static func from(stage: PipelineProcessingStage, stageCount: Int = 4) -> PipelineProgress {
        let weight = 1.0 / Double(stageCount)
        let completed = Double(stage.index) * weight
        let current = stage.progress * weight
        return PipelineProgress(
            currentStage: stage,
            overallFraction: completed + current
        )
    }
}
