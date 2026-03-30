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
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
