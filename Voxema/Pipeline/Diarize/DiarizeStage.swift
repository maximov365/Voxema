import Foundation
import COnnxRuntime
import Accelerate

// MARK: - EmbeddingEngineProtocol

/// Abstraction over the ECAPA-TDNN ONNX Runtime session.
/// Enables testing DiarizeStage with a mock engine without real inference.
public protocol EmbeddingEngineProtocol: AnyObject {
    /// Loads the speaker embedding model at `url`.
    /// Pass a bundle resource URL for `ecapa-tdnn.mlpackage` (CoreML, DEC-16 Phase 2)
    /// or an empty URL to use the MFCC fallback (Phase 1, no model file required).
    func loadModel(at url: URL) throws
    /// Extracts a 192-dim speaker embedding from mono float32 16kHz `samples`.
    func embed(samples: [Float]) throws -> [Float]
    /// Releases model resources.
    func unloadModel()
}

// MARK: - EmbeddingEngine

/// Real ECAPA-TDNN embedding engine backed by `COnnxRuntime` C bridge.
public final class EmbeddingEngine: EmbeddingEngineProtocol {

    private var ctx: OpaquePointer?
    private let log = VoxemaLogger.make(category: "diarize.engine")

    public init() {}
    deinit { unloadModel() }

    public func loadModel(at url: URL) throws {
        unloadModel()
        var loaded: OpaquePointer?
        url.withUnsafeFileSystemRepresentation { cPath in
            loaded = voxema_ecapa_init(cPath)
        }
        guard let loaded else {
            log.error("voxema_ecapa_init returned nil")
            throw PipelineError.diarizeEmbeddingModelNotFound
        }
        ctx = loaded
        log.info("EmbeddingEngine model loaded")
    }

    public func embed(samples: [Float]) throws -> [Float] {
        guard let ctx else { throw PipelineError.diarizeEmbeddingModelNotFound }
        guard !samples.isEmpty else { return [Float](repeating: 0, count: Int(VOXEMA_ECAPA_EMBEDDING_DIM)) }

        var embedding = [Float](repeating: 0, count: Int(VOXEMA_ECAPA_EMBEDDING_DIM))
        let result = samples.withUnsafeBufferPointer { samplesBuf in
            embedding.withUnsafeMutableBufferPointer { embBuf in
                voxema_ecapa_embed(
                    ctx,
                    samplesBuf.baseAddress,
                    Int32(samplesBuf.count),
                    embBuf.baseAddress,
                    Int32(embBuf.count)
                )
            }
        }
        guard result == 0 else {
            log.error("voxema_ecapa_embed returned non-zero")
            return [Float](repeating: 0, count: Int(VOXEMA_ECAPA_EMBEDDING_DIM))
        }
        return embedding
    }

    public func unloadModel() {
        guard let ctx else { return }
        voxema_ecapa_free(ctx)
        self.ctx = nil
        log.info("EmbeddingEngine model unloaded")
    }
}

// MARK: - VoiceProfile

/// In-memory representation of a known or discovered speaker.
/// Persisted across sessions via GRDB (`SpeakerProfilePersistence`).
public struct VoiceProfile: Equatable, Sendable {
    public let profileId: UUID
    /// Human-readable label: user name or temporary "Speaker A", "Speaker B", …
    public let label: String
    /// True for the local-channel speaker (always the device user).
    public let isUser: Bool
    /// Accumulated embedding (updated as more segments are observed).
    public var embedding: [Float]
    /// Number of times this profile has been successfully matched.
    /// Used to compute an adaptive matching threshold: new profiles require
    /// stricter similarity before merging with an incoming embedding.
    public var matchCount: Int
    /// Timestamp of the most recent match (used for ordering in persistence).
    public var lastSeenAt: Date
    /// Timestamp when this profile was first created.
    public let createdAt: Date

    public init(
        profileId:  UUID    = UUID(),
        label:      String,
        isUser:     Bool,
        embedding:  [Float] = [],
        matchCount: Int     = 0,
        lastSeenAt: Date    = Date(),
        createdAt:  Date    = Date()
    ) {
        self.profileId  = profileId
        self.label      = label
        self.isUser     = isUser
        self.embedding  = embedding
        self.matchCount = matchCount
        self.lastSeenAt = lastSeenAt
        self.createdAt  = createdAt
    }
}

