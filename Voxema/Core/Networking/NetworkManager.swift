import Foundation
import Network
import Combine

// MARK: - NetworkConnectionType

/// The interface type over which a network path is established.
public enum NetworkConnectionType: String, Equatable, Sendable {
    case wifi
    case wired
    case cellular
    case unknown
}

// MARK: - NetworkStatus

/// A snapshot of current network reachability.
public struct NetworkStatus: Equatable, Sendable {

    public let isConnected: Bool
    public let connectionType: NetworkConnectionType

    /// Sentinel value representing no confirmed connectivity.
    /// `NetworkManager` starts in this state (offline-first).
    public static let disconnected = NetworkStatus(isConnected: false, connectionType: .unknown)

    /// Derives status from a live `NWPath`. Internal — only `NetworkManager` constructs
    /// status from real paths.
    init(_ path: NWPath) {
        isConnected = path.status == .satisfied
        if path.usesInterfaceType(.wifi) {
            connectionType = .wifi
        } else if path.usesInterfaceType(.wiredEthernet) {
            connectionType = .wired
        } else if path.usesInterfaceType(.cellular) {
            connectionType = .cellular
        } else {
            connectionType = .unknown
        }
    }

    /// Memberwise initialiser for testing and manual construction.
    public init(isConnected: Bool, connectionType: NetworkConnectionType) {
        self.isConnected = isConnected
        self.connectionType = connectionType
    }
}

// MARK: - NetworkManager

/// Monitors network path reachability using `NWPathMonitor`.
///
/// ## Offline-first contract
/// `status` begins as `.disconnected`. Consumers must never assume connectivity
/// until `status.isConnected` is `true`. This prevents spurious cloud requests
/// at launch before the first path update is delivered.
///
/// ## Lifetime
/// `shared` is designed for app-lifetime monitoring. Call `startMonitoring()` once
/// from the app entry point (e.g. `AppDelegate.applicationDidFinishLaunching`).
///
/// ## Thread safety
/// All public properties and methods are `@MainActor`-isolated.
/// `NWPathMonitor` callbacks are received on a private utility queue and
/// bridged back to the main actor via `Task`.
@MainActor
public final class NetworkManager: ObservableObject {

    /// App-wide shared instance. Monitoring must be started explicitly.
    public static let shared = NetworkManager()

    /// Current network status. Starts `.disconnected` (offline-first).
    @Published public private(set) var status: NetworkStatus = .disconnected

    /// `true` when the network path is satisfied.
    public var isConnected: Bool { status.isConnected }

    private let monitor: NWPathMonitor
    private let monitorQueue = DispatchQueue(
        label: "com.voxema.app.networkmonitor",
        qos: .utility
    )
    private var monitoring = false

    public init() {
        monitor = NWPathMonitor()
    }

    deinit {
        monitor.cancel()
    }

    /// Begins monitoring network path changes.
    ///
    /// Idempotent — subsequent calls before `stopMonitoring()` are silent no-ops.
    /// `NWPathMonitor` delivers its initial path state shortly after `start(queue:)`.
    public func startMonitoring() {
        guard !monitoring else { return }
        monitoring = true
        monitor.pathUpdateHandler = { [weak self] path in
            let newStatus = NetworkStatus(path)
            Task { @MainActor [weak self] in
                self?.status = newStatus
            }
        }
        monitor.start(queue: monitorQueue)
    }

    /// Cancels monitoring and resets `status` to `.disconnected`.
    ///
    /// After calling this method, the `NetworkManager` instance must be discarded —
    /// `NWPathMonitor.cancel()` is irreversible and the monitor cannot be restarted.
    public func stopMonitoring() {
        guard monitoring else { return }
        monitoring = false
        monitor.cancel()
        status = .disconnected
    }
}
