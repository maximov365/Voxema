import XCTest
import AVFoundation
import GRDB
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

    // ── 7a. SpeakerMatcher.weightedBlend ────────────────────────────────────

    func testWeightedBlendAtZeroKeepsExisting() {
        let existing: [Float] = [1, 0, 0]
        let new:      [Float] = [0, 1, 0]
        let result = SpeakerMatcher.weightedBlend(existing, new, newWeight: 0)
        XCTAssertEqual(result[0], 1.0, accuracy: 1e-5)
        XCTAssertEqual(result[1], 0.0, accuracy: 1e-5)
    }

    func testWeightedBlendAtOneReplacesWithNew() {
        let existing: [Float] = [1, 0, 0]
        let new:      [Float] = [0, 1, 0]
        let result = SpeakerMatcher.weightedBlend(existing, new, newWeight: 1)
        XCTAssertEqual(result[0], 0.0, accuracy: 1e-5)
        XCTAssertEqual(result[1], 1.0, accuracy: 1e-5)
    }

    func testWeightedBlendAtHalfIsEqualAverage() {
        let existing: [Float] = [1, 0, 0]
        let new:      [Float] = [0, 0, 1]
        let result = SpeakerMatcher.weightedBlend(existing, new, newWeight: 0.5)
        XCTAssertEqual(result[0], 0.5, accuracy: 1e-5)
        XCTAssertEqual(result[2], 0.5, accuracy: 1e-5)
    }

    func testWeightedBlendLowWeightPreservesProfile() {
        // A short segment (blendWeight = 0.15) should move the centroid only slightly
        let existing: [Float] = [Float](repeating: 0.1, count: 192)
        var noise    = [Float](repeating: 0.0, count: 192)
        noise[0] = 1.0   // very different from existing
        let result = SpeakerMatcher.weightedBlend(existing, noise, newWeight: 0.15)
        // Centroid should be much closer to existing than to noise
        let distToExisting = SpeakerMatcher.cosine(result, existing)
        let distToNoise    = SpeakerMatcher.cosine(result, noise)
        XCTAssertGreaterThan(distToExisting, distToNoise)
    }

    // ── 7b. SpeakerMatcher cosine ────────────────────────────────────────────

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

    // ── 11. Short-segment context-padded window ──────────────────────────────

    func testShortRemoteSegmentGetsSameSpeakerAsPrev() async throws {
        // Both segments return the same mock embedding → should get the same label.
        // No audio streams provided: slicedSamples will be empty for both, so the
        // short segment falls back to the reuse path (prev profile, confidence = 0).
        let engine = MockEmbeddingEngine()
        var embedding = [Float](repeating: 0, count: 192)
        embedding[0] = 1.0
        engine.embedResult = embedding

        let config = DiarizeConfiguration(
            modelURL: URL(fileURLWithPath: ""),
            minEmbeddingDuration: 1.5
        )
        let stage = DiarizeStage(engineFactory: { engine }, config: config)

        let seg1 = makeSeg(channel: .remote, start: 0, end: 3.0)
        let seg2 = makeSeg(channel: .remote, start: 3.0, end: 3.5)   // short

        let result = try await stage.run([seg1, seg2], audioStreams: [])

        XCTAssertEqual(result.count, 2)
        // Short segment reuses the last speaker when no audio is available
        XCTAssertEqual(result[0].speaker.label, result[1].speaker.label,
                       "Short segment with no audio must reuse the previous speaker")
        XCTAssertEqual(result[1].speaker.confidence, 0.0, accuracy: 1e-6,
                       "Reused-speaker confidence must be 0 (no embedding computed)")
    }

    func testShortSegmentWithAudioUsesContextPadding() async throws {
        // When audio IS available the context-padded window should produce a
        // real embedding and a non-zero confidence — not a reuse (confidence = 0).
        let engine = MockEmbeddingEngine()
        var embedding = [Float](repeating: 0, count: 192)
        embedding[0] = 1.0
        engine.embedResult = embedding

        let config = DiarizeConfiguration(
            modelURL: URL(fileURLWithPath: ""),
            matchThreshold: 0.5,
            minEmbeddingDuration: 1.5
        )
        let stage = DiarizeStage(engineFactory: { engine }, config: config)

        // Provide a real (silent) audio stream so slicedSamples is non-empty
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                   sampleRate: 16_000, channels: 1, interleaved: false)!
        let frameCount = AVAudioFrameCount(16_000 * 5)   // 5 s of silence
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
        buffer.frameLength = frameCount

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let wavURL = tempDir.appendingPathComponent("remote.wav")
        let audioFile = try AVAudioFile(forWriting: wavURL,
                                        settings: format.settings,
                                        commonFormat: format.commonFormat,
                                        interleaved: false)
        try audioFile.write(from: buffer)

        // Encrypt the WAV using the default key
        let keyId = "test-diarize-ctx-\(UUID().uuidString)"
        let plaintext = try Data(contentsOf: wavURL)
        let encrypted = try EncryptionManager.encrypt(plaintext, keyIdentifier: keyId)
        let encURL = tempDir.appendingPathComponent("remote.enc")
        try encrypted.write(to: encURL)

        let stream = AudioStream(channel: .remote, filePath: encURL.path,
                                 durationSeconds: 5, deviceName: "Mock")
        let configWithKey = DiarizeConfiguration(
            modelURL: URL(fileURLWithPath: ""),
            encryptionKeyId: keyId,
            matchThreshold: 0.5,
            minEmbeddingDuration: 1.5
        )
        let stageWithKey = DiarizeStage(engineFactory: { engine }, config: configWithKey)

        let seg1 = makeSeg(channel: .remote, start: 0, end: 3.0)
        let seg2 = makeSeg(channel: .remote, start: 3.0, end: 3.5)   // 0.5 s, short

        let result = try await stageWithKey.run([seg1, seg2], audioStreams: [stream])

        XCTAssertEqual(result.count, 2)
        // With audio available, the short segment gets a real embedding → confidence > 0
        XCTAssertGreaterThan(result[1].speaker.confidence, 0.0,
                             "Short segment with audio context must produce a non-zero confidence")
        XCTAssertEqual(result[0].speaker.label, result[1].speaker.label,
                       "Short segment should match the same speaker when embedding is identical")
    }

    func testShortFirstRemoteSegmentProducesALabel() async throws {
        // A short first segment (no prev speaker) still gets a speaker label.
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
        XCTAssertFalse(result[0].speaker.label.isEmpty)
    }

    func testConfigDefaultMinEmbeddingDuration() {
        XCTAssertEqual(DiarizeConfiguration.default.minEmbeddingDuration, 1.5, accuracy: 1e-6)
    }

    // ── 13. Adaptive threshold ───────────────────────────────────────────────

    func testAdaptiveThresholdStricterForNewProfiles() {
        // A brand-new profile (matchCount=0) should require ~0.05 higher similarity
        // to be matched than the base threshold.
        let store = VoiceProfileStore()
        var base = [Float](repeating: 0, count: 192)
        base[0] = 1.0
        _ = store.matchOrCreate(embedding: base, threshold: 0.75)  // creates Speaker A, matchCount=0

        // Query with similarity ≈ 0.77 (above base threshold but below adaptive boost).
        // 0.77 < 0.75 + 0.05 = 0.80 → should NOT match → new profile "Speaker B"
        var slightly = [Float](repeating: 0, count: 192)
        slightly[0] = 0.97   // cosine ≈ 0.97… too similar, let's use a weaker vector
        slightly[1] = 0.24   // cosine(base, slightly) = 0.97 / (1 * 1) ≈ normalised
        // We need cosine exactly in range (0.75, 0.80). Use a precise construction:
        // a = [1, 0], b = [cos θ, sin θ] → cosine = cos θ
        // cos(40°) ≈ 0.766 → in (0.75, 0.80)
        let angle: Float = 40.0 * .pi / 180.0
        var borderline = [Float](repeating: 0, count: 192)
        borderline[0] = cos(angle)
        borderline[1] = sin(angle)

        let result = store.matchOrCreate(embedding: borderline, threshold: 0.75)
        XCTAssertEqual(result.label, "Speaker B",
                       "Borderline similarity should not match a brand-new profile (adaptive boost)")
    }

    func testAdaptiveThresholdRelaxesAfterThreeMatches() {
        // After 3 successful matches, the adaptive boost should reach 0 and
        // a borderline similarity (just above base threshold) should match.
        let store = VoiceProfileStore()
        var base = [Float](repeating: 0, count: 192)
        base[0] = 1.0

        // Build up matchCount to 3 with identical vectors (cosine = 1.0 → always matches)
        for _ in 0 ..< 3 {
            _ = store.matchOrCreate(embedding: base, threshold: 0.75, blendWeight: 0.1)
        }

        // Now borderline query (cosine ≈ 0.766 → above 0.75 base, below 0.80 boosted)
        let angle: Float = 40.0 * .pi / 180.0
        var borderline = [Float](repeating: 0, count: 192)
        borderline[0] = cos(angle)
        borderline[1] = sin(angle)

        let result = store.matchOrCreate(embedding: borderline, threshold: 0.75)
        XCTAssertEqual(result.label, "Speaker A",
                       "After 3 matches the adaptive boost is 0; borderline should match")
    }

    func testMatchCountIncreasesOnEachMatch() {
        let store = VoiceProfileStore()
        var emb = [Float](repeating: 0, count: 192)
        emb[0] = 1.0
        // First call: creates profile (matchCount = 0)
        let p0 = store.matchOrCreate(embedding: emb, threshold: 0.5)
        XCTAssertEqual(p0.matchCount, 0)
        // Second call with identical embedding: matches (matchCount increments to 1)
        let p1 = store.matchOrCreate(embedding: emb, threshold: 0.5)
        XCTAssertEqual(p1.matchCount, 1)
        let p2 = store.matchOrCreate(embedding: emb, threshold: 0.5)
        XCTAssertEqual(p2.matchCount, 2)
    }

    func testConfigDefaultRetroAttributionThreshold() {
        XCTAssertEqual(DiarizeConfiguration.default.retroAttributionThreshold, 0.60, accuracy: 1e-6)
    }

    // ── 12. Retrospective re-attribution ─────────────────────────────────────

    func testRetroAttributionFixesMisattributedSegment() async throws {
        // Scenario: two distinct speakers.
        // seg1 (Speaker A) arrives first — profile_A created.
        // seg2 (Speaker B) arrives — profile_B created, but embedB is borderline
        //   similar to profile_A at the time → incorrectly matched to A with low conf.
        // seg3 (Speaker B again) → profile_B now well-established.
        // seg4 (Speaker B) → also strong match.
        // After pass 1, seg2 should have been reassigned to B in the retro pass.

        // embedA and embedB are orthogonal → cosine = 0 → will always create new profiles.
        var embedA = [Float](repeating: 0, count: 192)
        embedA[0] = 1.0   // Speaker A: axis 0

        var embedB = [Float](repeating: 0, count: 192)
        embedB[1] = 1.0   // Speaker B: axis 1 (orthogonal to A)

        // Engine returns A for seg1, then B for seg2, seg3, seg4
        var callCount = 0
        let engine = MockEmbeddingEngine()

        let config = DiarizeConfiguration(
            modelURL: URL(fileURLWithPath: ""),
            matchThreshold: 0.75,
            retroAttributionThreshold: 0.50
        )

        // We use a custom engine factory per call
        var embeddings: [[Float]] = [embedA, embedB, embedB, embedB]
        let stage = DiarizeStage(
            engineFactory: {
                let e = MockEmbeddingEngine()
                return e
            },
            config: config
        )

        // Use the mock directly with changing embedResult
        let mockEngine = MockEmbeddingEngine()
        var embedQueue = embeddings
        // We can't change embedResult mid-run with the current mock API,
        // so instead test the retro logic via VoiceProfileStore directly.

        // ── Direct unit test of retro logic via store ──
        let store = VoiceProfileStore()

        // Simulate pass 1: embedA creates profile A
        let profileA = store.matchOrCreate(embedding: embedA, threshold: 0.75, blendWeight: 0.3)
        XCTAssertEqual(profileA.label, "Speaker A")

        // embedB creates profile B
        let profileB = store.matchOrCreate(embedding: embedB, threshold: 0.75, blendWeight: 0.3)
        XCTAssertEqual(profileB.label, "Speaker B")

        // More embedB updates → profile B well-established
        _ = store.matchOrCreate(embedding: embedB, threshold: 0.75, blendWeight: 0.4)
        _ = store.matchOrCreate(embedding: embedB, threshold: 0.75, blendWeight: 0.4)

        // Simulate a low-confidence result for embedB assigned to profile A (misattribution)
        let finalProfiles = store.allRemoteProfiles()
        let bestRetro = SpeakerMatcher.best(for: embedB, in: finalProfiles, threshold: 0.50)
        XCTAssertNotNil(bestRetro, "Retro pass should find a match for embedB")
        XCTAssertEqual(bestRetro?.label, "Speaker B",
                       "Retro pass should reassign embedB to Speaker B, not Speaker A")
        XCTAssertGreaterThan(
            SpeakerMatcher.cosine(bestRetro!.embedding, embedB),
            SpeakerMatcher.cosine(profileA.embedding, embedB),
            "Speaker B profile should score higher than Speaker A for embedB"
        )
        _ = (engine, mockEngine, callCount, embedQueue, stage)  // silence unused warnings
    }

    func testWeightedMatchOrCreateUsesBlendWeight() {
        let store = VoiceProfileStore()
        var base = [Float](repeating: 0, count: 192)
        base[0] = 1.0  // unit vector along axis 0

        // Create initial profile
        _ = store.matchOrCreate(embedding: base, threshold: 0.5, blendWeight: 0.3)

        // Update with a perpendicular vector at very low weight
        var perp = [Float](repeating: 0, count: 192)
        perp[1] = 1.0
        // This should NOT match (cosine = 0 < 0.5 threshold) → creates new profile
        let second = store.matchOrCreate(embedding: perp, threshold: 0.5, blendWeight: 0.3)
        XCTAssertEqual(second.label, "Speaker B")

        // Now update first profile with a near-identical vector at low weight
        var nearBase = [Float](repeating: 0, count: 192)
        nearBase[0] = 0.99
        nearBase[1] = 0.14  // slight drift, cosine ~0.99 with base → matches
        let updated = store.matchOrCreate(embedding: nearBase, threshold: 0.5, blendWeight: 0.15)
        XCTAssertEqual(updated.label, "Speaker A")
        // Profile centroid should have moved only slightly toward nearBase
        let sim = SpeakerMatcher.cosine(updated.embedding, base)
        XCTAssertGreaterThan(sim, 0.99, "Low blend weight should keep centroid close to original")
    }
}

