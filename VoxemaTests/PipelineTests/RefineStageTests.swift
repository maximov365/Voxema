import XCTest
@testable import Voxema

// MARK: - Helpers

private func makeSeg(
    speakerId: UUID,
    label: String = "Speaker A",
    start: Float,
    end: Float,
    text: String,
    channel: AudioChannel = .remote
) -> DiarizedSegment {
    DiarizedSegment(
        segmentId: UUID(),
        startTime: start,
        endTime:   end,
        text:      text,
        speaker:   SpeakerIdentity(
            speakerId:  speakerId,
            label:      label,
            isUser:     false,
            confidence: 0.9,
            isKnown:    false
        ),
        channel: channel
    )
}

// MARK: - RefineStageTests

final class RefineStageTests: XCTestCase {

    private let A = UUID()
    private let B = UUID()

    // ── 1. Empty input ───────────────────────────────────────────────────────

    func testEmptyInputReturnsEmpty() async throws {
        let stage = RefineStage()
        let result = try await stage.run([])
        XCTAssertTrue(result.isEmpty)
    }

    // ── 2. Single segment passes through unchanged (modulo cleanup) ──────────

    func testSingleSegmentIsReturned() async throws {
        let stage = RefineStage()
        let seg = makeSeg(speakerId: A, start: 0, end: 1, text: "hello world")
        let result = try await stage.run([seg])
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].speaker.speakerId, A)
    }

    // ── 3. Same speaker, short gap → merged into one block ──────────────────

    func testConsecutiveSameSpeakerWithShortGapIsMerged() async throws {
        let stage = RefineStage(config: RefineConfiguration(mergeGapSeconds: 1.5))
        let segs = [
            makeSeg(speakerId: A, start: 0.0, end: 1.0, text: "hello"),
            makeSeg(speakerId: A, start: 1.5, end: 2.5, text: "world"),   // gap = 0.5 s
        ]
        let result = try await stage.run(segs)
        XCTAssertEqual(result.count, 1)
        XCTAssertTrue(result[0].text.contains("hello"))
        XCTAssertTrue(result[0].text.contains("world"))
    }

    func testMergedBlockSpansFullTimeRange() async throws {
        let stage = RefineStage(config: RefineConfiguration(mergeGapSeconds: 2.0))
        let segs = [
            makeSeg(speakerId: A, start: 0.0, end: 1.0, text: "first"),
            makeSeg(speakerId: A, start: 1.2, end: 2.0, text: "second"),
            makeSeg(speakerId: A, start: 2.1, end: 3.0, text: "third"),
        ]
        let result = try await stage.run(segs)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].startTime, 0.0, accuracy: 0.001)
        XCTAssertEqual(result[0].endTime,   3.0, accuracy: 0.001)
    }

    // ── 4. Same speaker, gap ≥ mergeGapSeconds → separate blocks ────────────

    func testSameSpeakerLongGapCreatesNewBlock() async throws {
        let stage = RefineStage(config: RefineConfiguration(mergeGapSeconds: 1.5))
        let segs = [
            makeSeg(speakerId: A, start: 0.0, end: 1.0, text: "first turn"),
            makeSeg(speakerId: A, start: 4.0, end: 5.0, text: "second turn"),  // gap = 3 s
        ]
        let result = try await stage.run(segs)
        XCTAssertEqual(result.count, 2)
    }

    // ── 5. Different speakers are never merged ───────────────────────────────

    func testDifferentSpeakersAreNotMerged() async throws {
        let stage = RefineStage(config: RefineConfiguration(mergeGapSeconds: 5.0))
        let segs = [
            makeSeg(speakerId: A, start: 0.0, end: 1.0, text: "speaker A"),
            makeSeg(speakerId: B, start: 1.1, end: 2.0, text: "speaker B"),  // tiny gap but B
        ]
        let result = try await stage.run(segs)
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0].speaker.speakerId, A)
        XCTAssertEqual(result[1].speaker.speakerId, B)
    }

    // ── 6. Alternating speakers each get their own block ────────────────────

    func testAlternatingSpeakersProduceCorrectCount() async throws {
        let stage = RefineStage(config: RefineConfiguration(mergeGapSeconds: 1.5))
        let segs = [
            makeSeg(speakerId: A, start: 0, end: 1, text: "A1"),
            makeSeg(speakerId: B, start: 1.2, end: 2, text: "B1"),
            makeSeg(speakerId: A, start: 2.2, end: 3, text: "A2"),
            makeSeg(speakerId: B, start: 3.2, end: 4, text: "B2"),
        ]
        let result = try await stage.run(segs)
        XCTAssertEqual(result.count, 4)
    }

    // ── 7. Text cleanup — capitalisation ────────────────────────────────────

    func testFirstLetterIsCapitalised() async throws {
        let stage = RefineStage()
        let seg = makeSeg(speakerId: A, start: 0, end: 1, text: "hello world.")
        let result = try await stage.run([seg])
        XCTAssertEqual(result[0].text.first, "H")
    }

    // ── 8. Text cleanup — terminal punctuation added ─────────────────────────

    func testTerminalPeriodAddedWhenMissing() async throws {
        let stage = RefineStage()
        let seg = makeSeg(speakerId: A, start: 0, end: 1, text: "no punctuation here")
        let result = try await stage.run([seg])
        XCTAssertTrue(result[0].text.hasSuffix("."),
                      "Expected period, got: \(result[0].text)")
    }

    func testExistingPunctuationNotDuplicated() async throws {
        let stage = RefineStage()
        for terminal in [".", "?", "!", "…"] {
            let seg = makeSeg(speakerId: A, start: 0, end: 1, text: "Are you sure\(terminal)")
            let result = try await stage.run([seg])
            XCTAssertEqual(result[0].text.last.map(String.init), terminal,
                           "Terminal \(terminal) should be preserved")
        }
    }

    // ── 9. Segments are sorted by startTime before processing ───────────────

    func testOutOfOrderSegmentsAreSortedBeforeMerge() async throws {
        let stage = RefineStage(config: RefineConfiguration(mergeGapSeconds: 2.0))
        // Deliberately out-of-order
        let segs = [
            makeSeg(speakerId: A, start: 1.0, end: 2.0, text: "second"),
            makeSeg(speakerId: A, start: 0.0, end: 0.8, text: "first"),
        ]
        let result = try await stage.run(segs)
        XCTAssertEqual(result.count, 1)
        XCTAssertTrue(result[0].text.contains("first"))
        XCTAssertTrue(result[0].text.contains("second"))
        XCTAssertEqual(result[0].startTime, 0.0, accuracy: 0.001)
    }

    // ── 10. Speaker identity is preserved on merged block ───────────────────

    func testMergedBlockRetainsSpeakerIdentity() async throws {
        let stage = RefineStage()
        let segs = [
            makeSeg(speakerId: A, label: "Alice", start: 0, end: 1, text: "hello"),
            makeSeg(speakerId: A, label: "Alice", start: 1.2, end: 2, text: "world"),
        ]
        let result = try await stage.run(segs)
        XCTAssertEqual(result[0].speaker.speakerId, A)
        XCTAssertEqual(result[0].speaker.label, "Alice")
    }

    // ── 11. cancel() does not crash ──────────────────────────────────────────

    func testCancelDoesNotCrash() {
        let stage = RefineStage()
        stage.cancel()  // synchronous stage — just verifies no crash
    }

    // ── 12. RefineConfiguration default gap is 1.5 s ────────────────────────

    func testDefaultConfigMergeGap() {
        XCTAssertEqual(RefineConfiguration.default.mergeGapSeconds, 1.5, accuracy: 0.001)
    }

    // ── 13. Many same-speaker fragments collapse into one readable block ─────

    func testManyFragmentsCollapseToOneBlock() async throws {
        let stage = RefineStage(config: RefineConfiguration(mergeGapSeconds: 0.5))
        let fragments = (0..<10).map { i -> DiarizedSegment in
            makeSeg(speakerId: A, start: Float(i) * 0.3, end: Float(i) * 0.3 + 0.2,
                    text: "word\(i)")
        }
        let result = try await stage.run(fragments)
        XCTAssertEqual(result.count, 1)
        XCTAssertTrue(result[0].text.contains("word0"))
        XCTAssertTrue(result[0].text.contains("word9"))
    }
}
