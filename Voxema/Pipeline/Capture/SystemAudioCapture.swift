import AVFoundation
import CoreAudio

/// Captures system audio (remote meeting participants) via the Core Audio tap API (macOS 14.2+).
///
/// Uses `CATapDescription` + `AudioHardwareCreateProcessTap` to install a global audio tap,
/// wraps it in an aggregate device, then points `AVAudioEngine` at that device so the engine
/// delivers `AVAudioPCMBuffer` objects without requiring a raw C I/O-proc callback.
///
/// This approach requires only the "System Audio Recording Only" TCC permission
/// (`NSAudioCaptureUsageDescription`), which is narrower than the full
/// "Screen & System Audio Recording" permission required by ScreenCaptureKit.
///
/// Output: 16 kHz mono Float32 PCM WAV file at the URL provided to `startCapture(to:)`.
@available(macOS 14.2, *)
final class SystemAudioCapture: NSObject, AudioCapturer {

    private var tapID: AudioObjectID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateDeviceID: AudioObjectID = AudioObjectID(kAudioObjectUnknown)
    private var engine: AVAudioEngine?
    private var fileWriter: AudioFileWriter?
    private let log = VoxemaLogger.make(category: "capture.system")

    // MARK: - AudioCapturer

    func startCapture(to url: URL) async throws {
        teardown()

        // 1. Create a global tap that captures all process audio output.
        let tapDescription = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        tapDescription.name = "VoxemaTap"
        tapDescription.muteBehavior = .unmuted
        tapDescription.isPrivate = true

        var newTapID = AudioObjectID(kAudioObjectUnknown)
        var status = AudioHardwareCreateProcessTap(tapDescription, &newTapID)
        guard status == noErr, newTapID != kAudioObjectUnknown else {
            log.error("AudioHardwareCreateProcessTap failed — permission denied or unavailable")
            throw PipelineError.captureSystemAudioPermissionDenied
        }
        tapID = newTapID

        guard let tapUID = tapPropertyUID(for: tapID) else {
            log.error("Failed to read tap UID after creation")
            teardown()
            throw PipelineError.captureSystemAudioPermissionDenied
        }

        // 2. Wrap the tap in a private aggregate device so Core Audio presents it
        //    as a regular audio input device to AVAudioEngine.
        let taps: [[String: Any]] = [[
            kAudioSubTapUIDKey:              tapUID,
            kAudioSubTapDriftCompensationKey: true,
        ]]
        let aggProps: [String: Any] = [
            kAudioAggregateDeviceNameKey:         "VoxemaAggregateDevice",
            kAudioAggregateDeviceUIDKey:          "com.voxema.app.aggregate-\(tapUID)",
            kAudioAggregateDeviceTapListKey:      taps,
            kAudioAggregateDeviceTapAutoStartKey: false,
            kAudioAggregateDeviceIsPrivateKey:    true,
        ]

        var newAggID = AudioObjectID(kAudioObjectUnknown)
        status = AudioHardwareCreateAggregateDevice(aggProps as CFDictionary, &newAggID)
        guard status == noErr, newAggID != kAudioObjectUnknown else {
            log.error("AudioHardwareCreateAggregateDevice failed")
            teardown()
            throw PipelineError.captureSystemAudioPermissionDenied
        }
        aggregateDeviceID = newAggID

        // 3. Create an AVAudioEngine and redirect its input node to the aggregate device.
        let newEngine = AVAudioEngine()

        // `audioUnit` is the underlying AUHAL AudioUnit of the input node.
        // Setting kAudioOutputUnitProperty_CurrentDevice is the standard macOS way to
        // select a specific hardware device for AVAudioEngine input.
        guard let inputAudioUnit = newEngine.inputNode.audioUnit else {
            log.error("AVAudioEngine inputNode has no AudioUnit")
            teardown()
            throw PipelineError.captureSystemAudioPermissionDenied
        }

        var deviceID = aggregateDeviceID
        let setStatus = AudioUnitSetProperty(
            inputAudioUnit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &deviceID,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )
        guard setStatus == noErr else {
            log.error("AudioUnitSetProperty(CurrentDevice) failed")
            teardown()
            throw PipelineError.captureSystemAudioPermissionDenied
        }

        // 4. Prepare the output WAV writer (AudioFileWriter resamples to 16 kHz mono).
        let outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16_000,
            channels: 1,
            interleaved: false
        )!
        let writer: AudioFileWriter
        do {
            writer = try AudioFileWriter(url: url, outputFormat: outputFormat)
        } catch {
            log.error("AudioFileWriter init failed")
            teardown()
            throw error
        }
        fileWriter = writer

        // 5. Install a tap on the engine's input node to receive audio buffers.
        //    The format is read from the node after the device redirect above.
        let inputFormat = newEngine.inputNode.outputFormat(forBus: 0)
        newEngine.inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak writer] buffer, _ in
            writer?.write(buffer)
        }

        // 6. Start the engine — this activates the tap and begins audio delivery.
        do {
            try newEngine.start()
        } catch {
            log.error("AVAudioEngine start failed")
            teardown()
            throw PipelineError.captureSystemAudioPermissionDenied
        }

        engine = newEngine
        log.info("SystemAudioCapture started (Core Audio tap via AVAudioEngine)")
    }

    func stopCapture() async throws -> TimeInterval {
        let duration = fileWriter?.duration ?? 0
        // Bridge to a plain GCD thread so that AVAudioEngine.stop(),
        // AudioHardwareDestroyAggregateDevice(), and AudioHardwareDestroyProcessTap()
        // can never run on or dispatch_sync back to the main thread.
        // withCheckedContinuation suspends the Swift async context while GCD does the work.
        let cap = self
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            DispatchQueue.global(qos: .userInitiated).async {
                cap.teardown()
                cont.resume()
            }
        }
        log.info("SystemAudioCapture stopped")
        return duration
    }

    func cancel() {
        // cancel() is synchronous and called from PipelineCoordinator.cancel() (@MainActor).
        // Dispatch teardown asynchronously so the main thread is never blocked.
        let cap = self
        DispatchQueue.global(qos: .userInitiated).async { cap.teardown() }
        log.info("SystemAudioCapture cancelled")
    }

    // MARK: - Private helpers

    private func teardown() {
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil

        fileWriter?.close()
        fileWriter = nil

        if aggregateDeviceID != kAudioObjectUnknown {
            AudioHardwareDestroyAggregateDevice(aggregateDeviceID)
            aggregateDeviceID = AudioObjectID(kAudioObjectUnknown)
        }

        if tapID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = AudioObjectID(kAudioObjectUnknown)
        }
    }

    /// Returns the UID string of an `AudioObjectID` tap, or `nil` on failure.
    private func tapPropertyUID(for id: AudioObjectID) -> String? {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyUID,
            mScope:    kAudioObjectPropertyScopeGlobal,
            mElement:  kAudioObjectPropertyElementMain
        )
        var size = UInt32(MemoryLayout<CFString>.stride)
        var uid: CFString = "" as CFString
        let status = withUnsafeMutablePointer(to: &uid) { ptr in
            AudioObjectGetPropertyData(id, &addr, 0, nil, &size, ptr)
        }
        return status == noErr ? (uid as String) : nil
    }
}
