import XCTest
import Combine
@testable import Voxema

// MARK: - Mock Stages

private final class MockCaptureStage: CaptureStageProtocol {
    var startError: PipelineError?
    var stopError: PipelineError?
    var returnedStreams: [AudioStream] = []
    private(set) var cancelCalled = false

    func startCapture() async throws {
        if let err = startError { throw err }
    }
    func stopCapture() async throws -> [AudioStream] {
        if let err = stopError { throw err }
        return returnedStreams
    }
    func cancel() { cancelCalled = true }
}

private final class MockTranscribeStage: TranscribeStageProtocol {
    var error: PipelineError?
    var result: [TranscribedSegment] = []
    private(set) var cancelCalled = false

    func run(_ streams: [AudioStream]) async throws -> [TranscribedSegment] {
        if let err = error { throw err }
        return result
    }
    func cancel() { cancelCalled = true }
}

private final class MockDiarizeStage: DiarizeStageProtocol {
    var error: PipelineError?
    var result: [DiarizedSegment] = []
    private(set) var cancelCalled = false

    func run(_ segments: [TranscribedSegment]) async throws -> [DiarizedSegment] {
        if let err = error { throw err }
        return result
    }
    func cancel() { cancelCalled = true }
}

private final class MockSummarizeStage: SummarizeStageProtocol {
    var error: PipelineError?
    var result: MeetingSummary = MeetingSummary(
        meetingId: UUID(),
        summaryText: "stub",
        providerUsed: .local,
        modelName: "stub"
    )
    private(set) var cancelCalled = false

    func run(_ segments: [DiarizedSegment]) async throws -> MeetingSummary {
        if let err = error { throw err }
        return result
    }
    func cancel() { cancelCalled = true }
}

private final class MockExportStage: ExportStageProtocol {
    var error: PipelineError?
    var result: Meeting = Meeting(
        meetingId: UUID(),
        title: "Stub Meeting",
        recordedAt: Date(),
        durationSeconds: 0,
        transcript: [],
        summary: nil,
        speakers: [],
        audioDeleted: false,
        metadata: MeetingMetadata(
            whisperModel: "whisper-tiny",
            summaryProvider: "local",
            languageDetected: "en",
            segmentCount: 0,
            wordCount: 0
        )
    )
    private(set) var cancelCalled = false

    func run(_ input: ExportStageInput) async throws -> Meeting {
        if let err = error { throw err }
        return result
    }
    func cancel() { cancelCalled = true }
}

// MARK: - Test Helpers

@MainActor
private func makeCoordinator(
    capture:    MockCaptureStage    = MockCaptureStage(),
    transcribe: MockTranscribeStage = MockTranscribeStage(),
    diarize:    MockDiarizeStage    = MockDiarizeStage(),
    summarize:  MockSummarizeStage  = MockSummarizeStage(),
    export:     MockExportStage     = MockExportStage()
) throws -> PipelineCoordinator {
    let manifest = try ModelManifest.decode(from: """
    {"version":"1.0.0","models":[
      {"id":"whisper-tiny","name":"Whisper Tiny","family":"whisper","variant":"tiny",
       "size_bytes":1,"sha256":"x","ram_gb":0.2,"tier":null,
       "download_url":"https://example.com/t.bin","is_bundled":true,"description":""}
    ]}
    """.data(using: .utf8)!)
    let manager = ModelManager(
        manifest: manifest,
        modelsDirectory: FileManager.default.temporaryDirectory.appendingPathComponent("mmtest-\(UUID())")
    )
    return PipelineCoordinator(
        captureStage: capture,
        transcribeStage: transcribe,
        diarizeStage: diarize,
        summarizeStage: summarize,
        exportStage: export,
        modelManager: manager
    )
}

// MARK: - Tests

@MainActor
final class PipelineCoordinatorTests: XCTestCase {

    // MARK: - Initial State

    func testInitialStateIsIdle() throws {
        let coord = try makeCoordinator()
        XCTAssertEqual(coord.state, .idle)
        XCTAssertEqual(coord.progress, .initial)
    }

    // MARK: - startRecording

    func testStartRecordingTransitionsToRecording() async throws {
        let coord = try makeCoordinator()
        try await coord.startRecording()
        XCTAssertEqual(coord.state, .recording)
    }

