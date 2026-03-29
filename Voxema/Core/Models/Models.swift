import Foundation

// MARK: - Audio Channel

/// Identifies which audio channel a stream or segment belongs to.
/// Raw values match the string literals defined in PIPELINE_CONTRACTS.md.
public enum AudioChannel: String, Codable, Equatable, Hashable, Sendable {
    case local  = "local"   // user's microphone
    case remote = "remote"  // system audio (remote participants)
}

// MARK: - Stage 1: Capture output

/// A captured audio stream produced by the Capture stage.
/// Corresponds to `AudioStream` in PIPELINE_CONTRACTS.md.
public struct AudioStream: Codable, Equatable, Hashable, Sendable {
    public let streamId: UUID
    public let channel: AudioChannel
    /// Always "PCM 16kHz mono" at MVP (Whisper.cpp input format).
    public let format: String
    /// Encrypted temporary file path on disk. Never transmitted.
    public let filePath: String
    public let durationSeconds: Float
    public let deviceName: String
    public let recordedAt: Date

    public init(
        streamId: UUID = UUID(),
        channel: AudioChannel,
        format: String = "PCM 16kHz mono",
        filePath: String,
        durationSeconds: Float,
        deviceName: String,
        recordedAt: Date = Date()
    ) {
        self.streamId = streamId
        self.channel = channel
        self.format = format
        self.filePath = filePath
        self.durationSeconds = durationSeconds
        self.deviceName = deviceName
        self.recordedAt = recordedAt
    }

    enum CodingKeys: String, CodingKey {
        case streamId = "stream_id"
        case channel
        case format
        case filePath = "file_path"
        case durationSeconds = "duration_seconds"
        case deviceName = "device_name"
        case recordedAt = "recorded_at"
    }
}

// MARK: - Stage 2: Transcribe output

/// A timestamped text segment produced by the Transcribe stage.
/// Corresponds to `TranscribedSegment` in PIPELINE_CONTRACTS.md.
public struct TranscribedSegment: Codable, Equatable, Hashable, Sendable {
    public let segmentId: UUID
    public let channel: AudioChannel
    /// Seconds from recording start.
    public let startTime: Float
    public let endTime: Float
    public let text: String
    /// BCP-47 language code detected by Whisper.
    public let language: String
    /// Whisper confidence score in range 0.0–1.0.
    public let confidence: Float

    public init(
        segmentId: UUID = UUID(),
        channel: AudioChannel,
        startTime: Float,
        endTime: Float,
        text: String,
        language: String,
        confidence: Float
    ) {
        self.segmentId = segmentId
        self.channel = channel
        self.startTime = startTime
        self.endTime = endTime
        self.text = text
        self.language = language
        self.confidence = confidence
    }

    enum CodingKeys: String, CodingKey {
        case segmentId = "segment_id"
        case channel
        case startTime = "start_time"
        case endTime = "end_time"
        case text
        case language
        case confidence
    }
}

// MARK: - Stage 3: Diarize output

/// Resolved speaker identity produced during the Diarize stage.
/// Corresponds to `SpeakerIdentity` in PIPELINE_CONTRACTS.md.
public struct SpeakerIdentity: Codable, Equatable, Hashable, Sendable {
    public let speakerId: UUID
    /// User-assigned name or temporary label ("Speaker A", "Speaker B", …).
    public let label: String
    /// True for the local-channel speaker (always the app user).
    public let isUser: Bool
    /// Cosine similarity score from voice profile matching (0.0–1.0).
    public let confidence: Float
    /// True when matched against a stored voice profile.
    public let isKnown: Bool

    public init(
        speakerId: UUID = UUID(),
        label: String,
        isUser: Bool,
        confidence: Float,
        isKnown: Bool
    ) {
        self.speakerId = speakerId
        self.label = label
        self.isUser = isUser
        self.confidence = confidence
        self.isKnown = isKnown
    }

    enum CodingKeys: String, CodingKey {
        case speakerId = "speaker_id"
        case label
        case isUser = "is_user"
        case confidence
        case isKnown = "is_known"
    }
}

/// A speaker-attributed transcript segment produced by the Diarize stage.
/// `segmentId` is the same UUID as the corresponding `TranscribedSegment`.
/// Corresponds to `DiarizedSegment` in PIPELINE_CONTRACTS.md.
public struct DiarizedSegment: Codable, Equatable, Hashable, Sendable {
    /// Matches `TranscribedSegment.segmentId` for the source segment.
    public let segmentId: UUID
    public let startTime: Float
    public let endTime: Float
    public let text: String
    public let speaker: SpeakerIdentity
    public let channel: AudioChannel

    public init(
        segmentId: UUID,
        startTime: Float,
        endTime: Float,
        text: String,
        speaker: SpeakerIdentity,
        channel: AudioChannel
    ) {
        self.segmentId = segmentId
        self.startTime = startTime
        self.endTime = endTime
        self.text = text
        self.speaker = speaker
        self.channel = channel
    }

