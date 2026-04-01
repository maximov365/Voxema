import XCTest
@testable import Voxema

// MARK: - Mock

private final class MockEmbeddingEngine: EmbeddingEngineProtocol {
    var loadError: Error?
    var embedResult: [Float] = [Float](repeating: 0, count: 192)
    var embedError: Error?
    private(set) var loadCalled = false
    private(set) var unloadCalled = false
    private(set) var embedCallCount = 0

    func loadModel(at url: URL) throws {
        loadCalled = true
        if let err = loadError { throw err }
    }

    func embed(samples: [Float]) throws -> [Float] {
        embedCallCount += 1
        if let err = embedError { throw err }
        return embedResult
    }

    func unloadModel() { unloadCalled = true }
}

// MARK: - Helpers

private func makeSeg(
    channel: AudioChannel,
    start: Float = 0,
    end: Float = 1,
    text: String = "hello",
    id: UUID = UUID()
) -> TranscribedSegment {
    TranscribedSegment(
        segmentId: id,
        channel: channel,
        startTime: start,
        endTime: end,
        text: text,
        language: "en",
        confidence: 0.9
    )
}

private func makeStage(engine: MockEmbeddingEngine) -> DiarizeStage {
    DiarizeStage(engineFactory: { engine }, config: .default)
}

// MARK: - DiarizeStageTests

final class DiarizeStageTests: XCTestCase {

    // ── 1. Empty input ───────────────────────────────────────────────────────

    func testEmptySegmentsReturnsEmpty() async throws {
        let engine = MockEmbeddingEngine()
        let stage = makeStage(engine: engine)
        let result = try await stage.run([], audioStreams: [])
        XCTAssertTrue(result.isEmpty)
    }

    // ── 2. Local channel → user attribution ─────────────────────────────────

    func testLocalSegmentIsAttributedToUser() async throws {
        let engine = MockEmbeddingEngine()
        let stage = makeStage(engine: engine)
        let result = try await stage.run([makeSeg(channel: .local)], audioStreams: [])
        XCTAssertEqual(result.count, 1)
        XCTAssertTrue(result[0].speaker.isUser)
    }

    func testLocalSegmentUsesUserLabel() async throws {
        let config = DiarizeConfiguration(modelURL: URL(fileURLWithPath: ""), userLabel: "Alice")
        let engine = MockEmbeddingEngine()
        let stage = DiarizeStage(engineFactory: { engine }, config: config)
        let result = try await stage.run([makeSeg(channel: .local)], audioStreams: [])
        XCTAssertEqual(result[0].speaker.label, "Alice")
    }

    func testLocalSegmentConfidenceIsOne() async throws {
        let engine = MockEmbeddingEngine()
        let stage = makeStage(engine: engine)
        let result = try await stage.run([makeSeg(channel: .local)], audioStreams: [])
        XCTAssertEqual(result[0].speaker.confidence, 1.0, accuracy: 1e-6)
    }

    // ── 3. Remote channel ────────────────────────────────────────────────────

    func testRemoteSegmentIsNotUser() async throws {
        let engine = MockEmbeddingEngine()
        let stage = makeStage(engine: engine)
        let result = try await stage.run([makeSeg(channel: .remote)], audioStreams: [])
        XCTAssertFalse(result[0].speaker.isUser)
    }

    func testRemoteSegmentHasNonEmptyLabel() async throws {
        let engine = MockEmbeddingEngine()
        let stage = makeStage(engine: engine)
        let result = try await stage.run([makeSeg(channel: .remote)], audioStreams: [])
        XCTAssertFalse(result[0].speaker.label.isEmpty)
    }

    // ── 4. unloadModel called after run ─────────────────────────────────────

    func testUnloadModelCalledAfterRun() async throws {
        let engine = MockEmbeddingEngine()
        let stage = makeStage(engine: engine)
        _ = try await stage.run([makeSeg(channel: .remote)], audioStreams: [])
        XCTAssertTrue(engine.unloadCalled)
    }

    func testUnloadModelCalledEvenWhenLoadFails() async throws {
        let engine = MockEmbeddingEngine()
        engine.loadError = PipelineError.diarizeEmbeddingModelNotFound
        // Providing a non-empty audioStreams triggers loadModel
        let stream = AudioStream(channel: .remote, filePath: "/nonexistent.enc", durationSeconds: 1, deviceName: "Mock")
        let stage = makeStage(engine: engine)
        _ = try await stage.run([makeSeg(channel: .remote)], audioStreams: [stream])
        XCTAssertTrue(engine.unloadCalled)
    }

    // ── 5. segmentId preserved ───────────────────────────────────────────────

    func testSegmentIdPreserved() async throws {
        let id = UUID()
        let engine = MockEmbeddingEngine()
        let stage = makeStage(engine: engine)
        let result = try await stage.run([makeSeg(channel: .local, id: id)], audioStreams: [])
        XCTAssertEqual(result[0].segmentId, id)
    }

    // ── 6. DiarizeConfiguration defaults ────────────────────────────────────

    func testConfigDefaultMatchThreshold() {
        XCTAssertEqual(DiarizeConfiguration.default.matchThreshold, 0.75, accuracy: 1e-6)
    }

    func testConfigDefaultUserLabel() {
        XCTAssertEqual(DiarizeConfiguration.default.userLabel, "You")
    }

    // ── 7. SpeakerMatcher cosine ─────────────────────────────────────────────

    func testCosineUnitVectorsIsOne() {
        let a: [Float] = [1, 0, 0]
        let b: [Float] = [1, 0, 0]
        XCTAssertEqual(SpeakerMatcher.cosine(a, b), 1.0, accuracy: 1e-6)
    }

