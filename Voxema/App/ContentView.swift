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
        .alert(
            appState.permissionRequired == .screenRecording
                ? String(localized: "Screen Recording Required")
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
            if kind == .screenRecording {
                Button(String(localized: "Restart Voxema")) {
                    appState.restartApp()
                }
            }
            Button(String(localized: "Cancel"), role: .cancel) {
                appState.permissionRequired = nil
            }
        } message: { kind in
            switch kind {
            case .screenRecording:
                Text(String(localized: "Screen Recording is required to capture meeting audio from remote participants.\n\nIf you already enabled it in System Settings, tap Restart Voxema — macOS requires a relaunch for this permission to take effect."))
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
            Image(systemName: "mic.circle")
                .font(.system(size: 52))
                .foregroundStyle(.quaternary)
            Text("No meeting selected")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.secondary)
            Text("Start a new recording or select a meeting from the list.")
                .font(.system(size: 13))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 260)
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
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    #if DEBUG
    private func SCKDiagnosticsView() -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("SCK Diagnostics")
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