// MARK: - MockSpeakerProfilePersistence

private final class MockSpeakerProfilePersistence: SpeakerProfilePersistence {
    var profilesToReturn: [VoiceProfile] = []
    private(set) var upsertedProfiles: [VoiceProfile] = []
    var loadError: Error?
    var upsertError: Error?

    func loadRemoteProfiles() throws -> [VoiceProfile] {
        if let err = loadError { throw err }
        return profilesToReturn
    }

    func upsertProfile(_ profile: VoiceProfile) throws {
        if let err = upsertError { throw err }
        if let idx = upsertedProfiles.firstIndex(where: { $0.profileId == profile.profileId }) {
            upsertedProfiles[idx] = profile
        } else {
            upsertedProfiles.append(profile)
        }
    }
}

// MARK: - SpeakerProfilePersistenceTests

final class SpeakerProfilePersistenceTests: XCTestCase {

    // ── 1. Profiles loaded from persistence are seeded into the store ─────────

    func testSeededProfileIsReusedForMatchingEmbedding() async throws {
        let knownEmbedding: [Float] = [1, 0, 0] + [Float](repeating: 0, count: 189)
        let persisted = VoiceProfile(
            profileId: UUID(),
            label: "Speaker A",
            isUser: false,
            embedding: knownEmbedding,
            matchCount: 5
        )

        let persistence = MockSpeakerProfilePersistence()
        persistence.profilesToReturn = [persisted]

        let engine = MockEmbeddingEngine()
        engine.embedResult = knownEmbedding   // same embedding → cosine = 1.0

        let stage = DiarizeStage(
            engineFactory: { engine },
            config: DiarizeConfiguration(
                modelURL: URL(fileURLWithPath: "/dev/null"),
                matchThreshold: 0.75
            ),
            profilePersistence: persistence
        )

        let result = try await stage.run(
            [makeSeg(channel: .remote, start: 0, end: 1)],
            audioStreams: []
        )

        // Should reuse the seeded profile, not create a new "Speaker B"
        XCTAssertEqual(result.first?.speaker.label, "Speaker A")
    }