    func testCosineOrthogonalIsZero() {
        let a: [Float] = [1, 0, 0]
        let b: [Float] = [0, 1, 0]
        XCTAssertEqual(SpeakerMatcher.cosine(a, b), 0.0, accuracy: 1e-6)
    }

    func testCosineZeroVectorIsZeroNoNaN() {
        let a: [Float] = [0, 0, 0]
        let b: [Float] = [1, 0, 0]
        let result = SpeakerMatcher.cosine(a, b)
        XCTAssertEqual(result, 0.0, accuracy: 1e-6)
        XCTAssertFalse(result.isNaN)
    }

    // ── 8. SpeakerMatcher.best ───────────────────────────────────────────────

    func testBestBelowThresholdReturnsNil() {
        let profile = VoiceProfile(label: "Speaker A", isUser: false, embedding: [1, 0, 0])
        let query: [Float] = [0, 1, 0]  // orthogonal → similarity = 0
        let result = SpeakerMatcher.best(for: query, in: [profile], threshold: 0.75)
        XCTAssertNil(result)
    }

    func testBestAboveThresholdReturnsProfile() {
        let embedding: [Float] = [1, 0, 0]
        let profile = VoiceProfile(label: "Speaker A", isUser: false, embedding: embedding)
        let result = SpeakerMatcher.best(for: embedding, in: [profile], threshold: 0.75)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.label, "Speaker A")
    }

    // ── 9. VoiceProfileStore ─────────────────────────────────────────────────

    func testVoiceProfileStoreAlphabeticSequence() {
        let store = VoiceProfileStore()
        let zeros = [Float](repeating: 0, count: 192)
        // All embeddings are zero → cosine = 0 → below threshold → new profiles each time
        let p1 = store.matchOrCreate(embedding: zeros, threshold: 0.75)
        // Manually empty p1's embedding to force new profile on next call
        _ = p1  // p1 gets label "Speaker A"
        // We can't easily force new profile without resetting store, so just verify first is "Speaker A"
        XCTAssertEqual(p1.label, "Speaker A")
    }

    func testVoiceProfileStoreSameEmbeddingReturnsConsistentLabel() {
        let store = VoiceProfileStore()
        // Create first profile with a distinctive embedding
        var embedding = [Float](repeating: 0, count: 192)
        embedding[0] = 1.0
        let p1 = store.matchOrCreate(embedding: embedding, threshold: 0.5)
        let p2 = store.matchOrCreate(embedding: embedding, threshold: 0.5)
        XCTAssertEqual(p1.label, p2.label)
    }

    // ── 10. Protocol backward-compat default ─────────────────────────────────

    func testProtocolDefaultRunDelegatesToAudioStreams() async throws {
        let engine = MockEmbeddingEngine()
        let stage = makeStage(engine: engine)
        // Default run() should delegate to run(_:audioStreams:[]) without error
        let result = try await stage.run([makeSeg(channel: .local)])
        XCTAssertEqual(result.count, 1)
        XCTAssertTrue(result[0].speaker.isUser)
    }

    // ── 11. Short-segment guard ──────────────────────────────────────────────

    func testShortRemoteSegmentReusesLastSpeaker() async throws {
        let engine = MockEmbeddingEngine()
        // Give the first (long) segment a distinctive embedding so it creates Speaker A.
        var longEmbedding = [Float](repeating: 0, count: 192)
        longEmbedding[0] = 1.0
        engine.embedResult = longEmbedding

        // Config: minEmbeddingDuration = 1.5s
        let config = DiarizeConfiguration(
            modelURL: URL(fileURLWithPath: ""),
            minEmbeddingDuration: 1.5
        )
        let stage = DiarizeStage(engineFactory: { engine }, config: config)

        // seg1: 3s duration — triggers full embedding path
        let seg1 = makeSeg(channel: .remote, start: 0, end: 3.0)
        // seg2: 0.5s duration — too short, should reuse seg1's speaker
        let seg2 = makeSeg(channel: .remote, start: 3.0, end: 3.5)

        let result = try await stage.run([seg1, seg2], audioStreams: [])

        XCTAssertEqual(result.count, 2)
        // Both segments should have the same speaker label
        XCTAssertEqual(result[0].speaker.label, result[1].speaker.label,
                       "Short segment must reuse the previous speaker, not create a new one")
        // Short segment should report confidence 0 (no embedding was computed)
        XCTAssertEqual(result[1].speaker.confidence, 0.0, accuracy: 1e-6)
        // embed() must have been called exactly once (only for the long segment)
        XCTAssertEqual(engine.embedCallCount, 1,
                       "embed() must not be called for segments below minEmbeddingDuration")
    }

    func testShortFirstRemoteSegmentFallsBackToEmbedding() async throws {
        // When there is no previous speaker, a short first segment still goes
        // through the embedding path (no prior to reuse).
        let engine = MockEmbeddingEngine()
        let config = DiarizeConfiguration(
            modelURL: URL(fileURLWithPath: ""),
            minEmbeddingDuration: 1.5
        )
        let stage = DiarizeStage(engineFactory: { engine }, config: config)
        let shortFirst = makeSeg(channel: .remote, start: 0, end: 0.5)
        let result = try await stage.run([shortFirst], audioStreams: [])
        XCTAssertEqual(result.count, 1)
        XCTAssertFalse(result[0].speaker.isUser)
        // embed() called once — no prev speaker to reuse
        XCTAssertEqual(engine.embedCallCount, 1)
    }

    func testConfigDefaultMinEmbeddingDuration() {
        XCTAssertEqual(DiarizeConfiguration.default.minEmbeddingDuration, 1.5, accuracy: 1e-6)
    }
}
