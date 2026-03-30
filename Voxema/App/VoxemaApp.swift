import SwiftUI

@main
struct VoxemaApp: App {

    @StateObject private var appState = AppState.production()
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    init() {
        #if DEBUG
        // Always show onboarding in debug builds so the flow can be tested on each run.
        // Remove this block before shipping to production.
        UserDefaults.standard.removeObject(forKey: "hasCompletedOnboarding")
        #endif
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .frame(minWidth: 720, minHeight: 480)
                .sheet(isPresented: .constant(!hasCompletedOnboarding)) {
                    OnboardingView {
                        hasCompletedOnboarding = true
                    }
                    .frame(width: 480, height: 560)
                    .interactiveDismissDisabled()
                }
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button(String(localized: "New Recording")) {
                    Task { await appState.startRecording() }
                }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(appState.pipelineState != .idle)
            }
        }

        MenuBarExtra(String(localized: "Voxema"), systemImage: "waveform") {
            MenuBarView()
                .environmentObject(appState)
        }
        .menuBarExtraStyle(.window)
    }
}
