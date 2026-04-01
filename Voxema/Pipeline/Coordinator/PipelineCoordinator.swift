import Foundation
import Combine
import Accelerate

/// Orchestrates the five pipeline stages sequentially.
///
/// ## Stage execution order
/// ```
/// Capture → Transcribe → Diarize → Summarize → Export
/// ```
///
/// ## Cross-stage rules enforced (from `docs/PIPELINE_CONTRACTS.md`)
/// 1. Stages receive immutable input and produce new output — no in-place mutation
/// 2. Stages do not call each other — all calls route through `PipelineCoordinator`
/// 3. Errors raised at stage boundaries as typed `PipelineError`
/// 4. Error messages never contain transcript text, audio content, or PII
/// 5. Models loaded only during their stage, unloaded after (8 GB discipline)
///
/// ## Thread safety
/// All state is `@MainActor`-isolated. Stage `run()` methods are `async` and may
/// execute on any executor; results are delivered back on the main actor.
@MainActor
public final class PipelineCoordinator: ObservableObject {

    // MARK: - Published State

    @Published public private(set) var state: PipelineState = .idle
    @Published public private(set) var progress: PipelineProgress = .initial

    // MARK: - Dependencies

    private let captureStage:    any CaptureStageProtocol
    private let transcribeStage: any TranscribeStageProtocol
    private let diarizeStage:    any DiarizeStageProtocol
    private let refineStage:     any RefineStageProtocol
    private let summarizeStage:  any SummarizeStageProtocol
    private let exportStage:     any ExportStageProtocol
    private let modelManager:    ModelManager

    private let log = VoxemaLogger.make(category: "pipeline")

    // MARK: - Init

    /// Designated initialiser. All stage dependencies are injected for production and testing.
    public init(
        captureStage:    any CaptureStageProtocol,
        transcribeStage: any TranscribeStageProtocol,
        diarizeStage:    any DiarizeStageProtocol,
        refineStage:     any RefineStageProtocol = RefineStage(),
        summarizeStage:  any SummarizeStageProtocol,
        exportStage:     any ExportStageProtocol,
        modelManager:    ModelManager? = nil
    ) {
        self.captureStage    = captureStage
        self.transcribeStage = transcribeStage
        self.diarizeStage    = diarizeStage
        self.refineStage     = refineStage
        self.summarizeStage  = summarizeStage
        self.exportStage     = exportStage
        // Resolve inside the @MainActor init body — default expressions are non-isolated
        self.modelManager    = modelManager ?? .shared
    }

    // MARK: - Recording Lifecycle

    /// Starts audio capture. Transitions from `.idle` to `.recording`.
    /// Calling when not `.idle` is a no-op.
    public func startRecording() async throws {
        guard state == .idle else {
            log.warning("startRecording called in non-idle state")
            return
        }
        log.info("pipeline recording starting")
        state = .recording
        do {
            try await captureStage.startCapture()
        } catch {
            let err = asPipelineError(error, fallback: .captureMicrophonePermissionDenied)
            state = .failed(err)
            throw err
        }
    }

    /// Stops capture and runs Transcribe → Diarize → Summarize → Export.
    /// Calling when not `.recording` is a no-op.
    public func stopRecording() async throws {
        guard state == .recording else {
            log.warning("stopRecording called in non-recording state")
            return
        }
        log.info("pipeline capture stopping")
        state = .stopping
        let streams: [AudioStream]
        do {
            streams = try await captureStage.stopCapture()
        } catch {
            let err = asPipelineError(error, fallback: .captureDiskSpaceInsufficient)
            state = .failed(err)
            throw err
        }
        try await runProcessingPipeline(streams: streams)
    }

    // MARK: - Cancellation

    /// Cancels the active stage and transitions to `.cancelled`.
    /// No-op if already idle, complete, cancelled, or failed.
    public func cancel() {
        switch state {
        case .idle, .complete, .cancelled, .failed:
            return
        case .recording, .stopping:
            captureStage.cancel()
        case .processing:
            transcribeStage.cancel()
            diarizeStage.cancel()
            refineStage.cancel()
            summarizeStage.cancel()
            exportStage.cancel()
        }
        log.info("pipeline cancelled")
        state = .cancelled
        progress = .initial
    }

    /// Resets a terminal state (`.failed`, `.complete`, `.cancelled`) back to `.idle`.
    /// Calling from a non-terminal state is a no-op.
    public func reset() {
        switch state {
        case .failed, .complete, .cancelled:
            log.info("pipeline reset to idle")
            state = .idle
            progress = .initial
        default:
            log.warning("reset called in non-terminal state")
        }
    }