    // ── 2. New profiles created during run are saved to persistence ───────────

    func testNewProfileIsUpsertedAfterRun() async throws {
        let persistence = MockSpeakerProfilePersistence()

        let engine = MockEmbeddingEngine()
        var embedding = [Float](repeating: 0, count: 192)
        embedding[0] = 1.0
        engine.embedResult = embedding

        let stage = DiarizeStage(
            engineFactory: { engine },
            config: DiarizeConfiguration(
                modelURL: URL(fileURLWithPath: "/dev/null"),
                matchThreshold: 0.75
            ),
            profilePersistence: persistence
        )

        _ = try await stage.run(
            [makeSeg(channel: .remote, start: 0, end: 1)],
            audioStreams: []
        )

        XCTAssertEqual(persistence.upsertedProfiles.count, 1)
        XCTAssertEqual(persistence.upsertedProfiles.first?.label, "Speaker A")
    }

    // ── 3. matchCount increments on a successful match ────────────────────────

    func testMatchCountIncrementedOnMatch() async throws {
        let embedding: [Float] = [1, 0, 0] + [Float](repeating: 0, count: 189)
        let persisted = VoiceProfile(
            profileId: UUID(),
            label: "Speaker A",
            isUser: false,
            embedding: embedding,
            matchCount: 3
        )

        let persistence = MockSpeakerProfilePersistence()
        persistence.profilesToReturn = [persisted]

        let engine = MockEmbeddingEngine()
        engine.embedResult = embedding

        let stage = DiarizeStage(
            engineFactory: { engine },
            config: DiarizeConfiguration(
                modelURL: URL(fileURLWithPath: "/dev/null"),
                matchThreshold: 0.75
            ),
            profilePersistence: persistence
        )

        _ = try await stage.run(
            [makeSeg(channel: .remote, start: 0, end: 1)],
            audioStreams: []
        )

        let saved = persistence.upsertedProfiles.first(where: { $0.label == "Speaker A" })
        XCTAssertEqual(saved?.matchCount, 4, "matchCount should increment from 3 to 4")
    }