// MARK: - VoiceProfileStore

/// In-memory store for VoiceProfile objects.
/// Seeded from `SpeakerProfilePersistence` at the start of each run.
public final class VoiceProfileStore {

    private var profiles: [UUID: VoiceProfile] = [:]
    private var remoteCount: Int = 0

    /// Returns the user profile, creating it on first access.
    public func userProfile(label: String) -> VoiceProfile {
        if let existing = profiles.values.first(where: { $0.isUser }) { return existing }
        let p = VoiceProfile(label: label, isUser: true)
        profiles[p.profileId] = p
        return p
    }

    /// Returns all non-user profiles. Used by the retrospective re-attribution pass.
    public func allRemoteProfiles() -> [VoiceProfile] {
        profiles.values.filter { !$0.isUser }
    }

    /// Pre-populates the store with profiles loaded from persistence.
    /// Advances `remoteCount` so new speakers receive fresh labels.
    public func seed(_ seeded: [VoiceProfile]) {
        for p in seeded { profiles[p.profileId] = p }
        let maxOrdinal = seeded
            .filter { !$0.isUser }
            .compactMap { labelOrdinal(of: $0.label) }
            .max() ?? 0
        remoteCount = max(remoteCount, maxOrdinal)
    }

    /// Returns all profiles currently held in the store.
    public func allProfiles() -> [VoiceProfile] { Array(profiles.values) }

    /// Returns a profile whose embedding is close to `embedding` within `threshold`,
    /// or creates a new profile with the next alphabetic label ("Speaker A", "B", …).
    ///
    /// **Adaptive threshold:** new profiles (matchCount < 3) require a stricter
    /// cosine similarity to be matched. Boost converges to zero at matchCount = 3.
    ///
    /// `blendWeight` controls how strongly the new embedding shifts the stored
    /// profile centroid (0 = no shift, 1 = full replacement).
    /// Updates `matchCount` and `lastSeenAt` on a successful match.
    public func matchOrCreate(
        embedding: [Float],
        threshold: Float,
        blendWeight: Float = 0.3
    ) -> VoiceProfile {
        // Evaluate each candidate against its own adaptive threshold
        let matched = profiles.values
            .filter { !$0.isUser && !$0.embedding.isEmpty }
            .compactMap { profile -> (VoiceProfile, Float)? in
                let sim = SpeakerMatcher.cosine(profile.embedding, embedding)
                // Young profiles (matchCount < 3) require up to +0.05 extra similarity.
                // Converges to base threshold once the profile is well-established.
                let boost = 0.05 * max(0, 1.0 - Float(min(profile.matchCount, 3)) / 3.0)
                return sim >= threshold + boost ? (profile, sim) : nil
            }
            .max { $0.1 < $1.1 }

        if let (best, _) = matched {
            var updated = best
            updated.matchCount += 1
            updated.lastSeenAt = Date()
            updated.embedding = SpeakerMatcher.weightedBlend(
                best.embedding, embedding, newWeight: blendWeight)
            profiles[best.profileId] = updated
            return updated
        }

        let label = nextSpeakerLabel()
        let p = VoiceProfile(label: label, isUser: false, embedding: embedding)
        profiles[p.profileId] = p
        return p
    }

    // MARK: - Private helpers

    private func nextSpeakerLabel() -> String {
        remoteCount += 1
        var n = remoteCount
        var label = ""
        repeat {
            n -= 1
            label = String(UnicodeScalar(UInt32(65 + (n % 26)))!) + label
            n /= 26
        } while n > 0
        return "Speaker \(label)"
    }

    /// Converts "Speaker A" → 1, "Speaker B" → 2, "Speaker AA" → 27, etc.
    private func labelOrdinal(of label: String) -> Int? {
        let prefix = "Speaker "
        guard label.hasPrefix(prefix) else { return nil }
        let suffix = label.dropFirst(prefix.count)
        guard !suffix.isEmpty else { return nil }
        var n = 0
        for ch in suffix.uppercased() {
            guard let ascii = ch.asciiValue, ascii >= 65, ascii < 91 else { return nil }
            n = n * 26 + Int(ascii - 64)
        }
        return n
    }
}

// MARK: - SpeakerMatcher