    // MARK: - Processing Pipeline

    private func runProcessingPipeline(streams: [AudioStream]) async throws {

        // ── Transcribe ──────────────────────────────────────────────────
        log.info("stage transcribe starting")
        updateProgress(.transcribing(progress: 0))
        let rawSegments: [TranscribedSegment]
        do {
            rawSegments = try await transcribeStage.run(streams)
        } catch {
            let err = asPipelineError(error, fallback: .transcribeAudioFileCorrupt)
            state = .failed(err); throw err
        }
        // Secondary text-based filter: remove any remaining local-channel duplicates.
        let segments = filterAcousticBleed(from: rawSegments)
        log.info("stage transcribe complete", "segments=\(segments.count) (raw=\(rawSegments.count))")

        // ── Diarize ─────────────────────────────────────────────────────
        log.info("stage diarize starting")
        updateProgress(.diarizing(progress: 0))
        let diarized: [DiarizedSegment]
        do {
            diarized = try await diarizeStage.run(segments, audioStreams: streams)
        } catch {
            let err = asPipelineError(error, fallback: .diarizeAllSegmentsBelowThreshold)
            state = .failed(err); throw err
        }
        log.info("stage diarize complete", "segments=\(diarized.count)")

        // ── Refine ──────────────────────────────────────────────────────
        log.info("stage refine starting")
        updateProgress(.refining(progress: 0))
        let refined: [DiarizedSegment]
        do {
            refined = try await refineStage.run(diarized)
        } catch {
            let err = asPipelineError(error, fallback: .diarizeAllSegmentsBelowThreshold)
            state = .failed(err); throw err
        }
        log.info("stage refine complete", "segments=\(refined.count) (merged from \(diarized.count))")

        // ── Summarize ────────────────────────────────────────────────────
        log.info("stage summarize starting")
        updateProgress(.summarizing(progress: 0))
        let summary: MeetingSummary
        do {
            summary = try await summarizeStage.run(refined)
        } catch {
            let err = asPipelineError(error, fallback: .summarizeMalformedOutput)
            state = .failed(err); throw err
        }
        log.info("stage summarize complete")

        // ── Export ───────────────────────────────────────────────────────
        log.info("stage export starting")
        updateProgress(.exporting(progress: 0))
        let metadata = buildMetadata(segments: segments, summary: summary)
        let meeting: Meeting
        do {
            meeting = try await exportStage.run(
                ExportStageInput(
                    segments: refined,
                    summary: summary,
                    metadata: metadata,
                    audioFilePaths: streams.map(\.filePath)
                )
            )
        } catch {
            let err = asPipelineError(error, fallback: .exportDatabaseWriteFailure)
            state = .failed(err); throw err
        }
        log.info("stage export complete")

        log.info("pipeline complete")
        state = .complete(meetingId: meeting.meetingId)
        progress = PipelineProgress(currentStage: nil, overallFraction: 1.0)
    }

    // MARK: - Helpers

    private func updateProgress(_ stage: PipelineProcessingStage) {
        progress = .from(stage: stage)
        state = .processing(stage)
    }

    // MARK: - Acoustic bleed filters

    /// Primary filter — energy-based.
    ///
    /// Decrypts and measures RMS energy of each channel.
    /// If the local channel's energy is < `ratio` of the remote channel's energy,
    /// the user was not speaking (the mic only recorded acoustic bleed) and the
    /// entire local channel is dropped before transcription.
    ///
    /// Typical ratios:
    ///   - User silent, speakers playing:   0.02 – 0.10  → dropped  ✓
    ///   - User speaking actively:          0.40 – 2.00  → kept     ✓
    ///   - Headphone leakage + some speech: 0.15 – 0.40  → kept     ✓
    ///
    /// AudioSampleDecoder.decode is @MainActor (uses EncryptionManager), so we
    /// call it sequentially here on the main actor. The two file reads complete
    /// in < 200 ms for typical meeting recordings and do not block the UI
    /// because the coordinator is already suspended on an `await` at this point.
    private func filterSilentLocalChannel(
        _ streams: [AudioStream],
        ratio: Float = 0.25
    ) async -> [AudioStream] {
        let keyId = "com.voxema.app.capture-audio-key"
        var rms: [AudioChannel: Float] = [:]

        for stream in streams {
            let url = URL(fileURLWithPath: stream.filePath)
            guard let samples = try? AudioSampleDecoder.decode(
                from: url, encryptionKeyId: keyId),
                  !samples.isEmpty
            else { continue }
            var result: Float = 0
            vDSP_rmsqv(samples, 1, &result, vDSP_Length(samples.count))
            rms[stream.channel] = result
        }

        let localRMS  = rms[.local]  ?? 0
        let remoteRMS = rms[.remote] ?? 0
        guard remoteRMS > 0 else { return streams }

        let energyRatio = localRMS / remoteRMS
        log.info("channel energy computed", "ratio=\(String(format: "%.3f", energyRatio))")

        if energyRatio < ratio {
            log.info("local channel skipped — user was silent",
                     "ratio=\(String(format: "%.3f", energyRatio))")
            return streams.filter { $0.channel != .local }
        }
        return streams
    }

