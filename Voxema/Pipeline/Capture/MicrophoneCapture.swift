import AVFoundation

/// Captures the local user's microphone via AVAudioEngine.
///
/// Requires the Microphone privacy permission.
/// Output: 16 kHz mono Float32 PCM WAV file at the URL provided to `startCapture(to:)`.
final class MicrophoneCapture: AudioCapturer {

    private let engine = AVAudioEngine()
    private var fileWriter: AudioFileWriter?
    private let log = VoxemaLogger.make(category: "capture.microphone")

    func startCapture(to url: URL) async throws {
        try await requestMicrophonePermission()

        let inputNode = engine.inputNode
        let inputFormat = inputNode.inputFormat(forBus: 0)

        let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16_000,
            channels: 1,
            interleaved: false
        )!

        let writer = try AudioFileWriter(url: url, outputFormat: targetFormat)
        fileWriter = writer

        inputNode.installTap(onBus: 0, bufferSize: 4_096, format: inputFormat) { [weak writer] buffer, _ in
            writer?.write(buffer)
        }

        do {
            try engine.start()
        } catch {
            inputNode.removeTap(onBus: 0)
            fileWriter?.close()
            fileWriter = nil
            log.error("AVAudioEngine.start failed — microphone unavailable")
            throw PipelineError.captureMicrophonePermissionDenied
        }

        log.info("MicrophoneCapture started")
    }

    func stopCapture() async throws -> TimeInterval {
        let duration = fileWriter?.duration ?? 0
        // Bridge to a plain GCD thread so AVAudioEngine.stop() (which can
        // dispatch_sync back to the main thread internally) never blocks the
        // main actor, regardless of what context called stopCapture().
        let cap = self
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            DispatchQueue.global(qos: .userInitiated).async {
                cap.engine.inputNode.removeTap(onBus: 0)
                cap.engine.stop()
                cap.fileWriter?.close()
                cap.fileWriter = nil
                cont.resume()
            }
        }
        log.info("MicrophoneCapture stopped")
        return duration
    }

    func cancel() {
        // cancel() is synchronous — dispatch teardown asynchronously.
        let cap = self
        DispatchQueue.global(qos: .userInitiated).async {
            cap.engine.inputNode.removeTap(onBus: 0)
            cap.engine.stop()
            cap.fileWriter?.close()
            cap.fileWriter = nil
        }
        log.info("MicrophoneCapture cancelled")
    }

    // MARK: - Permission

    private func requestMicrophonePermission() async throws {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return
        case .denied, .restricted:
            throw PipelineError.captureMicrophonePermissionDenied
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .audio)
            if !granted { throw PipelineError.captureMicrophonePermissionDenied }
        @unknown default:
            return
        }
    }
}
