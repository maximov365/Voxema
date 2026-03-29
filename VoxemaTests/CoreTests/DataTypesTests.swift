import XCTest
@testable import Voxema

final class DataTypesTests: XCTestCase {

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private func roundTrip<T: Codable & Equatable>(_ value: T) throws -> T {
        let data = try encoder.encode(value)
        return try decoder.decode(T.self, from: data)
    }

    // MARK: - AudioChannel

    func testAudioChannelRawValues() {
        XCTAssertEqual(AudioChannel.local.rawValue, "local")
        XCTAssertEqual(AudioChannel.remote.rawValue, "remote")
    }

    func testAudioChannelRoundTrip() throws {
        XCTAssertEqual(try roundTrip(AudioChannel.local), .local)
        XCTAssertEqual(try roundTrip(AudioChannel.remote), .remote)
    }

    // MARK: - AudioStream

    func testAudioStreamRoundTrip() throws {
        let value = AudioStream(
            streamId: UUID(),
            channel: .remote,
            format: "PCM 16kHz mono",
            filePath: "/tmp/test.pcm",
            durationSeconds: 42.5,
            deviceName: "MacBook Pro Microphone",
            recordedAt: Date(timeIntervalSince1970: 1_000_000)
        )
        XCTAssertEqual(try roundTrip(value), value)
    }

    func testAudioStreamCodingKeysAreSnakeCase() throws {
        let value = AudioStream(
            streamId: UUID(),
            channel: .local,
            filePath: "/tmp/a.pcm",
            durationSeconds: 1.0,
            deviceName: "Mic",
            recordedAt: Date(timeIntervalSince1970: 0)
        )
        let json = String(data: try encoder.encode(value), encoding: .utf8) ?? ""
        XCTAssertTrue(json.contains("\"stream_id\""), "Expected snake_case key, got: \(json)")
        XCTAssertTrue(json.contains("\"file_path\""))
        XCTAssertTrue(json.contains("\"duration_seconds\""))
        XCTAssertTrue(json.contains("\"device_name\""))
        XCTAssertTrue(json.contains("\"recorded_at\""))
    }

    func testAudioStreamDefaultFormat() {
        let value = AudioStream(channel: .local, filePath: "/tmp/a.pcm", durationSeconds: 1.0, deviceName: "Mic")
        XCTAssertEqual(value.format, "PCM 16kHz mono")
    }

    // MARK: - TranscribedSegment

    func testTranscribedSegmentRoundTrip() throws {
        let value = TranscribedSegment(
            segmentId: UUID(),
            channel: .remote,
            startTime: 0.5,
            endTime: 3.2,
            text: "Hello world",
            language: "en",
            confidence: 0.95
        )
        XCTAssertEqual(try roundTrip(value), value)
    }

    func testTranscribedSegmentSnakeCaseKeys() throws {
        let value = TranscribedSegment(channel: .local, startTime: 0, endTime: 1, text: "hi", language: "en", confidence: 0.9)
        let json = String(data: try encoder.encode(value), encoding: .utf8) ?? ""
        XCTAssertTrue(json.contains("\"segment_id\""))
        XCTAssertTrue(json.contains("\"start_time\""))
        XCTAssertTrue(json.contains("\"end_time\""))
    }

    // MARK: - SpeakerIdentity

    func testSpeakerIdentityRoundTrip() throws {
        let value = SpeakerIdentity(speakerId: UUID(), label: "Alice", isUser: false, confidence: 0.82, isKnown: true)
        XCTAssertEqual(try roundTrip(value), value)
    }

    func testSpeakerIdentitySnakeCaseKeys() throws {
        let value = SpeakerIdentity(label: "Bob", isUser: true, confidence: 1.0, isKnown: false)
        let json = String(data: try encoder.encode(value), encoding: .utf8) ?? ""
        XCTAssertTrue(json.contains("\"speaker_id\""))
        XCTAssertTrue(json.contains("\"is_user\""))
        XCTAssertTrue(json.contains("\"is_known\""))
    }

    // MARK: - DiarizedSegment