    /// Secondary filter — text-based.
    ///
    /// Removes any remaining local-channel segments that duplicate a remote segment.
    /// Uses character 4-gram similarity so Russian (and other morphologically rich)
    /// word-form variants are caught: "открывают"/"открывает", "отложило"/"отложил"
    /// share most 4-gram substrings even though they are different word forms.
    private func filterAcousticBleed(
        from segments: [TranscribedSegment],
        timeTolerance: Float = 15.0,
        similarityThreshold: Double = 0.35
    ) -> [TranscribedSegment] {
        let remote = segments.filter { $0.channel == .remote }
        guard !remote.isEmpty else { return segments }

        return segments.filter { seg in
            guard seg.channel == .local else { return true }
            guard !seg.text.trimmingCharacters(in: .whitespaces).isEmpty else { return false }

            let isDuplicate = remote.contains { rSeg in
                guard abs(seg.startTime - rSeg.startTime) <= timeTolerance else { return false }
                // Take the max of word-level and char-4-gram similarity.
                // Word-level handles exact duplicates; n-gram handles inflected variants.
                let sim = max(
                    oneSidedWordOverlap(seg.text, rSeg.text),
                    charNgramSimilarity(seg.text, rSeg.text)
                )
                return sim >= similarityThreshold
            }
            if isDuplicate {
                log.info("bleed segment removed", "t=\(seg.startTime)")
            }
            return !isDuplicate
        }
    }

    /// One-sided word overlap: |intersection| / min(|A|, |B|).
    private func oneSidedWordOverlap(_ a: String, _ b: String) -> Double {
        func words(_ s: String) -> Set<String> {
            Set(
                s.lowercased()
                    .components(separatedBy: .whitespacesAndNewlines)
                    .map { $0.trimmingCharacters(in: .punctuationCharacters) }
                    .filter { !$0.isEmpty }
            )
        }
        let wa = words(a)
        let wb = words(b)
        let smaller = Double(min(wa.count, wb.count))
        guard smaller > 0 else { return 0 }
        return Double(wa.intersection(wb).count) / smaller
    }

    /// One-sided character 4-gram similarity: |intersection| / min(|ngrams_A|, |ngrams_B|).
    ///
    /// Morphology-agnostic: inflected forms of the same root share most 4-gram substrings.
    /// Example: "открывают" and "открывает" share "откр","ткры","крыв","рыва","ывае","вает".
    private func charNgramSimilarity(_ a: String, _ b: String, n: Int = 4) -> Double {
        func ngrams(_ s: String) -> Set<String> {
            let chars = s.lowercased().unicodeScalars
                .filter { CharacterSet.letters.union(.decimalDigits).contains($0) }
                .map(Character.init)
            guard chars.count >= n else { return [] }
            var result = Set<String>()
            result.reserveCapacity(chars.count - n + 1)
            for i in 0 ... (chars.count - n) {
                result.insert(String(chars[i ..< i + n]))
            }
            return result
        }
        let ga = ngrams(a)
        let gb = ngrams(b)
        let smaller = Double(min(ga.count, gb.count))
        guard smaller > 0 else { return 0 }
        return Double(ga.intersection(gb).count) / smaller
    }

    private func asPipelineError(_ error: Error, fallback: PipelineError) -> PipelineError {
        (error as? PipelineError) ?? fallback
    }

    private func buildMetadata(segments: [TranscribedSegment], summary: MeetingSummary) -> MeetingMetadata {
        let wordCount = segments.reduce(0) { $0 + $1.text.split(separator: " ").count }
        let whisperModelId: String = {
            let id = AppPreferences.shared.whisperModelId
            if !id.isEmpty { return id }
            return modelManager.manifest.models
                .first { $0.family == .whisper && $0.isBundled }?.id ?? "whisper-tiny"
        }()
        return MeetingMetadata(
            whisperModel: whisperModelId,
            summaryProvider: summary.providerUsed.rawValue,
            languageDetected: segments.first?.language ?? "unknown",
            segmentCount: segments.count,
            wordCount: wordCount
        )
    }
}
