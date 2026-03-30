import SwiftUI

@main
struct VoxemaApp: App {

    @StateObject private var appState = AppState.production()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .frame(minWidth: 720, minHeight: 480)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Recording") {
                    Task { await appState.startRecording() }
                }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(appState.pipelineState != .idle)
            }
        }

        MenuBarExtra("Voxema", systemImage: isRecording ? "mic.fill" : "mic") {
            MenuBarView()
                .environmentObject(appState)
        }
        .menuBarExtraStyle(.window)
    }

    private var isRecording: Bool {
        if case .recording = appState.pipelineState { return true }
        return false
    }
}