    func testDiarizedSegmentRoundTrip() throws {
        let speaker = SpeakerIdentity(label: "Speaker A", isUser: false, confidence: 0.78, isKnown: false)
        let value = DiarizedSegment(
            segmentId: UUID(),
            startTime: 1.0,
            endTime: 5.5,
            text: "This is a test",
            speaker: speaker,
            channel: .remote
        )
        XCTAssertEqual(try roundTrip(value), value)
    }

    // MARK: - ActionItem

    func testActionItemRoundTrip() throws {
        let value = ActionItem(actionDescription: "Send the report", assignee: "Bob", deadline: "Friday")
        XCTAssertEqual(try roundTrip(value), value)
    }

    func testActionItemNilFields() throws {
        let value = ActionItem(actionDescription: "No assignee")
        XCTAssertEqual(try roundTrip(value), value)
        XCTAssertNil(value.assignee)
        XCTAssertNil(value.deadline)
    }

    func testActionItemCodingKeyIsDescription() throws {
        let value = ActionItem(actionDescription: "Task X")
        let json = String(data: try encoder.encode(value), encoding: .utf8) ?? ""
        XCTAssertTrue(json.contains("\"description\""), "Expected JSON key 'description', got: \(json)")
    }

    // MARK: - ProviderType

    func testProviderTypeRawValues() {
        XCTAssertEqual(ProviderType.local.rawValue, "local")
        XCTAssertEqual(ProviderType.cloud.rawValue, "cloud")
        XCTAssertEqual(ProviderType.onPrem.rawValue, "on_prem")
    }

    // MARK: - MeetingSummary

    func testMeetingSummaryRoundTrip() throws {
        let action = ActionItem(actionDescription: "Follow up", assignee: "Charlie")
        let value = MeetingSummary(
            meetingId: UUID(),
            summaryText: "Discussed project timeline",
            keyDecisions: ["Extend deadline"],
            actionItems: [action],
            openQuestions: ["Who owns the release?"],
            providerUsed: .local,
            modelName: "qwen-2.5-3b-q4",
            generatedAt: Date(timeIntervalSince1970: 2_000_000)
        )
        XCTAssertEqual(try roundTrip(value), value)
    }

    func testMeetingSummarySnakeCaseKeys() throws {
        let value = MeetingSummary(meetingId: UUID(), summaryText: "x", providerUsed: .cloud, modelName: "m")
        let json = String(data: try encoder.encode(value), encoding: .utf8) ?? ""
        XCTAssertTrue(json.contains("\"meeting_id\""))
        XCTAssertTrue(json.contains("\"summary_text\""))
        XCTAssertTrue(json.contains("\"key_decisions\""))
        XCTAssertTrue(json.contains("\"action_items\""))
        XCTAssertTrue(json.contains("\"open_questions\""))
        XCTAssertTrue(json.contains("\"provider_used\""))
        XCTAssertTrue(json.contains("\"model_name\""))
        XCTAssertTrue(json.contains("\"generated_at\""))
    }

    // MARK: - MeetingMetadata

    func testMeetingMetadataRoundTrip() throws {
        let value = MeetingMetadata(
            whisperModel: "whisper-small",
            summaryProvider: "local",
            languageDetected: "en",
            segmentCount: 42,
            wordCount: 380
        )
        XCTAssertEqual(try roundTrip(value), value)
    }

    // MARK: - Meeting

    func testMeetingRoundTrip() throws {
        let metadata = MeetingMetadata(
            whisperModel: "whisper-tiny",
            summaryProvider: "local",
            languageDetected: "en",
            segmentCount: 3,
            wordCount: 20
        )
        let value = Meeting(
            meetingId: UUID(),
            title: "Sprint Planning",
            recordedAt: Date(timeIntervalSince1970: 3_000_000),
            durationSeconds: 3600.0,
            summary: nil,
            audioDeleted: false,
            metadata: metadata
        )
        XCTAssertEqual(try roundTrip(value), value)
    }