    func testStartRecordingIsNoOpWhenNotIdle() async throws {
        let capture = MockCaptureStage()
        let coord = try makeCoordinator(capture: capture)
        try await coord.startRecording()          // → .recording
        XCTAssertEqual(coord.state, .recording)
        try await coord.startRecording()          // no-op
        XCTAssertEqual(coord.state, .recording)
    }

    func testStartRecordingFailureTransitionsToFailed() async throws {
        let capture = MockCaptureStage()
        capture.startError = .captureScreenRecordingPermissionDenied
        let coord = try makeCoordinator(capture: capture)
        do {
            try await coord.startRecording()
            XCTFail("Expected throw")
        } catch {}
        XCTAssertEqual(coord.state, .failed(.captureScreenRecordingPermissionDenied))
    }

    // MARK: - stopRecording

    func testStopRecordingIsNoOpWhenNotRecording() async throws {
        let coord = try makeCoordinator()
        // state is .idle — no-op
        try await coord.stopRecording()
        XCTAssertEqual(coord.state, .idle)
    }

    func testStopRecordingCaptureFaultTransitionsToFailed() async throws {
        let capture = MockCaptureStage()
        capture.stopError = .captureDiskSpaceInsufficient
        let coord = try makeCoordinator(capture: capture)
        try await coord.startRecording()
        do {
            try await coord.stopRecording()
            XCTFail("Expected throw")
        } catch {}
        XCTAssertEqual(coord.state, .failed(.captureDiskSpaceInsufficient))
    }

    // MARK: - Full happy path

    func testFullPipelineCompletesSuccessfully() async throws {
        let capture    = MockCaptureStage()
        let export     = MockExportStage()
        let expectedId = export.result.meetingId

        let coord = try makeCoordinator(
            capture: capture,
            export: export
        )
        try await coord.startRecording()
        try await coord.stopRecording()

        XCTAssertEqual(coord.state, .complete(meetingId: expectedId))
        XCTAssertEqual(coord.progress.overallFraction, 1.0, accuracy: 0.001)
    }

    // MARK: - Stage error propagation

    func testTranscribeErrorTransitionsToFailed() async throws {
        let capture    = MockCaptureStage()
        let transcribe = MockTranscribeStage()
        transcribe.error = .transcribeModelNotFound(modelName: "whisper-small")

        let coord = try makeCoordinator(capture: capture, transcribe: transcribe)
        try await coord.startRecording()
        do {
            try await coord.stopRecording()
            XCTFail("Expected throw")
        } catch {}
        XCTAssertEqual(coord.state, .failed(.transcribeModelNotFound(modelName: "whisper-small")))
    }

    func testDiarizeErrorTransitionsToFailed() async throws {
        let capture = MockCaptureStage()
        let diarize = MockDiarizeStage()
        diarize.error = .diarizeEmbeddingModelNotFound

        let coord = try makeCoordinator(capture: capture, diarize: diarize)
        try await coord.startRecording()
        do {
            try await coord.stopRecording()
            XCTFail("Expected throw")
        } catch {}
        XCTAssertEqual(coord.state, .failed(.diarizeEmbeddingModelNotFound))
    }

    func testSummarizeErrorTransitionsToFailed() async throws {
        let capture   = MockCaptureStage()
        let summarize = MockSummarizeStage()
        summarize.error = .summarizeCloudConsentNotGranted

        let coord = try makeCoordinator(capture: capture, summarize: summarize)
        try await coord.startRecording()
        do {
            try await coord.stopRecording()
            XCTFail("Expected throw")
        } catch {}
        XCTAssertEqual(coord.state, .failed(.summarizeCloudConsentNotGranted))
    }

    func testExportErrorTransitionsToFailed() async throws {
        let capture = MockCaptureStage()
        let export  = MockExportStage()
        export.error = .exportDatabaseWriteFailure

        let coord = try makeCoordinator(capture: capture, export: export)
        try await coord.startRecording()
        do {
            try await coord.stopRecording()
            XCTFail("Expected throw")
        } catch {}
        XCTAssertEqual(coord.state, .failed(.exportDatabaseWriteFailure))
    }

    // MARK: - Cancellation

