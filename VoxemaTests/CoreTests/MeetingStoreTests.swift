import XCTest
import GRDB
@testable import Voxema

// MARK: - Helpers

private func makeStore() throws -> MeetingStore {
    try MeetingStore(db: DatabaseQueue())  // in-memory
}

private func makeMeeting(title: String = "Test Meeting", transcript: [DiarizedSegment] = []) -> Meeting {
    Meeting(
        title: title,
        durationSeconds: 60,
        transcript: transcript,
        summary: nil,
        speakers: [],
        audioDeleted: false,
        metadata: MeetingMetadata(
            whisperModel: "tiny",
            summaryProvider: "local",
            languageDetected: "en",
            segmentCount: transcript.count,
            wordCount: 0
        )
    )
}

private func makeSeg(label: String = "You", text: String = "hello") -> DiarizedSegment {
    DiarizedSegment(
        segmentId: UUID(),
        startTime: 0,
        endTime: 1,
        text: text,
        speaker: SpeakerIdentity(label: label, isUser: true, confidence: 1, isKnown: true),
        channel: .local
    )
}

// MARK: - Tests

final class MeetingStoreTests: XCTestCase {

    // ── 1. Save + fetch round-trip ─────────────────────────────────────────

    func testSaveAndFetchRoundTrip() throws {
        let store = try makeStore()
        let m = makeMeeting(title: "Round Trip")
        try store.save(m)
        let fetched = try store.fetch(id: m.meetingId)
        XCTAssertNotNil(fetched)
        XCTAssertEqual(fetched?.title, "Round Trip")
        XCTAssertEqual(fetched?.meetingId, m.meetingId)
    }

    // ── 2. Fetch missing ID → nil ──────────────────────────────────────────

    func testFetchMissingIdReturnsNil() throws {
        let store = try makeStore()
        let result = try store.fetch(id: UUID())
        XCTAssertNil(result)
    }

    // ── 3. fetchAll returns all, ordered by recordedAt DESC ────────────────

    func testFetchAllReturnsMostRecentFirst() throws {
        let store = try makeStore()
        let now = Date()
        // Use explicit timestamps so the ordering is deterministic regardless of wall clock speed
        let m1 = Meeting(title: "Older", recordedAt: now.addingTimeInterval(-60), durationSeconds: 60,
                         metadata: MeetingMetadata(whisperModel: "tiny", summaryProvider: "local", languageDetected: "en", segmentCount: 0, wordCount: 0))
        let m2 = Meeting(title: "Newer", recordedAt: now, durationSeconds: 60,
                         metadata: MeetingMetadata(whisperModel: "tiny", summaryProvider: "local", languageDetected: "en", segmentCount: 0, wordCount: 0))
        try store.save(m1)
        try store.save(m2)
        let all = try store.fetchAll()
        XCTAssertEqual(all.count, 2)
        XCTAssertEqual(all[0].title, "Newer")
        XCTAssertEqual(all[1].title, "Older")
    }

    // ── 4. Delete ──────────────────────────────────────────────────────────

    func testDeleteRemovesMeeting() throws {
        let store = try makeStore()
        let m = makeMeeting()
        try store.save(m)
        try store.delete(id: m.meetingId)
        let fetched = try store.fetch(id: m.meetingId)
        XCTAssertNil(fetched)
    }

    // ── 5. Search finds by transcript text ────────────────────────────────

    func testSearchFindsKeywordInTranscript() throws {
        let store = try makeStore()
        let seg = makeSeg(text: "quarterly revenue targets")
        let m = makeMeeting(title: "Q4 Review", transcript: [seg])
        try store.save(m)
        let results = try store.search("quarterly")
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].meetingId, m.meetingId)
    }

    // ── 6. Search miss ────────────────────────────────────────────────────

    func testSearchWithNoMatchReturnsEmpty() throws {
        let store = try makeStore()
        try store.save(makeMeeting(title: "Team sync"))
        let results = try store.search("xyznotfound")
        XCTAssertTrue(results.isEmpty)
    }

    // ── 7. markAudioDeleted ────────────────────────────────────────────────

    func testMarkAudioDeletedUpdatesFlagToTrue() throws {
        let store = try makeStore()
        let m = makeMeeting()
        XCTAssertFalse(m.audioDeleted)
        try store.save(m)
        try store.markAudioDeleted(id: m.meetingId)
        let updated = try store.fetch(id: m.meetingId)
        XCTAssertTrue(updated?.audioDeleted == true)
    }
}
