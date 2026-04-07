import ServiceManagement
import XCTest
@testable import MyMac

final class LaunchAtLoginStatusMapperTests: XCTestCase {
    func testMapsServiceManagementStatuses() {
        XCTAssertEqual(LaunchAtLoginStatusMapper.map(.enabled), .enabled)
        XCTAssertEqual(LaunchAtLoginStatusMapper.map(.notRegistered), .disabled)
        XCTAssertEqual(LaunchAtLoginStatusMapper.map(.requiresApproval), .requiresApproval)
        XCTAssertEqual(LaunchAtLoginStatusMapper.map(.notFound), .unavailable)
    }
}

private struct MockPermissionSystemClient: PermissionSystemClient {
    var listenPreflight = false
    var listenRequested = false
    var postPreflight = false
    var postRequested = false
    var accessibilityTrusted = false
    var accessibilityPrompted = false

    func preflightListenEventAccess() -> Bool { listenPreflight }
    func requestListenEventAccess() -> Bool { listenRequested }
    func preflightPostEventAccess() -> Bool { postPreflight }
    func requestPostEventAccess() -> Bool { postRequested }
    func isAccessibilityTrusted() -> Bool { accessibilityTrusted }
    func requestAccessibilityPrompt() {}
}

final class PermissionServiceTests: XCTestCase {
    func testRefreshStatusSeparatesListenAndPostPermissions() async {
        let service = DefaultPermissionService(
            client: MockPermissionSystemClient(
                listenPreflight: true,
                listenRequested: true,
                postPreflight: false,
                postRequested: false,
                accessibilityTrusted: true,
                accessibilityPrompted: false
            )
        )

        let snapshot = await service.refreshStatus()

        XCTAssertEqual(snapshot.inputMonitoring, .granted)
        XCTAssertEqual(snapshot.accessibility, .requiresUserAction)
    }

    func testCanStartMappingRequiresBothPermissions() {
        let service = DefaultPermissionService(client: MockPermissionSystemClient())

        XCTAssertFalse(service.canStartMapping(.init(accessibility: .granted, inputMonitoring: .requiresUserAction)))
        XCTAssertFalse(service.canStartMapping(.init(accessibility: .requiresUserAction, inputMonitoring: .granted)))
        XCTAssertTrue(service.canStartMapping(.init(accessibility: .granted, inputMonitoring: .granted)))
    }

    func testRequestRequiredPermissionsReturnsUpdatedSnapshot() async {
        let service = DefaultPermissionService(
            client: MockPermissionSystemClient(
                listenPreflight: true,
                listenRequested: true,
                postPreflight: true,
                postRequested: true,
                accessibilityTrusted: true,
                accessibilityPrompted: true
            )
        )

        let snapshot = await service.requestRequiredPermissions()

        XCTAssertEqual(snapshot.inputMonitoring, .granted)
        XCTAssertEqual(snapshot.accessibility, .granted)
    }
}