    func testMeetingSnakeCaseKeys() throws {
        let meta = MeetingMetadata(whisperModel: "w", summaryProvider: "l", languageDetected: "en", segmentCount: 0, wordCount: 0)
        let value = Meeting(title: "T", durationSeconds: 1.0, metadata: meta)
        let json = String(data: try encoder.encode(value), encoding: .utf8) ?? ""
        XCTAssertTrue(json.contains("\"meeting_id\""))
        XCTAssertTrue(json.contains("\"recorded_at\""))
        XCTAssertTrue(json.contains("\"duration_seconds\""))
        XCTAssertTrue(json.contains("\"audio_deleted\""))
    }

    // MARK: - PipelineError

    func testPipelineErrorCoversAllFiveStages() {
        let captureErrors: [PipelineError] = [
            .captureScreenRecordingPermissionDenied,
            .captureMicrophonePermissionDenied,
            .captureDiskSpaceInsufficient,
        ]
        let transcribeErrors: [PipelineError] = [
            .transcribeAudioFileCorrupt,
            .transcribeAudioFileEmpty,
        ]
        let diarizeErrors: [PipelineError] = [
            .diarizeEmbeddingModelNotFound,
            .diarizeVoiceProfileDatabaseCorrupt,
        ]
        let summarizeErrors: [PipelineError] = [
            .summarizeCloudConsentNotGranted,
            .summarizeMalformedOutput,
        ]
        let exportErrors: [PipelineError] = [
            .exportDatabaseWriteFailure,
            .exportFileWriteFailure,
            .exportDiskSpaceInsufficient,
        ]
        XCTAssertFalse(captureErrors.isEmpty)
        XCTAssertFalse(transcribeErrors.isEmpty)
        XCTAssertFalse(diarizeErrors.isEmpty)
        XCTAssertFalse(summarizeErrors.isEmpty)
        XCTAssertFalse(exportErrors.isEmpty)
    }

    func testPipelineErrorEquatability() {
        XCTAssertEqual(
            PipelineError.captureScreenRecordingPermissionDenied,
            PipelineError.captureScreenRecordingPermissionDenied
        )
        XCTAssertNotEqual(
            PipelineError.captureScreenRecordingPermissionDenied,
            PipelineError.captureMicrophonePermissionDenied
        )
        XCTAssertEqual(
            PipelineError.transcribeModelNotFound(modelName: "whisper-tiny"),
            PipelineError.transcribeModelNotFound(modelName: "whisper-tiny")
        )
        XCTAssertNotEqual(
            PipelineError.transcribeModelNotFound(modelName: "whisper-tiny"),
            PipelineError.transcribeModelNotFound(modelName: "whisper-small")
        )
    }

    func testPipelineErrorDescriptionIncludesStagePrefix() {
        XCTAssertTrue(PipelineError.captureScreenRecordingPermissionDenied.errorDescription?.hasPrefix("[capture]") == true)
        XCTAssertTrue(PipelineError.transcribeAudioFileCorrupt.errorDescription?.hasPrefix("[transcribe]") == true)
        XCTAssertTrue(PipelineError.diarizeEmbeddingModelNotFound.errorDescription?.hasPrefix("[diarize]") == true)
        XCTAssertTrue(PipelineError.summarizeMalformedOutput.errorDescription?.hasPrefix("[summarize]") == true)
        XCTAssertTrue(PipelineError.exportDatabaseWriteFailure.errorDescription?.hasPrefix("[export]") == true)
    }

    func testPipelineErrorDescriptionDoesNotContainContent() {
        let errors: [PipelineError] = [
            .captureScreenRecordingPermissionDenied,
            .transcribeAudioFileCorrupt,
            .diarizeEmbeddingModelNotFound,
            .summarizeMalformedOutput,
            .exportDatabaseWriteFailure,
        ]
        for error in errors {
            let description = error.errorDescription ?? ""
            XCTAssertFalse(
                description.lowercased().contains("content"),
                "errorDescription must not contain 'content' (privacy guard): \(description)"
            )
        }
    }

    // MARK: - VoxemaLogger

    func testLoggerMakeDoesNotCrash() {
        let logger = VoxemaLogger.make(category: "test")
        logger.info("test started")
        logger.debug("debug message", "stage=test")
        logger.warning("warning issued")
        logger.error("error occurred", "reason=test")
    }
}
