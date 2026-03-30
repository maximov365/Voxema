import SwiftUI

/// Content for the Menu Bar Extra popover.
struct MenuBarView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            recordButton
            Divider()
            recentMeetings
            Divider()
            footer
        }
        .frame(width: 260)
    }

    // MARK: - Sections

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Voxema")
                    .font(.system(size: 13, weight: .bold))
                Text(headerSubtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var headerSubtitle: String {
        switch appState.pipelineState {
        case .recording:              return "● Recording — \(formattedDuration)"
        case .processing:             return "Processing…"
        case .complete:               return "Ready"
        case .failed:                 return "Error — tap to view"
        default:                      return "Ready to record"
        }
    }

    private var recordButton: some View {
        Group {
            if case .recording = appState.pipelineState {
                Button {
                    Task { await appState.stopRecording() }
                } label: {
                    Label("Stop Recording — \(formattedDuration)", systemImage: "stop.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(MenuBarActionButtonStyle(tint: .secondary))
            } else {
                Button {
                    Task { await appState.startRecording() }
                } label: {
                    Label("Start Recording", systemImage: "mic.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(MenuBarActionButtonStyle(tint: .red))
                .disabled(appState.pipelineState != .idle)
            }
        }
        .padding(10)
    }

    @ViewBuilder
    private var recentMeetings: some View {
        let recent = Array(appState.meetings.prefix(2))
        if recent.isEmpty {
            Text("No meetings yet")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .padding(12)
        } else {
            VStack(spacing: 0) {
                ForEach(recent) { meeting in
                    Button {
                        appState.selectedMeetingId = meeting.meetingId
                        NSApp.activate(ignoringOtherApps: true)
                        NSApp.windows.first?.makeKeyAndOrderFront(nil)
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "doc.text")
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                                .frame(width: 20)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(meeting.title)
                                    .font(.system(size: 13, weight: .medium))
                                    .lineLimit(1)
                                Text(meetingMeta(meeting))
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if meeting.meetingId != recent.last?.meetingId {
                        Divider().padding(.leading, 44)
                    }
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            Button("Open Library") {
                NSApp.activate(ignoringOtherApps: true)
                NSApp.windows.first?.makeKeyAndOrderFront(nil)
            }
            .buttonStyle(.plain)
            .font(.system(size: 12))
            .foregroundStyle(.secondary)

            Spacer()

            Button("Quit") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }

    // MARK: - Helpers

    private var formattedDuration: String {
        let total = Int(appState.recordingDuration)
        let m = total / 60; let s = total % 60
        return String(format: "%02d:%02d", m, s)
    }

    private func meetingMeta(_ meeting: Meeting) -> String {
        let df = DateFormatter()
        df.doesRelativeDateFormatting = true
        df.dateStyle = .short
        df.timeStyle = .none
        let dur = Int(meeting.durationSeconds) / 60
        return "\(df.string(from: meeting.recordedAt)) · \(dur) min"
    }
}

// MARK: - Button Style

private struct MenuBarActionButtonStyle: ButtonStyle {
    let tint: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(tint == .red ? Color.white : Color.primary)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(tint == .red ? Color.red : Color(nsColor: .controlBackgroundColor))
            )
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}
