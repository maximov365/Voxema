import AVFoundation
import ScreenCaptureKit

/// Captures system audio (remote meeting participants) via ScreenCaptureKit.
///
/// Requires the Screen Recording privacy permission.
/// Output: 16 kHz mono Float32 PCM WAV file at the URL provided to `startCapture(to:)`.
final class SystemAudioCapture: NSObject, AudioCapturer {

    private var stream: SCStream?
    private var fileWriter: AudioFileWriter?
    private var outputURL: URL?
    private let log = VoxemaLogger.make(category: "capture.system")

    private let processingQueue = DispatchQueue(
        label: "com.voxema.app.syscapture.audio",
        qos: .userInitiated
    )

    func startCapture(to url: URL) async throws {
        outputURL = url

        // Obtain available content — this triggers the Screen Recording permission prompt
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.current
        } catch {
            log.error("SCShareableContent.current failed — permission denied or unavailable")
            throw PipelineError.captureScreenRecordingPermissionDenied
        }

        guard let display = content.displays.first else {
            log.error("No displays found — cannot create SCStream")
            throw PipelineError.captureScreenRecordingPermissionDenied
        }

        let filter = SCContentFilter(display: display, excludingWindows: [])

        let config = SCStreamConfiguration()
        config.capturesAudio = true
        config.excludesCurrentProcessAudio = true
        // SCStream requires non-zero pixel dimensions even for audio-only capture
        config.width = 2
        config.height = 2
        config.minimumFrameInterval = CMTime(value: 1, timescale: 1)

        let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16_000,
            channels: 1,
            interleaved: false
        )!

        fileWriter = try AudioFileWriter(url: url, outputFormat: targetFormat)

        let newStream = SCStream(filter: filter, configuration: config, delegate: nil)
        do {
            try newStream.addStreamOutput(self, type: .audio, sampleHandlerQueue: processingQueue)
            try await newStream.startCapture()
        } catch {
            log.error("SCStream.startCapture failed — permission or entitlement issue")
            fileWriter = nil
            throw PipelineError.captureScreenRecordingPermissionDenied
        }

        stream = newStream
        log.info("SystemAudioCapture started")
    }

    func stopCapture() async throws -> TimeInterval {
        guard let activeStream = stream else { return 0 }
        do {
            try await activeStream.stopCapture()
        } catch {
            log.error("SCStream.stopCapture failed")
        }
        stream = nil
        let duration = fileWriter?.duration ?? 0
        fileWriter?.close()
        fileWriter = nil
        log.info("SystemAudioCapture stopped")
        return duration
    }

    func cancel() {
        let streamToStop = stream
        stream = nil
        fileWriter?.close()
        fileWriter = nil
        Task { try? await streamToStop?.stopCapture() }
        log.info("SystemAudioCapture cancelled")
    }
}

// MARK: - SCStreamOutput

extension SystemAudioCapture: SCStreamOutput {
    func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of type: SCStreamOutputType
    ) {
        guard type == .audio, let writer = fileWriter else { return }
        guard let buffer = sampleBuffer.asPCMBuffer() else { return }
        writer.write(buffer)
    }
}

// MARK: - CMSampleBuffer helpers

private extension CMSampleBuffer {
    /// Converts a PCM `CMSampleBuffer` to `AVAudioPCMBuffer`.
    func asPCMBuffer() -> AVAudioPCMBuffer? {
        guard let formatDesc = formatDescription else { return nil }
        let format = AVAudioFormat(cmAudioFormatDescription: formatDesc)

        let frameCount = AVAudioFrameCount(numSamples)
        guard frameCount > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return nil }
        buffer.frameLength = frameCount

        let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(
            self,
            at: 0,
            frameCount: Int32(frameCount),
            into: buffer.mutableAudioBufferList
        )
        return status == noErr ? buffer : nil
    }
}
