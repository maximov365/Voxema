import Foundation

// MARK: - ExportConfiguration

/// Configuration for the Export stage.
public struct ExportConfiguration: Sendable {
    /// Path to the SQLite database file.
    public let databasePath: String
    /// Directory where Markdown and JSON export files are written.
    public let exportsDirectory: URL

    public static let `default` = ExportConfiguration(
        databasePath: defaultDatabasePath(),
        exportsDirectory: defaultExportsDirectory()
    )

    public init(databasePath: String, exportsDirectory: URL) {
        self.databasePath     = databasePath
        self.exportsDirectory = exportsDirectory
    }

    private static func defaultDatabasePath() -> String {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("Voxema/meetings.db").path
    }

    private static func defaultExportsDirectory() -> URL {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("Voxema/Exports")
    }
}

// MARK: - MarkdownExporter

/// Pure-Swift Markdown renderer for a `Meeting` record.
public enum MarkdownExporter {

    /// Writes a `.md` file to `directory` and returns its URL.
    public static func export(_ meeting: Meeting, to directory: URL) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("\(meeting.meetingId).md")
        try render(meeting).write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    /// Returns the Markdown representation of `meeting` as a `String`.
    public static func render(_ meeting: Meeting) -> String {
        var md = "# \(meeting.title)\n\n"
        md += "**Date:** \(isoDate(meeting.recordedAt))  \n"
        md += "**Duration:** \(formatDuration(meeting.durationSeconds))\n\n"

        if let s = meeting.summary, !s.summaryText.isEmpty {
            md += "## Summary\n\n\(s.summaryText)\n\n"

            if !s.keyDecisions.isEmpty {
                md += "### Key Decisions\n\n"
                s.keyDecisions.forEach { md += "- \($0)\n" }
                md += "\n"
            }
            if !s.actionItems.isEmpty {
                md += "### Action Items\n\n"
                s.actionItems.forEach { item in
                    let owner = item.assignee ?? "Unknown"
                    let dl = item.deadline.map { " (by \($0))" } ?? ""
                    md += "- [\(owner)] \(item.actionDescription)\(dl)\n"
                }
                md += "\n"
            }
            if !s.openQuestions.isEmpty {
                md += "### Open Questions\n\n"
                s.openQuestions.forEach { md += "- \($0)\n" }
                md += "\n"
            }
        }

        if !meeting.transcript.isEmpty {
            md += "## Transcript\n\n"
            meeting.transcript.forEach { seg in
                let start = formatTime(seg.startTime)
                let end   = formatTime(seg.endTime)
                md += "[\(start)-\(end)] **\(seg.speaker.label)**: \(seg.text)\n"
            }
        }

        return md
    }

    private static func isoDate(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        return f.string(from: date)
    }

    private static func formatDuration(_ s: Float) -> String {
        let m = Int(s) / 60; let sec = Int(s) % 60
        return "\(m)m \(sec)s"
    }

    private static func formatTime(_ s: Float) -> String {
        String(format: "%02d:%02d", Int(s) / 60, Int(s) % 60)
    }
}

// MARK: - JSONExporter

/// Pure-Swift JSON serialiser for a `Meeting` record.
public enum JSONExporter {

    /// Writes a `.json` file to `directory` and returns its URL.
    public static func export(_ meeting: Meeting, to directory: URL) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("\(meeting.meetingId).json")
        try render(meeting).write(to: url, options: .atomic)
        return url
    }

    /// Returns the JSON-encoded `Data` for `meeting` (pretty-printed, ISO-8601 dates).
    public static func render(_ meeting: Meeting) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting     = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(meeting)
    }
}

// MARK: - ExportStage

/// Persists the processed meeting to SQLite and deletes temporary audio files.
///
/// Audio deletion is performed **after** a successful database write.
/// If the database write fails, the `.enc` files are preserved so the user can retry.
public final class ExportStage: ExportStageProtocol {

    private let store: MeetingStore
    private let config: ExportConfiguration
    private let log = VoxemaLogger.make(category: "export.stage")
    private var isCancelled = false

    // MARK: - Init

    /// Convenience init — creates a `MeetingStore` at `config.databasePath`.
    public convenience init(config: ExportConfiguration = .default) throws {
        try self.init(store: MeetingStore(databasePath: config.databasePath), config: config)
    }

    init(store: MeetingStore, config: ExportConfiguration = .default) {
        self.store  = store
        self.config = config
    }

    // MARK: - ExportStageProtocol

    public func run(_ input: ExportStageInput) async throws -> Meeting {
        isCancelled = false
        let meeting = buildMeeting(from: input)

        // 1. Persist — must succeed before any destructive operation
        do {
            try store.save(meeting)
        } catch {
            log.error("ExportStage: database write failed")
            throw PipelineError.exportDatabaseWriteFailure
        }
        log.info("ExportStage: meeting saved")

        // 2. Delete temporary encrypted audio files (best-effort after successful DB write)
        for path in input.audioFilePaths {
            try? FileManager.default.removeItem(atPath: path)
        }
        if !input.audioFilePaths.isEmpty {
            log.info("ExportStage: audio files removed")
        }

        return meeting
    }

    public func cancel() {
        isCancelled = true
        log.info("ExportStage: cancelled")
    }

    // MARK: - Private

    private func buildMeeting(from input: ExportStageInput) -> Meeting {
        let duration = input.segments.map(\.endTime).max() ?? 0
        let uniqueSpeakers = Array(
            Dictionary(grouping: input.segments, by: { $0.speaker.speakerId })
                .values.compactMap(\.first?.speaker)
        )
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .short
        let title = "Meeting — \(dateFormatter.string(from: Date()))"

        return Meeting(
            title:          title,
            durationSeconds: duration,
            transcript:     input.segments,
            summary:        input.summary,
            speakers:       uniqueSpeakers,
            audioDeleted:   !input.audioFilePaths.isEmpty,
            metadata:       input.metadata
        )
    }
}