    enum CodingKeys: String, CodingKey {
        case segmentId = "segment_id"
        case startTime = "start_time"
        case endTime = "end_time"
        case text
        case speaker
        case channel
    }
}

// MARK: - Stage 4: Summarize output

/// An extracted action item from the meeting summary.
/// Corresponds to `ActionItem` in PIPELINE_CONTRACTS.md.
public struct ActionItem: Codable, Equatable, Hashable, Sendable {
    /// Maps to JSON key "description". Named actionDescription to avoid clash with CustomStringConvertible.
    public let actionDescription: String
    /// Speaker label if the assignee was identifiable from the transcript.
    public let assignee: String?
    /// Deadline extracted from the conversation, if mentioned.
    public let deadline: String?

    public init(actionDescription: String, assignee: String? = nil, deadline: String? = nil) {
        self.actionDescription = actionDescription
        self.assignee = assignee
        self.deadline = deadline
    }

    enum CodingKeys: String, CodingKey {
        case actionDescription = "description"
        case assignee
        case deadline
    }
}

/// Identifies which summarization provider was used to generate a summary.
/// Raw values match the `provider_used` literals in PIPELINE_CONTRACTS.md.
public enum ProviderType: String, Codable, Equatable, Hashable, Sendable {
    case local  = "local"
    case cloud  = "cloud"
    case onPrem = "on_prem"
}

/// Structured meeting summary produced by the Summarize stage.
/// Corresponds to `MeetingSummary` in PIPELINE_CONTRACTS.md.
public struct MeetingSummary: Codable, Equatable, Hashable, Sendable {
    public let meetingId: UUID
    public let summaryText: String
    public let keyDecisions: [String]
    public let actionItems: [ActionItem]
    public let openQuestions: [String]
    public let providerUsed: ProviderType
    public let modelName: String
    public let generatedAt: Date

    public init(
        meetingId: UUID,
        summaryText: String,
        keyDecisions: [String] = [],
        actionItems: [ActionItem] = [],
        openQuestions: [String] = [],
        providerUsed: ProviderType,
        modelName: String,
        generatedAt: Date = Date()
    ) {
        self.meetingId = meetingId
        self.summaryText = summaryText
        self.keyDecisions = keyDecisions
        self.actionItems = actionItems
        self.openQuestions = openQuestions
        self.providerUsed = providerUsed
        self.modelName = modelName
        self.generatedAt = generatedAt
    }

    enum CodingKeys: String, CodingKey {
        case meetingId = "meeting_id"
        case summaryText = "summary_text"
        case keyDecisions = "key_decisions"
        case actionItems = "action_items"
        case openQuestions = "open_questions"
        case providerUsed = "provider_used"
        case modelName = "model_name"
        case generatedAt = "generated_at"
    }
}

// MARK: - Stage 5: Export output

/// Processing metadata attached to a persisted meeting record.
/// Corresponds to `MeetingMetadata` in PIPELINE_CONTRACTS.md.
public struct MeetingMetadata: Codable, Equatable, Hashable, Sendable {
    public let whisperModel: String
    public let summaryProvider: String
    public let languageDetected: String
    public let segmentCount: Int
    public let wordCount: Int

    public init(
        whisperModel: String,
        summaryProvider: String,
        languageDetected: String,
        segmentCount: Int,
        wordCount: Int
    ) {
        self.whisperModel = whisperModel
        self.summaryProvider = summaryProvider
        self.languageDetected = languageDetected
        self.segmentCount = segmentCount
        self.wordCount = wordCount
    }

    enum CodingKeys: String, CodingKey {
        case whisperModel = "whisper_model"
        case summaryProvider = "summary_provider"
        case languageDetected = "language_detected"
        case segmentCount = "segment_count"
        case wordCount = "word_count"
    }
}

/// Top-level entity representing a single recorded and processed meeting.
/// Corresponds to `Meeting` in PIPELINE_CONTRACTS.md.
public struct Meeting: Codable, Equatable, Hashable, Sendable {
    public let meetingId: UUID
    public let title: String
    public let recordedAt: Date
    public let durationSeconds: Float
    public let transcript: [DiarizedSegment]
    /// `nil` before summarization runs or when summarization has failed.
    public let summary: MeetingSummary?
    public let speakers: [SpeakerIdentity]
    /// True after temporary audio files have been deleted.
    public let audioDeleted: Bool
    public let metadata: MeetingMetadata

    public init(
        meetingId: UUID = UUID(),
        title: String,
        recordedAt: Date = Date(),
        durationSeconds: Float,
        transcript: [DiarizedSegment] = [],
        summary: MeetingSummary? = nil,
        speakers: [SpeakerIdentity] = [],
        audioDeleted: Bool = false,
        metadata: MeetingMetadata
    ) {
        self.meetingId = meetingId
        self.title = title
        self.recordedAt = recordedAt
        self.durationSeconds = durationSeconds
        self.transcript = transcript
        self.summary = summary
        self.speakers = speakers
        self.audioDeleted = audioDeleted
        self.metadata = metadata
    }