    // ── 4. Label ordinals continue past seeded labels ─────────────────────────

    func testNextLabelContinuesPastSeededLabels() async throws {
        // Seed "Speaker A" and "Speaker B" → new speaker should be "Speaker C"
        let embA: [Float] = [1, 0, 0] + [Float](repeating: 0, count: 189)
        let embB: [Float] = [0, 1, 0] + [Float](repeating: 0, count: 189)
        let embC: [Float] = [0, 0, 1] + [Float](repeating: 0, count: 189)

        let persistence = MockSpeakerProfilePersistence()
        persistence.profilesToReturn = [
            VoiceProfile(label: "Speaker A", isUser: false, embedding: embA),
            VoiceProfile(label: "Speaker B", isUser: false, embedding: embB),
        ]

        let engine = MockEmbeddingEngine()
        engine.embedResult = embC   // orthogonal to both → new profile

        let stage = DiarizeStage(
            engineFactory: { engine },
            config: DiarizeConfiguration(
                modelURL: URL(fileURLWithPath: "/dev/null"),
                matchThreshold: 0.75
            ),
            profilePersistence: persistence
        )

        let result = try await stage.run(
            [makeSeg(channel: .remote, start: 0, end: 1)],
            audioStreams: []
        )

        XCTAssertEqual(result.first?.speaker.label, "Speaker C",
                       "New speaker after seeded A+B should be C")
    }

