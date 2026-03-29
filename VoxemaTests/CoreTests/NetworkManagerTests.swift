import XCTest
import Combine
@testable import Voxema

@MainActor
final class NetworkManagerTests: XCTestCase {

    // MARK: - NetworkConnectionType

    func testConnectionTypeRawValues() {
        XCTAssertEqual(NetworkConnectionType.wifi.rawValue,     "wifi")
        XCTAssertEqual(NetworkConnectionType.wired.rawValue,    "wired")
        XCTAssertEqual(NetworkConnectionType.cellular.rawValue, "cellular")
        XCTAssertEqual(NetworkConnectionType.unknown.rawValue,  "unknown")
    }

    func testConnectionTypeEquality() {
        XCTAssertEqual(NetworkConnectionType.wifi, NetworkConnectionType.wifi)
        XCTAssertNotEqual(NetworkConnectionType.wifi, NetworkConnectionType.wired)
    }

    // MARK: - NetworkStatus

    func testDisconnectedFactory() {
        let s = NetworkStatus.disconnected
        XCTAssertFalse(s.isConnected)
        XCTAssertEqual(s.connectionType, .unknown)
    }

    func testMemberwiseInit() {
        let s = NetworkStatus(isConnected: true, connectionType: .wifi)
        XCTAssertTrue(s.isConnected)
        XCTAssertEqual(s.connectionType, .wifi)
    }

    func testStatusEquality() {
        let a = NetworkStatus(isConnected: true,  connectionType: .wifi)
        let b = NetworkStatus(isConnected: true,  connectionType: .wifi)
        let c = NetworkStatus(isConnected: false, connectionType: .wifi)
        let d = NetworkStatus(isConnected: true,  connectionType: .wired)
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
        XCTAssertNotEqual(a, d)
    }

    func testAllConnectionTypesRepresented() {
        let types: [NetworkConnectionType] = [.wifi, .wired, .cellular, .unknown]
        // Verify all 4 cases produce distinct statuses
        let statuses = types.map { NetworkStatus(isConnected: true, connectionType: $0) }
        let unique = Set(statuses.map { $0.connectionType.rawValue })
        XCTAssertEqual(unique.count, 4)
    }

    // MARK: - NetworkManager — initial state

    func testInitialStatusIsDisconnected() {
        let manager = NetworkManager()
        XCTAssertEqual(manager.status, .disconnected)
    }

    func testIsConnectedMirrorsStatus() {
        let manager = NetworkManager()
        XCTAssertEqual(manager.isConnected, manager.status.isConnected)
    }

    func testSharedInstanceExists() {
        // Verify shared is accessible and starts disconnected
        // (do not start monitoring to avoid side-effects on shared state)
        XCTAssertFalse(NetworkManager.shared.isConnected)
    }

    // MARK: - NetworkManager — monitoring lifecycle

    func testStartMonitoringIsIdempotent() {
        let manager = NetworkManager()
        manager.startMonitoring()
        manager.startMonitoring() // second call must not crash
        manager.stopMonitoring()
    }

    func testStopMonitoringResetsStatusToDisconnected() {
        let manager = NetworkManager()
        manager.startMonitoring()
        manager.stopMonitoring()
        XCTAssertEqual(manager.status, .disconnected)
    }

    func testStopMonitoringBeforeStartIsNoOp() {
        let manager = NetworkManager()
        manager.stopMonitoring() // Must not crash when monitor was never started
    }

    // MARK: - NetworkManager — integration (requires network)

    func testMonitorDetectsConnectivityAfterStart() async throws {
        let manager = NetworkManager()
        manager.startMonitoring()

        // NWPathMonitor fires its initial update shortly after start.
        // Wait up to 2 seconds for the path callback to arrive.
        let deadline = Date().addingTimeInterval(2)
        while !manager.isConnected && Date() < deadline {
            try await Task.sleep(nanoseconds: 100_000_000) // 100 ms polling
        }

        XCTAssertTrue(
            manager.isConnected,
            "NetworkManager should report connected on a networked Mac after startMonitoring()"
        )
        manager.stopMonitoring()
    }

    func testStatusPublisherEmitsUpdates() async throws {
        let manager = NetworkManager()
        var received: [NetworkStatus] = []
        var cancellable: AnyCancellable?

        cancellable = manager.$status.sink { received.append($0) }
        manager.startMonitoring()

        // Wait for at least one update beyond the initial .disconnected emission
        let deadline = Date().addingTimeInterval(2)
        while received.count < 2 && Date() < deadline {
            try await Task.sleep(nanoseconds: 100_000_000)
        }

        cancellable?.cancel()
        manager.stopMonitoring()

        // Publisher emits current value on subscription (.disconnected),
        // then at least one path update
        XCTAssertGreaterThanOrEqual(received.count, 2, "Expected initial + at least one path update")
        XCTAssertEqual(received.first, .disconnected, "First emission must be the offline-first initial state")
    }
}
