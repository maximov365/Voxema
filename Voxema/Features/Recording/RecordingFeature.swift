import SwiftUI

// MARK: - RecordingView

/// Full-area view shown while `pipelineState == .recording`.
struct RecordingView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(spacing: 20) {
            pulsatingRing
            timerLabel
            Text("Recording in progress")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .kerning(0.4)
            channelIndicators
            stopButton
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Components

    private var pulsatingRing: some View {
        ZStack {
            Circle()
                .stroke(Color.red.opacity(0.25), lineWidth: 2)
                .frame(width: 92, height: 92)
            Circle()
                .fill(Color.red.opacity(0.12))
                .frame(width: 92, height: 92)
            Circle()
                .fill(Color.red)
                .frame(width: 38, height: 38)
        }
    }

    private var timerLabel: some View {
        Text(formattedDuration)
            .font(.system(size: 34, weight: .ultraLight, design: .default))
            .monospacedDigit()
            .foregroundStyle(.primary)
    }

    private var channelIndicators: some View {
        HStack(spacing: 16) {
            ChannelPill(label: "Microphone", color: .green)
            ChannelPill(label: "System audio", color: .blue)
        }
    }

    private var stopButton: some View {
        Button {
            Task { await appState.stopRecording() }
        } label: {
            HStack(spacing: 7) {
                RoundedRectangle(cornerRadius: 2)
                    .frame(width: 10, height: 10)
                Text("Stop Recording")
                    .font(.system(size: 13, weight: .semibold))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 9)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    private var formattedDuration: String {
        let total = Int(appState.recordingDuration)
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}

// MARK: - ProcessingView

/// Full-area view shown while `pipelineState == .processing(...)`.
struct ProcessingView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(spacing: 22) {
            VStack(spacing: 6) {
                Text("Processing your meeting")
                    .font(.system(size: 16, weight: .semibold))
                Text(durationSubtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            VStack(spacing: 8) {
                ForEach(PipelineStep.allCases) { step in
                    PipelineStepRow(step: step, currentStage: currentStage)
                }
            }
            .frame(width: 310)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var currentStage: PipelineProcessingStage? {
        if case .processing(let s) = appState.pipelineState { return s }
        return nil
    }

    private var durationSubtitle: String {
        let total = Int(appState.recordingDuration)
        let m = total / 60; let s = total % 60
        let dur = s == 0 ? "\(m) min" : "\(m)m \(s)s"
        return "\(dur) · estimated 1–2 min remaining"
    }
}

// MARK: - PipelineStepRow

private enum PipelineStep: Int, CaseIterable, Identifiable {
    case transcribing, diarizing, summarizing, exporting
    var id: Int { rawValue }

    var label: String {
        switch self {
        case .transcribing: return "Transcription"
        case .diarizing:    return "Speaker identification"
        case .summarizing:  return "Summary"
        case .exporting:    return "Saving"
        }
    }

    var processingStage: PipelineProcessingStage {
        switch self {
        case .transcribing: return .transcribing(progress: 0)
        case .diarizing:    return .diarizing(progress: 0)
        case .summarizing:  return .summarizing(progress: 0)
        case .exporting:    return .exporting(progress: 0)
        }
    }

    func status(current: PipelineProcessingStage?) -> StepStatus {
        guard let current else { return .waiting }
        if current.index > self.rawValue { return .done }
        if current.index == self.rawValue { return .active }
        return .waiting
    }
}

private enum StepStatus { case done, active, waiting }

private struct PipelineStepRow: View {
    let step: PipelineStep
    let currentStage: PipelineProcessingStage?

    var body: some View {
        let status = step.status(current: currentStage)
        HStack(spacing: 10) {
            statusIcon(status)
            Text(step.label)
                .font(.system(size: 13))
                .foregroundStyle(status == .waiting ? .tertiary : .primary)
            Spacer()
            statusTag(status)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
        )
    }

    @ViewBuilder
    private func statusIcon(_ status: StepStatus) -> some View {
        ZStack {
            Circle()
                .fill(iconBackground(status))
                .frame(width: 26, height: 26)
            switch status {
            case .done:
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.green)
            case .active:
                ProgressView()
                    .scaleEffect(0.6)
                    .progressViewStyle(.circular)
            case .waiting:
                Circle()
                    .fill(Color(nsColor: .tertiaryLabelColor))
                    .frame(width: 6, height: 6)
            }
        }
    }

    private func iconBackground(_ status: StepStatus) -> Color {
        switch status {
        case .done:    return Color.green.opacity(0.15)
        case .active:  return Color.accentColor.opacity(0.15)
        case .waiting: return Color(nsColor: .quaternaryLabelColor).opacity(0.3)
        }
    }

    @ViewBuilder
    private func statusTag(_ status: StepStatus) -> some View {
        switch status {
        case .done:    Text("Done").font(.system(size: 11, weight: .medium)).foregroundColor(.green)
        case .active:  Text("Running…").font(.system(size: 11, weight: .medium)).foregroundColor(.accentColor)
        case .waiting: Text("Waiting").font(.system(size: 11, weight: .medium)).foregroundStyle(.tertiary)
        }
    }
}

// MARK: - ChannelPill

struct ChannelPill: View {
    let label: String
    let color: Color

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(Capsule())
        .overlay(Capsule().stroke(Color(nsColor: .separatorColor), lineWidth: 0.5))
    }
}
