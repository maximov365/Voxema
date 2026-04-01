import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        NavigationSplitView(columnVisibility: .constant(.all)) {
            LibrarySidebarView()
                .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 280)
        } detail: {
            detailContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationSplitViewStyle(.balanced)
        .alert(
            "Recording Error",
            isPresented: Binding(
                get: { appState.pipelineError != nil },
                set: { if !$0 { appState.pipelineError = nil } }
            )
        ) {
            Button("OK") { appState.pipelineError = nil }
        } message: {
            Text(appState.pipelineError?.errorDescription ?? "An unknown error occurred.")
        }
        // Alert: permission missing — send user to Settings.
        .alert(
            appState.permissionRequired == .systemAudioRecording
                ? String(localized: "System Audio Recording Required")
                : String(localized: "Microphone Access Required"),
            isPresented: Binding(
                get: { appState.permissionRequired != nil },
                set: { if !$0 { appState.permissionRequired = nil } }
            ),
            presenting: appState.permissionRequired
        ) { kind in
            Button(String(localized: "Open System Settings")) {
                appState.openPermissionSettings(for: kind)
                appState.permissionRequired = nil
            }
            Button(String(localized: "Cancel"), role: .cancel) {
                appState.permissionRequired = nil
            }
        } message: { kind in
            switch kind {
            case .systemAudioRecording:
                Text(String(localized: "System Audio Recording access is required to capture audio from remote meeting participants.\n\nEnable it in System Settings → Privacy & Security, then return to Voxema and try again."))
            case .microphone:
                Text(String(localized: "Microphone access is required to record your side of the conversation.\n\nEnable it in System Settings, then return to Voxema."))
            }
        }
    }

    @ViewBuilder
    private var detailContent: some View {
        switch appState.pipelineState {
        case .recording, .stopping:
            RecordingView()
        case .processing:
            ProcessingView()
        default:
            if let meeting = appState.selectedMeeting {
                MeetingDetailView(meeting: meeting)
            } else {
                emptyDetail
            }
        }
    }

    private var emptyDetail: some View {
        VStack(spacing: 12) {
            if appState.meetings.isEmpty {
                Image(systemName: "mic")
                    .font(.system(size: 44))
                    .foregroundStyle(.quaternary)
                Text("No meetings yet")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .opacity(0.7)
                Text("Start a recording to capture and transcribe your next meeting.")
                    .font(.system(size: 13))
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 240)
                Button {
                    Task { await appState.startRecording() }
                } label: {
                    Label("Start Recording", systemImage: "mic.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 8)
                        .background(Color.red)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
                .disabled(appState.pipelineState != .idle)

                #if DEBUG
                SCKDiagnosticsView()
                #endif
            } else {
                Image(systemName: "doc.on.clipboard")
                    .font(.system(size: 44))
                    .foregroundStyle(.quaternary)
                Text("Select a meeting")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .opacity(0.7)
                Text("Choose from the list to view transcript and summary.")
                    .font(.system(size: 13))
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 260)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    #if DEBUG
    private func SCKDiagnosticsView() -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Audio Permission Diagnostics")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Check ⇧⌘K") {
                    Task { await appState.refreshSCKDiagnostics() }
                }
                .font(.system(size: 10))
                .buttonStyle(.borderless)
                .foregroundStyle(Color.accentColor)
            }
            Text(appState.sckDiagnostics)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.primary)
                .textSelection(.enabled)
                .lineLimit(4)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(10)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
        .frame(maxWidth: 480)
        .padding(.top, 16)
    }
    #endif
}