/// Pure-Swift cosine similarity utilities. No side effects.
public enum SpeakerMatcher {

    /// Cosine similarity in [0, 1]. Returns 0.0 if either vector has zero norm.
    public static func cosine(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dot: Float = 0
        var normA: Float = 0
        var normB: Float = 0
        vDSP_dotpr(a, 1, b, 1, &dot, vDSP_Length(a.count))
        vDSP_svesq(a, 1, &normA, vDSP_Length(a.count))
        vDSP_svesq(b, 1, &normB, vDSP_Length(b.count))
        let denom = normA.squareRoot() * normB.squareRoot()
        guard denom > 0 else { return 0 }
        return max(0, min(1, dot / denom))
    }

    /// Weighted blend of two embeddings.
    ///
    /// `newWeight` ∈ [0, 1] is the contribution of `new`:
    ///   0.0 → keep existing entirely, 1.0 → replace with new entirely.
    public static func weightedBlend(_ existing: [Float], _ new: [Float], newWeight: Float) -> [Float] {
        guard existing.count == new.count, !existing.isEmpty else { return existing }
        let w2 = max(0, min(1, newWeight))
        let w1 = 1.0 - w2
        var result = [Float](repeating: 0, count: existing.count)
        var temp   = [Float](repeating: 0, count: existing.count)
        var mw1 = w1
        var mw2 = w2
        vDSP_vsmul(existing, 1, &mw1, &result, 1, vDSP_Length(existing.count))
        vDSP_vsmul(new,      1, &mw2, &temp,   1, vDSP_Length(new.count))
        vDSP_vadd(result, 1, temp, 1, &result, 1, vDSP_Length(result.count))
        return result
    }

    /// Returns the best-matching profile above `threshold`, or nil.
    public static func best(
        for embedding: [Float],
        in profiles: [VoiceProfile],
        threshold: Float
    ) -> VoiceProfile? {
        profiles
            .filter { !$0.isUser && !$0.embedding.isEmpty }
            .map    { ($0, cosine($0.embedding, embedding)) }
            .filter { $0.1 >= threshold }
            .max    { $0.1 < $1.1 }
            .map    { $0.0 }
    }
}

// MARK: - DiarizeConfiguration

/// Configuration for the Diarize stage.
public struct DiarizeConfiguration: Sendable {
    /// URL of the ECAPA-TDNN ONNX model file.
    public let modelURL: URL
    /// Keychain identifier to decrypt audio files from Capture stage.
    public let encryptionKeyId: String
    /// Base cosine similarity threshold for speaker matching (0–1).
    /// Young profiles receive an additional adaptive boost of up to +0.05.
    public let matchThreshold: Float
    /// Label used for the local-channel speaker (device user).
    public let userLabel: String
    /// Minimum audio duration (seconds) for a reliable speaker embedding.
    /// Segments shorter than this use a context-padded window that borrows
    /// audio before the segment to reach this duration.
    public let minEmbeddingDuration: Float
    /// Confidence below which a segment is queued for retrospective re-attribution
    /// after pass 1, once all speaker profiles are fully populated.
    public let retroAttributionThreshold: Float

    public static let `default` = DiarizeConfiguration(
        modelURL: URL(fileURLWithPath: ""),
        encryptionKeyId: "com.voxema.app.capture-audio-key",
        matchThreshold: 0.75,
        userLabel: "You",
        minEmbeddingDuration: 1.5,
        retroAttributionThreshold: 0.60
    )

    public init(
        modelURL: URL,
        encryptionKeyId: String = "com.voxema.app.capture-audio-key",
        matchThreshold: Float = 0.75,
        userLabel: String = "You",
        minEmbeddingDuration: Float = 1.5,
        retroAttributionThreshold: Float = 0.60
    ) {
        self.modelURL = modelURL
        self.encryptionKeyId = encryptionKeyId
        self.matchThreshold = matchThreshold
        self.userLabel = userLabel
        self.minEmbeddingDuration = minEmbeddingDuration
        self.retroAttributionThreshold = retroAttributionThreshold
    }
}

// MARK: - DiarizeStage

