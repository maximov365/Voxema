import Foundation

// MARK: - RefineConfiguration

/// Configuration for the Refine stage.
public struct RefineConfiguration: Sendable {
    /// Maximum silence gap (seconds) between two consecutive same-speaker segments
    /// that will be merged into a single block. Gaps equal to or larger than this
    /// value force a new block even for the same speaker, creating a natural
    /// paragraph break in the displayed transcript.
    public let mergeGapSeconds: Float

    public static let `default` = RefineConfiguration(mergeGapSeconds: 1.5)

    public init(mergeGapSeconds: Float = 1.5) {
        self.mergeGapSeconds = mergeGapSeconds
    }
}

// MARK: - RefineStage

/// Post-diarization transcript cleanup stage.
///
/// ## What it does
/// 1. **Sorts** all segments by `startTime` (Whisper occasionally emits out-of-order chunks).
/// 2. **Merges** consecutive segments from the same speaker when the silence gap between
///    them is shorter than `mergeGapSeconds`. Short Whisper chunks ("Uh", "right", "OK")
///    are collapsed into the surrounding turn, producing readable speaker blocks.
/// 3. **Paragraph breaks** — when the same speaker pauses for ≥ `mergeGapSeconds`, a new
///    block is emitted, creating a visual paragraph break in the UI transcript list.
/// 4. **Text cleanup** — each merged block is trimmed, its first letter capitalised, and
///    a terminal punctuation mark added if none is present.
///
/// The stage is synchronous internally but exposed as `async` to fit the pipeline contract.
/// It never throws and always produces at least one segment when given non-empty input.
public final class RefineStage: RefineStageProtocol {

    private let config: RefineConfiguration
    private let log = VoxemaLogger.make(category: "refine.stage")

    public init(config: RefineConfiguration = .default) {
        self.config = config
    }

    // MARK: - RefineStageProtocol

    public func run(_ segments: [DiarizedSegment]) async throws -> [DiarizedSegment] {
        guard !segments.isEmpty else { return [] }

        let sorted = segments.sorted { $0.startTime < $1.startTime }
        var result: [DiarizedSegment] = []
        result.reserveCapacity(sorted.count)

        // Accumulator for the current in-progress speaker block
        var accText     = sorted[0].text
        var accStart    = sorted[0].startTime
        var accEnd      = sorted[0].endTime
        var accSpeaker  = sorted[0].speaker
        var accChannel  = sorted[0].channel
        var accLanguage = sorted[0].language

        for seg in sorted.dropFirst() {
            let gap        = seg.startTime - accEnd
            let sameSpeaker = seg.speaker.speakerId == accSpeaker.speakerId

            if sameSpeaker && gap < config.mergeGapSeconds {
                // Same speaker, short gap → extend the current block
                accText += " " + seg.text
                accEnd   = seg.endTime
            } else {
                // Different speaker or long pause → emit the accumulated block
                result.append(emit(text: accText, start: accStart, end: accEnd,
                                   speaker: accSpeaker, channel: accChannel, language: accLanguage))
                accText     = seg.text
                accStart    = seg.startTime
                accEnd      = seg.endTime
                accSpeaker  = seg.speaker
                accChannel  = seg.channel
                accLanguage = seg.language
            }
        }

        // Emit the final accumulated block
        result.append(emit(text: accText, start: accStart, end: accEnd,
                           speaker: accSpeaker, channel: accChannel, language: accLanguage))

        log.info("RefineStage complete")
        return result
    }

    public func cancel() {
        // Synchronous computation — nothing to interrupt
    }

    // MARK: - Private helpers

    private func emit(
        text: String, start: Float, end: Float,
        speaker: SpeakerIdentity, channel: AudioChannel, language: String
    ) -> DiarizedSegment {
        DiarizedSegment(
            segmentId: UUID(),
            startTime: start,
            endTime:   end,
            text:      cleanText(text),
            speaker:   speaker,
            channel:   channel,
            language:  language
        )
    }

    /// Trims, capitalises the first character, and ensures terminal punctuation.
    private func cleanText(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespaces)
        guard !s.isEmpty else { return s }

        // Capitalise first letter without disturbing the rest
        let first = s.unicodeScalars.first!
        if CharacterSet.lowercaseLetters.contains(first) {
            s = s.prefix(1).uppercased() + s.dropFirst()
        }

        // Add a period when no sentence-ending punctuation is present
        if let last = s.last, !".?!…".contains(last) {
            s += "."
        }

        return s
    }
}
