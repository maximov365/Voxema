import SwiftUI

/// Sidebar view showing the meeting list with search.
struct LibrarySidebarView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(spacing: 0) {
            recordButton
            meetingList
        }
        .navigationTitle("Voxema")
        .searchable(text: $appState.searchQuery, placement: .sidebar, prompt: "Search meetings…")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button {
                    openSettings()
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 13))
                }
                .help("Settings")
                .keyboardShortcut(",", modifiers: .command)
            }
        }
    }

    // MARK: - Sections

    private var isRecordingActive: Bool {
        if case .recording = appState.pipelineState { return true }
        return false
    }

    private var recordButton: some View {
        Button {
            Task { await appState.startRecording() }
        } label: {
            HStack(spacing: 8) {
                BlinkingRecordDot(active: isRecordingActive)
                Text(recordButtonLabel)
                    .font(.system(size: 14, weight: .semibold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(recordButtonColor)
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 14)
        .disabled(isRecordButtonDisabled)
        .opacity(isRecordButtonDisabled && appState.pipelineState != .recording ? 0.45 : 1)
        .animation(.easeInOut(duration: 0.2), value: appState.pipelineState)
    }

    private var recordButtonLabel: String {
        switch appState.pipelineState {
        case .recording:  return String(localized: "Recording…")
        case .processing: return String(localized: "Processing…")
        default:          return String(localized: "New Recording")
        }
    }

    private var recordButtonColor: Color {
        if case .recording = appState.pipelineState { return Color.red.opacity(0.75) }
        return Color.red
    }

    private var isRecordButtonDisabled: Bool {
        switch appState.pipelineState {
        case .idle, .complete, .failed, .cancelled: return false
        default: return true
        }
    }

    @ViewBuilder
    private var meetingList: some View {
        let isProcessing = { if case .processing = appState.pipelineState { return true }; return false }()
        let doneMeetings = appState.meetings

        if !isProcessing && doneMeetings.isEmpty {
            Spacer()
            emptyState
            Spacer()
        } else {
            List(selection: $appState.selectedMeetingId) {
                if isProcessing {
                    Section("Now") {
                        processingRow
                    }
                }
                if !doneMeetings.isEmpty {
                    Section(isProcessing ? "Earlier" : "Meetings") {
                        ForEach(doneMeetings) { meeting in
                            MeetingRowView(meeting: meeting)
                                .tag(meeting.meetingId)
                        }
                    }
                }
            }
            .listStyle(.sidebar)
        }
    }

    private var processingRow: some View {
        HStack(spacing: 8) {
            ProgressView()
                .scaleEffect(0.7)
                .progressViewStyle(.circular)
            VStack(alignment: .leading, spacing: 2) {
                Text("Processing…")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                Text(durationText)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "mic")
                .font(.system(size: 28))
                .foregroundStyle(.quaternary)
            Text("No meetings yet")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
    }

    private var durationText: String {
        let total = Int(appState.recordingDuration)
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}

// MARK: - MeetingRowView

struct MeetingRowView: View {
    let meeting: Meeting

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(meeting.title)
                .font(.system(size: 14, weight: .medium))
                .lineLimit(1)
            HStack(spacing: 4) {
                Text(relativeDate)
                Text("·")
                Text(durationText)
            }
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 5)
    }

    private var relativeDate: String {
        if Calendar.current.isDateInToday(meeting.recordedAt) { return String(localized: "Today") }
        if Calendar.current.isDateInYesterday(meeting.recordedAt) { return String(localized: "Yesterday") }
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .none
        return df.string(from: meeting.recordedAt)
    }

    private var durationText: String {
        let m = Int(meeting.durationSeconds) / 60
        return m < 1 ? "< 1 min" : "\(m) min"
    }
}

// MARK: - BlinkingRecordDot

/// White circle that blinks (opacity 1.0 ↔ 0.25) while recording is active.
private struct BlinkingRecordDot: View {
    let active: Bool
    @State private var opacity: Double = 1.0

    var body: some View {
        Circle()
            .fill(Color.white)
            .frame(width: 8, height: 8)
            .opacity(opacity)
            .onAppear { if active { startBlink() } }
            .onChange(of: active) { isActive in
                if isActive { startBlink() } else { stopBlink() }
            }
    }

    private func startBlink() {
        withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) {
            opacity = 0.25
        }
    }

    private func stopBlink() {
        withAnimation(.easeOut(duration: 0.2)) {
            opacity = 1.0
        }
    }
}