/// Attributes each transcribed segment to a speaker.
///
/// Local-channel segments are always attributed to the device user.
/// Remote-channel segments use ECAPA-TDNN voice embeddings and cosine
/// similarity matching against an in-memory `VoiceProfileStore`.
///
/// ## Short-segment handling (improvement #3)
/// Segments shorter than `minEmbeddingDuration` now use a context-padded audio
/// window: audio is borrowed from before the segment to reach the minimum
/// duration, giving Whisper enough signal for a reliable embedding. Reuse of
/// the previous speaker is kept only as a last resort when no audio is available.
///
/// ## Adaptive threshold (improvement #4)
/// `VoiceProfileStore.matchOrCreate` applies a per-profile threshold boost of
/// up to +0.05 for profiles with fewer than 3 confirmed matches. This prevents
/// two distinct speakers from being merged before either profile is established.
///
/// ## Two-pass attribution (improvement #2)
/// Pass 1 (greedy): segments attributed as they arrive with weighted centroid
/// updates (improvement #1). Pass 2 (retrospective): low-confidence assignments
/// re-evaluated against the fully-populated final profiles.
public final class DiarizeStage: DiarizeStageProtocol {

    private let engineFactory: () -> EmbeddingEngineProtocol
    private let config: DiarizeConfiguration
    private let profilePersistence: (any SpeakerProfilePersistence)?
    private let log = VoxemaLogger.make(category: "diarize.stage")
    private var isCancelled = false

    private struct PendingRetro {
        let resultIndex: Int
        let embedding: [Float]
    }

    // MARK: - Init

    public convenience init(
        config: DiarizeConfiguration = .default,
        profilePersistence: (any SpeakerProfilePersistence)? = nil
    ) {
        self.init(engineFactory: { EmbeddingEngine() },
                  config: config,
                  profilePersistence: profilePersistence)
    }

    init(engineFactory: @escaping () -> EmbeddingEngineProtocol,
         config: DiarizeConfiguration = .default,
         profilePersistence: (any SpeakerProfilePersistence)? = nil) {
        self.engineFactory = engineFactory
        self.config = config
        self.profilePersistence = profilePersistence
    }

    // MARK: - DiarizeStageProtocol

