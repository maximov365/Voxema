import SwiftUI
import Combine
import Sparkle

/// Observable wrapper that exposes the Sparkle updater's `canCheckForUpdates`
/// state to SwiftUI's command system.
final class UpdaterViewModel: ObservableObject {
    @Published var canCheckForUpdates = false

    init(updater: SPUUpdater) {
        updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
    }
}

/// SwiftUI view used inside `CommandGroup(after: .appInfo)` to add
/// a standard "Check for Updates…" menu item backed by Sparkle.
struct CheckForUpdatesView: View {
    @StateObject private var viewModel: UpdaterViewModel
    private let updater: SPUUpdater

    init(updater: SPUUpdater) {
        self.updater = updater
        _viewModel = StateObject(wrappedValue: UpdaterViewModel(updater: updater))
    }

    var body: some View {
        Button(String(localized: "Check for Updates…")) {
            updater.checkForUpdates()
        }
        .disabled(!viewModel.canCheckForUpdates)
    }
}
