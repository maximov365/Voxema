import Foundation
import GRDB

// MARK: - MeetingStore

/// Persists `Meeting` records in a local SQLite database via GRDB.
///
/// Schema uses a single `meetings` table that stores each meeting as a JSON
/// blob (`meetingData`) alongside a denormalized `searchText` column for
/// full-text substring search. FTS5 indexing is deferred to a future migration.
public final class MeetingStore {

    private let db: DatabaseQueue
    private let log = VoxemaLogger.make(category: "storage")

    // MARK: - Init

    /// Opens (or creates) the SQLite database at `databasePath` and runs migrations.
    public convenience init(databasePath: String) throws {
        // Ensure the parent directory exists
        let url = URL(fileURLWithPath: databasePath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let dbq = try DatabaseQueue(path: databasePath)
        try self.init(db: dbq)
    }

    /// Initialises with an existing `DatabaseQueue` — used for in-memory testing.
    init(db: DatabaseQueue) throws {
        self.db = db
        try runMigrations()
    }

    // MARK: - CRUD

    /// Persists a `Meeting`, replacing any existing record with the same `meetingId`.
    public func save(_ meeting: Meeting) throws {
        let row = try MeetingRow(meeting: meeting)
        try db.write { db in
            try row.save(db)
        }
    }

    /// Returns the `Meeting` with the given `id`, or `nil` if not found.
    public func fetch(id: UUID) throws -> Meeting? {
        let row = try db.read { db in
            try MeetingRow.fetchOne(db, key: id.uuidString)
        }
        return try row.map { try $0.toMeeting() }
    }

    /// Returns all meetings ordered by `recordedAt` descending (most recent first).
    public func fetchAll() throws -> [Meeting] {
        let rows = try db.read { db in
            try MeetingRow
                .order(Column("recordedAt").desc)
                .fetchAll(db)
        }
        return try rows.map { try $0.toMeeting() }
    }

    /// Returns meetings whose `searchText` contains `query` (case-insensitive).
    /// `searchText` covers: title + all transcript segment texts + summary text.
    public func search(_ query: String) throws -> [Meeting] {
        guard !query.isEmpty else { return try fetchAll() }
        let pattern = "%\(query)%"
        let rows = try db.read { db in
            try MeetingRow.fetchAll(db,
                sql: "SELECT * FROM meetings WHERE searchText LIKE ? ORDER BY recordedAt DESC",
                arguments: [pattern])
        }
        return try rows.map { try $0.toMeeting() }
    }

    /// Hard-deletes the meeting with the given `id`. This operation is irreversible.
    public func delete(id: UUID) throws {
        _ = try db.write { db in
            try MeetingRow.deleteOne(db, key: id.uuidString)
        }
    }

    /// Updates the `audioDeleted` flag to `true` for the given meeting.
    public func markAudioDeleted(id: UUID) throws {
        try db.write { db in
            try db.execute(
                sql: "UPDATE meetings SET audioDeleted = 1 WHERE meetingId = ?",
                arguments: [id.uuidString]
            )
        }
    }

    // MARK: - Migration

    private func runMigrations() throws {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1_initial") { db in
            try db.create(table: "meetings", ifNotExists: true) { t in
                t.primaryKey("meetingId", .text)
                t.column("title", .text).notNull()
                t.column("recordedAt", .double).notNull()
                t.column("durationSeconds", .double).notNull()
                t.column("audioDeleted", .boolean).notNull().defaults(to: false)
                t.column("meetingData", .blob).notNull()
                t.column("searchText", .text).notNull().defaults(to: "")
            }
        }

        try migrator.migrate(db)
        log.info("MeetingStore: migrations complete")
    }
}

// MARK: - MeetingRow (GRDB record)

private struct MeetingRow: FetchableRecord, PersistableRecord {
    static let databaseTableName = "meetings"

    let meetingId: String
    let title: String
    let recordedAt: Double
    let durationSeconds: Double
    let audioDeleted: Bool
    let meetingData: Data
    let searchText: String

    // ── FetchableRecord ──────────────────────────────────────────────────────

    init(row: Row) {
        meetingId     = row["meetingId"]
        title         = row["title"]
        recordedAt    = row["recordedAt"]
        durationSeconds = row["durationSeconds"]
        audioDeleted  = row["audioDeleted"]
        meetingData   = row["meetingData"]
        searchText    = row["searchText"]
    }

    // ── PersistableRecord ────────────────────────────────────────────────────

    func encode(to container: inout PersistenceContainer) throws {
        container["meetingId"]      = meetingId
        container["title"]          = title
        container["recordedAt"]     = recordedAt
        container["durationSeconds"] = durationSeconds
        container["audioDeleted"]   = audioDeleted
        container["meetingData"]    = meetingData
        container["searchText"]     = searchText
    }

    // ── Factory ──────────────────────────────────────────────────────────────

    init(meeting: Meeting) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(meeting)

        let transcriptText = meeting.transcript.map(\.text).joined(separator: " ")
        let summaryText = meeting.summary?.summaryText ?? ""

        meetingId       = meeting.meetingId.uuidString
        title           = meeting.title
        recordedAt      = meeting.recordedAt.timeIntervalSince1970
        durationSeconds = Double(meeting.durationSeconds)
        audioDeleted    = meeting.audioDeleted
        meetingData     = data
        searchText      = "\(meeting.title) \(transcriptText) \(summaryText)"
    }

    func toMeeting() throws -> Meeting {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let m = try decoder.decode(Meeting.self, from: meetingData)
        // The `audioDeleted` column is the authoritative value — it can be updated
        // independently via `markAudioDeleted` without re-encoding the full blob.
        guard m.audioDeleted != audioDeleted else { return m }
        return Meeting(
            meetingId:       m.meetingId,
            title:           m.title,
            recordedAt:      m.recordedAt,
            durationSeconds: m.durationSeconds,
            transcript:      m.transcript,
            summary:         m.summary,
            speakers:        m.speakers,
            audioDeleted:    audioDeleted,
            metadata:        m.metadata
        )
    }
}

// MARK: - Fallback stub

extension MeetingStore {
    /// Returns an in-memory `MeetingStore` used when the production DB cannot be opened.
    /// Queries succeed but nothing is persisted to disk.
    static var failing: MeetingStore {
        return (try? MeetingStore(db: DatabaseQueue())) ?? { fatalError("MeetingStore in-memory init failed") }()
    }
}