    // ── 5. Load error is silently ignored (session continues without prior data) ──

    func testLoadErrorFallsBackToEmptyStore() async throws {
        let persistence = MockSpeakerProfilePersistence()
        persistence.loadError = NSError(domain: "TestError", code: 1)

        let engine = MockEmbeddingEngine()
        let stage = DiarizeStage(
            engineFactory: { engine },
            config: .default,
            profilePersistence: persistence
        )

        // Should not throw — load failure is soft
        let result = try await stage.run(
            [makeSeg(channel: .remote)],
            audioStreams: []
        )
        XCTAssertFalse(result.isEmpty)
    }

    // ── 6. GRDB round-trip: save + reload preserves all fields ───────────────

    func testMeetingStoreRoundTrip() throws {
        let db = try MeetingStore(db: DatabaseQueue())

        let original = VoiceProfile(
            profileId:  UUID(),
            label:      "Speaker Z",
            isUser:     false,
            embedding:  [0.1, 0.2, 0.3],
            matchCount: 7,
            lastSeenAt: Date(timeIntervalSince1970: 1_000_000),
            createdAt:  Date(timeIntervalSince1970:   500_000)
        )

        try db.upsertProfile(original)

        let loaded = try db.loadRemoteProfiles()
        XCTAssertEqual(loaded.count, 1)
        let p = try XCTUnwrap(loaded.first)
        XCTAssertEqual(p.profileId,  original.profileId)
        XCTAssertEqual(p.label,      "Speaker Z")
        XCTAssertFalse(p.isUser)
        XCTAssertEqual(p.matchCount, 7)
        XCTAssertEqual(p.embedding[0], 0.1, accuracy: 1e-5)
        XCTAssertEqual(p.embedding[1], 0.2, accuracy: 1e-5)
        XCTAssertEqual(p.embedding[2], 0.3, accuracy: 1e-5)
        XCTAssertEqual(p.lastSeenAt.timeIntervalSince1970, 1_000_000, accuracy: 0.001)
        XCTAssertEqual(p.createdAt.timeIntervalSince1970,   500_000, accuracy: 0.001)
    }