    enum CodingKeys: String, CodingKey {
        case meetingId = "meeting_id"
        case title
        case recordedAt = "recorded_at"
        case durationSeconds = "duration_seconds"
        case transcript
        case summary
        case speakers
        case audioDeleted = "audio_deleted"
        case metadata
    }
}

// MARK: - Pipeline Errors

/// Typed errors raised at pipeline stage boundaries.
///
/// Error messages must never contain transcript text, audio content,
/// speaker names from recordings, or any PII. This is a hard privacy constraint.
public enum PipelineError: Error, LocalizedError, Equatable, Sendable {

    // MARK: Capture
    case captureScreenRecordingPermissionDenied
    case captureMicrophonePermissionDenied
    case captureDeviceDisconnected(deviceName: String)
    case captureDiskSpaceInsufficient

    // MARK: Transcribe
    case transcribeModelNotFound(modelName: String)
    case transcribeModelCorrupt(modelName: String)
    case transcribeAudioFileCorrupt
    case transcribeAudioFileEmpty
    case transcribeInsufficientMemory(requiredGB: Float, availableGB: Float)

    // MARK: Diarize
    case diarizeEmbeddingModelNotFound
    case diarizeVoiceProfileDatabaseCorrupt
    case diarizeAllSegmentsBelowThreshold

    // MARK: Summarize
    case summarizeLocalModelTooLargeForRAM(modelName: String, requiredGB: Float)
    case summarizeCloudAPIError(statusCode: Int)
    case summarizeCloudConsentNotGranted
    case summarizeOnPremEndpointUnreachable
    case summarizeMalformedOutput
    case summarizeMaxRetriesExceeded(retries: Int)

    // MARK: Export
    case exportDatabaseWriteFailure
    case exportFileWriteFailure
    case exportDiskSpaceInsufficient

    public var errorDescription: String? {
        switch self {
        case .captureScreenRecordingPermissionDenied:
            return "[capture] Screen Recording permission required. Grant it in System Settings → Privacy & Security → Screen Recording."
        case .captureMicrophonePermissionDenied:
            return "[capture] Microphone permission required. Grant it in System Settings → Privacy & Security → Microphone."
        case .captureDeviceDisconnected(let deviceName):
            return "[capture] Audio device '\(deviceName)' disconnected during recording."
        case .captureDiskSpaceInsufficient:
            return "[capture] Insufficient disk space to continue recording."

        case .transcribeModelNotFound(let modelName):
            return "[transcribe] Model '\(modelName)' not found. Re-download it from Settings."
        case .transcribeModelCorrupt(let modelName):
            return "[transcribe] Model '\(modelName)' appears corrupt. Re-download it from Settings."
        case .transcribeAudioFileCorrupt:
            return "[transcribe] The captured audio file could not be read."
        case .transcribeAudioFileEmpty:
            return "[transcribe] The captured audio file contains no data."
        case .transcribeInsufficientMemory(let required, let available):
            return "[transcribe] Insufficient memory (required \(String(format: "%.1f", required)) GB, available \(String(format: "%.1f", available)) GB)."

        case .diarizeEmbeddingModelNotFound:
            return "[diarize] Speaker embedding model not found. Re-download it from Settings."
        case .diarizeVoiceProfileDatabaseCorrupt:
            return "[diarize] Voice profile database appears corrupt. A fresh database has been initialized."
        case .diarizeAllSegmentsBelowThreshold:
            return "[diarize] Speaker confidence too low. Temporary labels have been assigned."

        case .summarizeLocalModelTooLargeForRAM(let modelName, let required):
            return "[summarize] Model '\(modelName)' requires \(String(format: "%.1f", required)) GB RAM."
        case .summarizeCloudAPIError(let statusCode):
            return "[summarize] Cloud API returned error (status \(statusCode))."
        case .summarizeCloudConsentNotGranted:
            return "[summarize] Cloud summarization requires consent. Please confirm in the summary dialog."
        case .summarizeOnPremEndpointUnreachable:
            return "[summarize] On-premise endpoint could not be reached."
        case .summarizeMalformedOutput:
            return "[summarize] The model returned output that could not be parsed."
        case .summarizeMaxRetriesExceeded(let retries):
            return "[summarize] Summarization failed after \(retries) attempts."

        case .exportDatabaseWriteFailure:
            return "[export] Failed to save meeting to the database."
        case .exportFileWriteFailure:
            return "[export] Failed to write export file."
        case .exportDiskSpaceInsufficient:
            return "[export] Insufficient disk space to export the meeting."
        }
    }
}
