import Foundation
import Combine

/// Orchestrates the five pipeline stages sequentially.
///
/// ## Stage execution order
/// ```
/// Capture → Transcribe → Diarize → Summarize → Export
/// ```
///
/// ## Cross-stage rules enforced (from `docs/PIPELINE_CONTRACTS.md`)
/// 1. Stages receive immutable input and produce new output — no in-place mutation
/// 2. Stages do not call each other — all calls route through `PipelineCoordinator`
/// 3. Errors raised at stage boundaries as typed `PipelineError`
/// 4. Error messages never contain transcript text, audio content, or PII
/// 5. Models loaded only during their stage, unloaded after (8 GB discipline)
///
/// ## Thread safety
/// All state is `@MainActor`-isolated. Stage `run()` methods are `async` and may
/// execute on any executor; results are delivered back on the main actor.
@MainActor
public final class PipelineCoordinator: ObservableObject {

    // MARK: - Published State

    @Published public private(set) var state: PipelineState = .idle
    @Published public private(set) var progress: PipelineProgress = .initial

    // MARK: - Dependencies

    private let captureStage:    any CaptureStageProtocol
    private let transcribeStage: any TranscribeStageProtocol
    private let diarizeStage:    any DiarizeStageProtocol
    private let summarizeStage:  any SummarizeStageProtocol
    private let exportStage:     any ExportStageProtocol
    private let modelManager:    ModelManager

    private let log = VoxemaLogger.make(category: "pipeline")

    // MARK: - Init

    /// Designated initialiser. All stage dependencies are injected for production and testing.
    public init(
        captureStage:    any CaptureStageProtocol,
        transcribeStage: any TranscribeStageProtocol,
        diarizeStage:    any DiarizeStageProtocol,
        summarizeStage:  any SummarizeStageProtocol,
        exportStage:     any ExportStageProtocol,
        modelManager:    ModelManager = .shared
    ) {
        self.captureStage    = captureStage
        self.transcribeStage = transcribeStage
        self.diarizeStage    = diarizeStage
        self.summarizeStage  = summarizeStage
        self.exportStage     = exportStage
        self.modelManager    = modelManager
    }

    // MARK: - Recording Lifecycle

    /// Starts audio capture. Transitions from `.idle` to `.recording`.
    /// Calling when not `.idle` is a no-op.
    public func startRecording() async throws {
        guard state == .idle else {
            log.warning("startRecording called in non-idle state")
            return
        }
        log.info("pipeline recording starting")
        state = .recording
        do {
            try await captureStage.startCapture()
        } catch {
            let err = asPipelineError(error, fallback: .captureMicrophonePermissionDenied)
            state = .failed(err)
            throw err
        }
    }

    /// Stops capture and runs Transcribe → Diarize → Summarize → Export.
    /// Calling when not `.recording` is a no-op.
    public func stopRecording() async throws {
        guard state == .recording else {
            log.warning("stopRecording called in non-recording state")
            return
        }
        log.info("pipeline capture stopping")
        state = .stopping
        let streams: [AudioStream]
        do {
            streams = try await captureStage.stopCapture()
        } catch {
            let err = asPipelineError(error, fallback: .captureDiskSpaceInsufficient)
            state = .failed(err)
            throw err
        }
        try await runProcessingPipeline(streams: streams)
    }

    // MARK: - Cancellation

    /// Cancels the active stage and transitions to `.cancelled`.
    /// No-op if already idle, complete, cancelled, or failed.
    public func cancel() {
        switch state {
        case .idle, .complete, .cancelled, .failed:
            return
        case .recording, .stopping:
            captureStage.cancel()
        case .processing:
            transcribeStage.cancel()
            diarizeStage.cancel()
            summarizeStage.cancel()
            exportStage.cancel()
        }
        log.info("pipeline cancelled")
        state = .cancelled
        progress = .initial
    }

    /// Resets a terminal state (`.failed`, `.complete`, `.cancelled`) back to `.idle`.
    /// Calling from a non-terminal state is a no-op.
    public func reset() {
        switch state {
        case .failed, .complete, .cancelled:
            log.info("pipeline reset to idle")
            state = .idle
            progress = .initial
        default:
            log.warning("reset called in non-terminal state")
        }
    }

    // MARK: - Processing Pipeline

    private func runProcessingPipeline(streams: [AudioStream]) async throws {

        // ── Transcribe ──────────────────────────────────────────────────
        log.info("stage transcribe starting")
        updateProgress(.transcribing(progress: 0))
        let segments: [TranscribedSegment]
        do {
            segments = try await transcribeStage.run(streams)
        } catch {
            let err = asPipelineError(error, fallback: .transcribeAudioFileCorrupt)
            state = .failed(err); throw err
        }
        log.info("stage transcribe complete", "segments=\(segments.count)")

        // ── Diarize ─────────────────────────────────────────────────────
        log.info("stage diarize starting")
        updateProgress(.diarizing(progress: 0))
        let diarized: [DiarizedSegment]
        do {
            diarized = try await diarizeStage.run(segments, audioStreams: streams)
        } catch {
            let err = asPipelineError(error, fallback: .diarizeAllSegmentsBelowThreshold)
            state = .failed(err); throw err
        }
        log.info("stage diarize complete", "segments=\(diarized.count)")

        // ── Summarize ────────────────────────────────────────────────────
        log.info("stage summarize starting")
        updateProgress(.summarizing(progress: 0))
        let summary: MeetingSummary
        do {
            summary = try await summarizeStage.run(diarized)
        } catch {
            let err = asPipelineError(error, fallback: .summarizeMalformedOutput)
            state = .failed(err); throw err
        }
        log.info("stage summarize complete")

        // ── Export ───────────────────────────────────────────────────────
        log.info("stage export starting")
        updateProgress(.exporting(progress: 0))
        let metadata = buildMetadata(segments: segments, summary: summary)
        let meeting: Meeting
        do {
            meeting = try await exportStage.run(
                ExportStageInput(segments: diarized, summary: summary, metadata: metadata)
            )
        } catch {
            let err = asPipelineError(error, fallback: .exportDatabaseWriteFailure)
            state = .failed(err); throw err
        }
        log.info("stage export complete")

        log.info("pipeline complete")
        state = .complete(meetingId: meeting.meetingId)
        progress = PipelineProgress(currentStage: nil, overallFraction: 1.0)
    }

    // MARK: - Helpers

    private func updateProgress(_ stage: PipelineProcessingStage) {
        progress = .from(stage: stage)
        state = .processing(stage)
    }

    private func asPipelineError(_ error: Error, fallback: PipelineError) -> PipelineError {
        (error as? PipelineError) ?? fallback
    }

    private func buildMetadata(segments: [TranscribedSegment], summary: MeetingSummary) -> MeetingMetadata {
        let wordCount = segments.reduce(0) { $0 + $1.text.split(separator: " ").count }
        let bundledWhisper = modelManager.manifest.models
            .first { $0.family == .whisper && $0.isBundled }?.id ?? "whisper-tiny"
        return MeetingMetadata(
            whisperModel: bundledWhisper,
            summaryProvider: summary.providerUsed.rawValue,
            languageDetected: segments.first?.language ?? "unknown",
            segmentCount: segments.count,
            wordCount: wordCount
        )
    }
}