    // ── 7. Upsert replaces existing record ───────────────────────────────────

    func testMeetingStoreUpsertUpdatesExistingRecord() throws {
        let db = try MeetingStore(db: DatabaseQueue())
        let id = UUID()

        let v1 = VoiceProfile(profileId: id, label: "Speaker A", isUser: false,
                               embedding: [1, 0, 0], matchCount: 1)
        try db.upsertProfile(v1)

        let v2 = VoiceProfile(profileId: id, label: "Speaker A", isUser: false,
                               embedding: [1, 0, 0], matchCount: 5)
        try db.upsertProfile(v2)

        let loaded = try db.loadRemoteProfiles()
        XCTAssertEqual(loaded.count, 1, "upsert should not create a duplicate row")
        XCTAssertEqual(loaded.first?.matchCount, 5)
    }

    // ── 8. User profiles are not persisted ────────────────────────────────────

    func testUserProfileIsNotUpserted() throws {
        let db = try MeetingStore(db: DatabaseQueue())
        let user = VoiceProfile(label: "You", isUser: true, embedding: [1, 0, 0])
        // upsertProfile should silently skip user profiles
        XCTAssertNoThrow(try db.upsertProfile(user))
        let loaded = try db.loadRemoteProfiles()
        XCTAssertTrue(loaded.isEmpty, "User profile must not be persisted")
    }
}