    func testCancelDuringRecordingCallsCaptureCancel() async throws {
        let capture = MockCaptureStage()
        let coord = try makeCoordinator(capture: capture)
        try await coord.startRecording()
        coord.cancel()
        XCTAssertEqual(coord.state, .cancelled)
        XCTAssertTrue(capture.cancelCalled)
    }

    func testCancelWhenIdleIsNoOp() throws {
        let coord = try makeCoordinator()
        coord.cancel()
        XCTAssertEqual(coord.state, .idle)
    }

    func testCancelWhenCompleteIsNoOp() async throws {
        let coord = try makeCoordinator(capture: MockCaptureStage())
        try await coord.startRecording()
        try await coord.stopRecording()
        guard case .complete = coord.state else { XCTFail("Expected complete"); return }
        coord.cancel()
        guard case .complete = coord.state else {
            XCTFail("cancel from .complete should be no-op"); return
        }
    }

    // MARK: - Reset

    func testResetFromFailedReturnsToIdle() async throws {
        let capture = MockCaptureStage()
        capture.startError = .captureMicrophonePermissionDenied
        let coord = try makeCoordinator(capture: capture)
        do { try await coord.startRecording() } catch {}
        XCTAssertEqual(coord.state, .failed(.captureMicrophonePermissionDenied))
        coord.reset()
        XCTAssertEqual(coord.state, .idle)
    }

    func testResetFromCompleteReturnsToIdle() async throws {
        let coord = try makeCoordinator(capture: MockCaptureStage())
        try await coord.startRecording()
        try await coord.stopRecording()
        guard case .complete = coord.state else { XCTFail(); return }
        coord.reset()
        XCTAssertEqual(coord.state, .idle)
        XCTAssertEqual(coord.progress, .initial)
    }

    func testResetWhenIdleIsNoOp() throws {
        let coord = try makeCoordinator()
        coord.reset() // should not crash
        XCTAssertEqual(coord.state, .idle)
    }

    // MARK: - PipelineProgress

    func testProgressFromStageCalculation() {
        // Stage 0 (transcribe) at 50% → overall = 0/4 + 0.5/4 = 0.125
        let p = PipelineProgress.from(stage: .transcribing(progress: 0.5))
        XCTAssertEqual(p.overallFraction, 0.125, accuracy: 0.001)
        XCTAssertEqual(p.currentStage, .transcribing(progress: 0.5))
    }

    func testProgressClampsToZeroToOne() {
        let p = PipelineProgress(currentStage: nil, overallFraction: 1.5)
        XCTAssertEqual(p.overallFraction, 1.0)
    }

    // MARK: - PipelineProcessingStage

    func testProcessingStageSortOrder() {
        XCTAssertEqual(PipelineProcessingStage.transcribing(progress: 0).index, 0)
        XCTAssertEqual(PipelineProcessingStage.diarizing(progress: 0).index,    1)
        XCTAssertEqual(PipelineProcessingStage.summarizing(progress: 0).index,  2)
        XCTAssertEqual(PipelineProcessingStage.exporting(progress: 0).index,    3)
    }

    func testProcessingStageProgressAccessor() {
        XCTAssertEqual(PipelineProcessingStage.transcribing(progress: 0.42).progress, 0.42, accuracy: 0.001)
        XCTAssertEqual(PipelineProcessingStage.exporting(progress: 0.99).progress,    0.99, accuracy: 0.001)
    }

    // MARK: - PipelineState equality

    func testPipelineStateEquality() {
        XCTAssertEqual(PipelineState.idle, .idle)
        XCTAssertEqual(PipelineState.recording, .recording)
        XCTAssertEqual(PipelineState.cancelled, .cancelled)
        let id = UUID()
        XCTAssertEqual(PipelineState.complete(meetingId: id), .complete(meetingId: id))
        XCTAssertNotEqual(PipelineState.complete(meetingId: id), .complete(meetingId: UUID()))
        XCTAssertEqual(PipelineState.failed(.exportDatabaseWriteFailure), .failed(.exportDatabaseWriteFailure))
        XCTAssertNotEqual(PipelineState.failed(.exportDatabaseWriteFailure), .failed(.exportFileWriteFailure))
    }
}
