import SwiftUI

/// Sidebar view showing the meeting list with search.
struct LibrarySidebarView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            recordButton
            searchBar
            meetingList
        }
    }

    // MARK: - Sections

    private var recordButton: some View {
        Button {
            Task { await appState.startRecording() }
        } label: {
            HStack(spacing: 6) {
                Circle()
                    .fill(Color.white)
                    .frame(width: 8, height: 8)
                Text(recordButtonLabel)
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(recordButtonColor)
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 10)
        .padding(.top, 10)
        .padding(.bottom, 6)
        .disabled(isRecordButtonDisabled)
        .opacity(isRecordButtonDisabled && appState.pipelineState != .recording ? 0.45 : 1)
        .animation(.easeInOut(duration: 0.2), value: appState.pipelineState)
    }

    private var recordButtonLabel: String {
        switch appState.pipelineState {
        case .recording: return "Recording…"
        case .processing: return "Processing…"
        default: return "New Recording"
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
    private var searchBar: some View {
        if !appState.meetings.isEmpty || !appState.searchQuery.isEmpty {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                TextField("Search meetings…", text: $appState.searchQuery)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                if !appState.searchQuery.isEmpty {
                    Button { appState.searchQuery = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .padding(.horizontal, 10)
            .padding(.bottom, 6)
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
        VStack(alignment: .leading, spacing: 3) {
            Text(meeting.title)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)
            HStack(spacing: 4) {
                Text(relativeDate)
                Text("·")
                Text(durationText)
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 1)
    }

    private var relativeDate: String {
        let df = RelativeDateTimeFormatter()
        df.dateTimeStyle = .named
        df.unitsStyle = .abbreviated
        if Calendar.current.isDateInToday(meeting.recordedAt) { return "Today" }
        if Calendar.current.isDateInYesterday(meeting.recordedAt) { return "Yesterday" }
        let df2 = DateFormatter()
        df2.dateStyle = .medium
        df2.timeStyle = .none
        return df2.string(from: meeting.recordedAt)
    }

    private var durationText: String {
        let m = Int(meeting.durationSeconds) / 60
        return m < 1 ? "< 1 min" : "\(m) min"
    }
}
