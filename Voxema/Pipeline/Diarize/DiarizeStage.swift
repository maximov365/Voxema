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
        // withUnsafeFileSystemRepresentation provides the POSIX UTF-8 path needed
        // by both the MFCC fallback (ignores it) and CoreML model loading.
        // Empty path is valid — voxema_ecapa_coreml.m skips CoreML init and
        // falls back to MFCC embeddings automatically.
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
/// Persistence via GRDB is deferred to TASK-10.
public struct VoiceProfile: Equatable, Sendable {
    public let profileId: UUID
    /// Human-readable label: user name or temporary "Speaker A", "Speaker B", …
    public let label: String
    /// True for the local-channel speaker (always the device user).
    public let isUser: Bool
    /// Accumulated embedding (updated as more segments are observed).
    public var embedding: [Float]

    public init(profileId: UUID = UUID(), label: String, isUser: Bool, embedding: [Float] = []) {
        self.profileId = profileId
        self.label = label
        self.isUser = isUser
        self.embedding = embedding
    }
}

// MARK: - VoiceProfileStore

/// In-memory store for VoiceProfile objects.
/// One store is created per pipeline run; cross-run persistence is deferred.
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

    /// Returns a profile whose embedding is close to `embedding` within `threshold`,
    /// or creates a new profile with the next alphabetic label ("Speaker A", "B", …).
    ///
    /// `blendWeight` controls how strongly the new embedding updates the stored profile
    /// centroid: 0 = keep old, 1 = replace entirely. Use a value derived from segment
    /// duration so that long, confident segments move the centroid more than short ones.
    public func matchOrCreate(
        embedding: [Float],
        threshold: Float,
        blendWeight: Float = 0.3
    ) -> VoiceProfile {
        let best = profiles.values
            .filter { !$0.isUser && !$0.embedding.isEmpty }
            .max { SpeakerMatcher.cosine($0.embedding, embedding) < SpeakerMatcher.cosine($1.embedding, embedding) }

        if let best, SpeakerMatcher.cosine(best.embedding, embedding) >= threshold {
            // Update stored centroid with a weighted blend: longer / more confident
            // segments contribute more, preventing noisy short segments from
            // distorting the profile established by high-quality audio.
            var updated = best
            updated.embedding = SpeakerMatcher.weightedBlend(
                best.embedding, embedding, newWeight: blendWeight)
            profiles[best.profileId] = updated
            return updated
        }

        // Create new profile with next alphabetic label
        let label = nextSpeakerLabel()
        let p = VoiceProfile(label: label, isUser: false, embedding: embedding)
        profiles[p.profileId] = p
        return p
    }

    private func nextSpeakerLabel() -> String {
        remoteCount += 1
        // A=1, B=2, … Z=26, AA=27, …
        var n = remoteCount
        var label = ""
        repeat {
            n -= 1
            label = String(UnicodeScalar(UInt32(65 + (n % 26)))!) + label
            n /= 26
        } while n > 0
        return "Speaker \(label)"
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
    /// `newWeight` is the contribution of `new` in [0, 1]:
    ///   - 0.0 → result = existing (no update)
    ///   - 0.5 → equal blend (equivalent to the old running average)
    ///   - 1.0 → result = new (full replacement)
    ///
    /// Typical call: pass `newWeight` derived from segment duration so that
    /// longer, higher-quality segments move the profile centroid more.
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
    /// Cosine similarity threshold for speaker matching (0–1, architecture spec: 0.75).
    public let matchThreshold: Float
    /// Label used for the local-channel speaker (device user).
    public let userLabel: String
    /// Minimum segment duration (seconds) required to extract a speaker embedding.
    /// Segments shorter than this threshold reuse the last known remote speaker
    /// instead of computing a noisy embedding from too few audio frames.
    public let minEmbeddingDuration: Float
    /// Confidence below which a segment is a candidate for retrospective re-attribution.
    /// After the first pass, low-confidence assignments are re-evaluated against the
    /// final (fully-populated) speaker profiles, correcting early misattributions.
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
/// Audio samples are loaded once per stream (not per segment) for efficiency.
///
/// ## Two-pass attribution
/// Pass 1 (greedy): segments are attributed as they arrive, updating speaker
/// profile centroids with a duration-weighted blend after each match.
///
/// Pass 2 (retrospective): segments whose confidence fell below
/// `retroAttributionThreshold` are re-evaluated against the fully-populated
/// final profiles. This corrects early misattributions that occurred before
/// profiles were well-established — common for the first 1–2 utterances of
/// each speaker.
public final class DiarizeStage: DiarizeStageProtocol {

    private let engineFactory: () -> EmbeddingEngineProtocol
    private let config: DiarizeConfiguration
    private let log = VoxemaLogger.make(category: "diarize.stage")
    private var isCancelled = false

    // Holds the index and embedding for a segment that may need re-attribution.
    private struct PendingRetro {
        let resultIndex: Int
        let embedding: [Float]
    }

    // MARK: - Init

    public convenience init(config: DiarizeConfiguration = .default) {
        self.init(engineFactory: { EmbeddingEngine() }, config: config)
    }

    init(engineFactory: @escaping () -> EmbeddingEngineProtocol,
         config: DiarizeConfiguration = .default) {
        self.engineFactory = engineFactory
        self.config = config
    }

    // MARK: - DiarizeStageProtocol

    public func run(
        _ segments: [TranscribedSegment],
        audioStreams: [AudioStream]
    ) async throws -> [DiarizedSegment] {
        isCancelled = false
        guard !segments.isEmpty else { return [] }

        let store = VoiceProfileStore()
        let userProfile = store.userProfile(label: config.userLabel)

        // Pre-decode audio streams indexed by channel for efficient slice access
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

        // Load embedding model once for the entire run
        let engine = engineFactory()
        defer { engine.unloadModel() }

        if !audioStreams.isEmpty {
            do { try engine.loadModel(at: config.modelURL) } catch {
                // Model unavailable — all remote speakers get new temp labels (no match)
                log.error("EmbeddingEngine.loadModel failed — assigning temp labels")
            }
        }

        var results: [DiarizedSegment] = []
        results.reserveCapacity(segments.count)

        // Tracks the last successfully matched remote speaker so that very short
        // segments (below minEmbeddingDuration) can reuse it rather than
        // producing a noisy embedding that may create a spurious new profile.
        var lastRemoteProfile: VoiceProfile?

        // Segments that may benefit from retrospective re-attribution after the
        // first pass, once all speaker profiles are fully populated.
        var pendingRetro: [PendingRetro] = []

        // ── Pass 1: greedy attribution ───────────────────────────────────────

        for segment in segments {
            if isCancelled { break }

            let speaker: SpeakerIdentity

            switch segment.channel {
            case .local:
                // Local channel always attributed to the device user
                speaker = SpeakerIdentity(
                    speakerId: userProfile.profileId,
                    label: userProfile.label,
                    isUser: true,
                    confidence: 1.0,
                    isKnown: true
                )

            case .remote:
                let segDuration = segment.endTime - segment.startTime

                if segDuration < config.minEmbeddingDuration, let prev = lastRemoteProfile {
                    // Segment too short for a reliable embedding — reuse the
                    // previous speaker rather than risking a mis-classification.
                    speaker = SpeakerIdentity(
                        speakerId: prev.profileId,
                        label: prev.label,
                        isUser: false,
                        confidence: 0.0,
                        isKnown: false
                    )
                } else {
                    let samples = streamSamples[.remote] ?? []
                    let slicedSamples = sliceSamples(
                        samples,
                        startTime: segment.startTime,
                        endTime: segment.endTime
                    )

                    let embedding: [Float]
                    if slicedSamples.isEmpty {
                        embedding = [Float](repeating: 0, count: Int(VOXEMA_ECAPA_EMBEDDING_DIM))
                    } else {
                        embedding = (try? engine.embed(samples: slicedSamples))
                            ?? [Float](repeating: 0, count: Int(VOXEMA_ECAPA_EMBEDDING_DIM))
                    }

                    // Blend weight: longer segments move the profile centroid more.
                    // Range [0.15, 0.45]: short (1.5 s) → 0.17, medium (3 s) → 0.24,
                    // long (10 s) → 0.45. This prevents noisy short segments from
                    // distorting well-established profile centroids.
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

                    // Queue for retrospective check if confidence is low: the profile
                    // may have been sparse at attribution time but is now better-defined.
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
        // Re-evaluate low-confidence remote segments against the final profiles.
        // Only update if a *different* profile scores higher than retroThreshold,
        // preventing pointless reassignment and instability.

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

                // Only re-attribute if this is a genuinely different, better match
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

        log.info("DiarizeStage complete")
        return results
    }

    public func cancel() {
        isCancelled = true
        log.info("DiarizeStage cancelled")
    }

    // MARK: - Private helpers

    /// Extracts audio samples from `allSamples` for the time window [startTime, endTime] (seconds).
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