    public func run(
        _ segments: [TranscribedSegment],
        audioStreams: [AudioStream]
    ) async throws -> [DiarizedSegment] {
        isCancelled = false
        guard !segments.isEmpty else { return [] }

        let store = VoiceProfileStore()

        // Seed with profiles from previous sessions
        if let persistence = profilePersistence {
            let stored = (try? persistence.loadRemoteProfiles()) ?? []
            if !stored.isEmpty {
                store.seed(stored)
                log.info("DiarizeStage: profiles seeded from persistence")
            }
        }

        let userProfile = store.userProfile(label: config.userLabel)

        var streamSamples: [AudioChannel: [Float]] = [:]
        for stream in audioStreams {
            if isCancelled { break }
            let encURL = URL(fileURLWithPath: stream.filePath)
            let samples = (try? AudioSampleDecoder.decode(
                from: encURL,
                encryptionKeyId: config.encryptionKeyId
            )) ?? []
            streamSamples[stream.channel] = samples
        }

        let engine = engineFactory()
        defer { engine.unloadModel() }

        if !audioStreams.isEmpty {
            do { try engine.loadModel(at: config.modelURL) } catch {
                log.error("EmbeddingEngine.loadModel failed — assigning temp labels")
            }
        }

        var results: [DiarizedSegment] = []
        results.reserveCapacity(segments.count)
        var lastRemoteProfile: VoiceProfile?
        var pendingRetro: [PendingRetro] = []

        // ── Pass 1: greedy attribution ───────────────────────────────────────

        for segment in segments {
            if isCancelled { break }

            let speaker: SpeakerIdentity

            switch segment.channel {
            case .local:
                speaker = SpeakerIdentity(
                    speakerId: userProfile.profileId,
                    label: userProfile.label,
                    isUser: true,
                    confidence: 1.0,
                    isKnown: true
                )

            case .remote:
                let segDuration = segment.endTime - segment.startTime
                let samples = streamSamples[.remote] ?? []

                // Context-padded window: for segments shorter than minEmbeddingDuration,
                // borrow audio from before the segment start so the embedding model
                // receives a full-length input. This replaces the simple "reuse last
                // speaker" heuristic and yields a real embedding even for brief replies.
                let windowEnd = segment.endTime
                let windowStart: Float
                if segDuration < config.minEmbeddingDuration {
                    let pad = config.minEmbeddingDuration - segDuration
                    windowStart = max(0, segment.startTime - pad)
                } else {
                    windowStart = segment.startTime
                }

                let slicedSamples = sliceSamples(
                    samples,
                    startTime: windowStart,
                    endTime: windowEnd
                )

                if slicedSamples.isEmpty, let prev = lastRemoteProfile {
                    // No audio available at all — fall back to last known speaker.
                    // Only reaches here when the audio stream is absent (e.g. tests,
                    // or a failed decrypt). In production this path is rarely taken.
                    speaker = SpeakerIdentity(
                        speakerId: prev.profileId,
                        label: prev.label,
                        isUser: false,
                        confidence: 0.0,
                        isKnown: false
                    )
                } else {
                    let embedding: [Float]
                    if slicedSamples.isEmpty {
                        embedding = [Float](repeating: 0, count: Int(VOXEMA_ECAPA_EMBEDDING_DIM))
                    } else {
                        embedding = (try? engine.embed(samples: slicedSamples))
                            ?? [Float](repeating: 0, count: Int(VOXEMA_ECAPA_EMBEDDING_DIM))
                    }

                    // Duration-weighted blend: longer segments shift the centroid more.
                    let blendWeight = min(0.45, max(0.15, segDuration / 10.0))

                    let profile = store.matchOrCreate(
                        embedding: embedding,
                        threshold: config.matchThreshold,
                        blendWeight: blendWeight
                    )
                    lastRemoteProfile = profile

                    let similarity = profile.embedding.isEmpty
                        ? 0
                        : SpeakerMatcher.cosine(profile.embedding, embedding)

                    speaker = SpeakerIdentity(
                        speakerId: profile.profileId,
                        label: profile.label,
                        isUser: false,
                        confidence: similarity,
                        isKnown: false
                    )

                    if similarity < config.retroAttributionThreshold {
                        pendingRetro.append(PendingRetro(
                            resultIndex: results.count,
                            embedding: embedding
                        ))
                    }
                }
            }

            results.append(DiarizedSegment(
                segmentId: segment.segmentId,
                startTime: segment.startTime,
                endTime:   segment.endTime,
                text:      segment.text,
                speaker:   speaker,
                channel:   segment.channel
            ))
        }

        // ── Pass 2: retrospective re-attribution ─────────────────────────────

        if !pendingRetro.isEmpty {
            let finalProfiles = store.allRemoteProfiles()
            for item in pendingRetro {
                guard let best = SpeakerMatcher.best(
                    for: item.embedding,
                    in: finalProfiles,
                    threshold: config.retroAttributionThreshold
                ) else { continue }

                let sim = SpeakerMatcher.cosine(best.embedding, item.embedding)
                let old = results[item.resultIndex]
                guard best.profileId != old.speaker.speakerId else { continue }

                results[item.resultIndex] = DiarizedSegment(
                    segmentId: old.segmentId,
                    startTime: old.startTime,
                    endTime:   old.endTime,
                    text:      old.text,
                    speaker:   SpeakerIdentity(
                        speakerId: best.profileId,
                        label:     best.label,
                        isUser:    false,
                        confidence: sim,
                        isKnown:   false
                    ),
                    channel: old.channel
                )
            }
            log.info("DiarizeStage retro-pass complete")
        }

        // Persist updated profiles for next session
        if let persistence = profilePersistence {
            for profile in store.allProfiles() where !profile.isUser {
                try? persistence.upsertProfile(profile)
            }
        }

        log.info("DiarizeStage complete")
        return results
    }

    public func cancel() {
        isCancelled = true
        log.info("DiarizeStage cancelled")
    }

    // MARK: - Private helpers

    private func sliceSamples(
        _ allSamples: [Float],
        startTime: Float,
        endTime: Float,
        sampleRate: Float = 16_000
    ) -> [Float] {
        guard !allSamples.isEmpty, endTime > startTime else { return [] }
        let start = Int(max(0, startTime * sampleRate))
        let end   = min(allSamples.count, Int(endTime * sampleRate))
        guard start < end else { return [] }
        return Array(allSamples[start ..< end])
    }
}
