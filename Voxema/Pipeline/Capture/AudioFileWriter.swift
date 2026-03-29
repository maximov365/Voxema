import AVFoundation

/// Thread-safe audio file writer with on-the-fly format conversion.
///
/// Converts incoming `AVAudioPCMBuffer` samples from any format to the `outputFormat`
/// (16 kHz mono Float32) and appends them to a WAV file. Used by both `SystemAudioCapture`
/// and `MicrophoneCapture`.
///
/// - Thread safety: `write(_:)` is safe to call from any queue. Internally serialises
///   all writes on a private queue.
/// - Duration: accumulated from `frameCount / sampleRate`; available after `close()`.
final class AudioFileWriter {

    let outputFormat: AVAudioFormat
    private var file: AVAudioFile?
    private var converter: AVAudioConverter?
    private let queue = DispatchQueue(label: "com.voxema.app.audiofilewriter", qos: .userInitiated)
    private var totalFrames: AVAudioFramePosition = 0

    /// Accumulated recording duration in seconds. Accurate after `close()`.
    var duration: TimeInterval { TimeInterval(totalFrames) / outputFormat.sampleRate }

    /// Creates a writer that converts incoming audio to `outputFormat` and writes to `url`.
    init(url: URL, outputFormat: AVAudioFormat) throws {
        self.outputFormat = outputFormat
        self.file = try AVAudioFile(
            forWriting: url,
            settings: outputFormat.settings,
            commonFormat: outputFormat.commonFormat,
            interleaved: outputFormat.isInterleaved
        )
    }

    /// Converts `buffer` to `outputFormat` and appends to the file.
    /// No-ops silently on conversion or write errors to avoid breaking the capture loop.
    func write(_ buffer: AVAudioPCMBuffer) {
        let input = buffer.format

        let outputBuffer: AVAudioPCMBuffer

        if input.sampleRate == outputFormat.sampleRate &&
            input.channelCount == outputFormat.channelCount &&
            input.commonFormat == outputFormat.commonFormat {
            // Formats match — write directly without conversion
            outputBuffer = buffer
        } else {
            // Build or reuse converter
            if converter?.inputFormat != input {
                guard let conv = AVAudioConverter(from: input, to: outputFormat) else { return }
                converter = conv
            }
            guard let conv = converter else { return }

            // Compute output frame count (proportional to sample rate ratio)
            let ratio = outputFormat.sampleRate / input.sampleRate
            let outputFrameCapacity = AVAudioFrameCount(ceil(Double(buffer.frameLength) * ratio)) + 1
            guard let converted = AVAudioPCMBuffer(pcmFormat: outputFormat,
                                                    frameCapacity: outputFrameCapacity) else { return }

            var inputConsumed = false
            var conversionError: NSError?
            conv.convert(to: converted, error: &conversionError) { _, outStatus in
                if inputConsumed {
                    outStatus.pointee = .noDataNow
                    return nil
                }
                inputConsumed = true
                outStatus.pointee = .haveData
                return buffer
            }
            if conversionError != nil || converted.frameLength == 0 { return }
            outputBuffer = converted
        }

        queue.async { [weak self] in
            guard let self, let file = self.file else { return }
            try? file.write(from: outputBuffer)
            self.totalFrames += AVAudioFramePosition(outputBuffer.frameLength)
        }
    }

    /// Closes the file. Subsequent `write(_:)` calls are silently ignored.
    func close() {
        queue.sync { file = nil }
    }
}
