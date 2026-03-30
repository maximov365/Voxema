import SwiftUI
import ScreenCaptureKit

@main
struct VoxemaApp: App {

    @StateObject private var appState = AppState.production()
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    init() {
        #if DEBUG
        // Skip onboarding in debug builds so the main UI is reached immediately.
        // Use Debug menu → Reset Onboarding (⇧⌘O) to test the flow manually.
        UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
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
                .task {
                    // Register with TCC so the app appears in System Settings →
                    // Screen & System Audio Recording before the first recording attempt.
                    // On macOS 15 CGPreflightScreenCaptureAccess() checks the old TCC key
                    // and is unreliable, so we always call SCK here; if already granted it
                    // returns silently, otherwise macOS shows the one-time permission prompt.
                    _ = try? await SCShareableContent.excludingDesktopWindows(
                        false, onScreenWindowsOnly: false
                    )
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
            #if DEBUG
            CommandMenu("Debug") {
                Button("Reset Onboarding") {
                    UserDefaults.standard.removeObject(forKey: "hasCompletedOnboarding")
                }
                .keyboardShortcut("o", modifiers: [.command, .shift])

                Button("Check SCK Permission") {
                    Task { await appState.refreshSCKDiagnostics() }
                }
                .keyboardShortcut("k", modifiers: [.command, .shift])
            }
            #endif
        }

        MenuBarExtra(String(localized: "Voxema"), systemImage: "waveform") {
            MenuBarView()
                .environmentObject(appState)
        }
        .menuBarExtraStyle(.window)
    }
}
