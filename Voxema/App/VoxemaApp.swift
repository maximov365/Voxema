import SwiftUI
import Security
import Sparkle

@main
struct VoxemaApp: App {

    @StateObject private var appState = AppState.production()
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    // Sparkle requires proper code signing (Developer ID) to start its XPC service.
    // In debug/ad-hoc builds the updater is initialised but not started.
    private let updaterController = SPUStandardUpdaterController(
        startingUpdater: {
            #if DEBUG
            return false
            #else
            return true
            #endif
        }(),
        updaterDelegate: nil,
        userDriverDelegate: nil
    )

    init() {
        #if DEBUG
        // Skip onboarding in debug builds so the main UI is reached immediately.
        // Use Debug menu → Reset Onboarding (⇧⌘O) to test the flow manually.
        UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")

        // Delete stale encryption keychain items created by previous builds.
        // Without a stable Team ID, each rebuild has a different code signature.
        // macOS then prompts "allow this app to access com.voxema.app.encryption"
        // on every new build. Deleting at launch forces a fresh item to be created
        // silently. Safe in debug: no persistent encrypted data survives across builds.
        let staleQuery: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: "com.voxema.app.encryption",
        ]
        SecItemDelete(staleQuery as CFDictionary)
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
            CommandGroup(after: .appInfo) {
                CheckForUpdatesView(updater: updaterController.updater)
            }
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

                Button("Check Audio Permission") {
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

        Settings {
            SettingsView()
        }
    }
}
