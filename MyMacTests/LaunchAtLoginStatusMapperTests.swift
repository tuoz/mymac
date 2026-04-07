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
    var postPreflight = false
    var postRequested = false
    var accessibilityTrusted = false
    var accessibilityPrompted = false

    func preflightPostEventAccess() -> Bool { postPreflight }
    func requestPostEventAccess() -> Bool { postRequested }
    func isAccessibilityTrusted() -> Bool { accessibilityTrusted }
    func requestAccessibilityPrompt() {}
}

final class PermissionServiceTests: XCTestCase {
    func testRefreshStatusRequiresPostEventAndAccessibilityTrust() async {
        let service = DefaultPermissionService(
            client: MockPermissionSystemClient(
                postPreflight: false,
                postRequested: false,
                accessibilityTrusted: true,
                accessibilityPrompted: false
            )
        )

        let snapshot = await service.refreshStatus()

        XCTAssertEqual(snapshot.accessibility, .requiresUserAction)
    }

    func testCanStartMappingRequiresAccessibilityOnly() {
        let service = DefaultPermissionService(client: MockPermissionSystemClient())

        XCTAssertFalse(service.canStartMapping(.init(accessibility: .requiresUserAction)))
        XCTAssertTrue(service.canStartMapping(.init(accessibility: .granted)))
    }

    func testRequestRequiredPermissionsReturnsUpdatedSnapshot() async {
        let service = DefaultPermissionService(
            client: MockPermissionSystemClient(
                postPreflight: true,
                postRequested: true,
                accessibilityTrusted: true,
                accessibilityPrompted: true
            )
        )

        let snapshot = await service.requestRequiredPermissions()

        XCTAssertEqual(snapshot.accessibility, .granted)
    }
}

@MainActor
final class AppStateTests: XCTestCase {
    func testPermissionSummaryReflectsAccessibilityOnly() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        let appState = AppState(settingsStore: SettingsStore(userDefaults: defaults))

        appState.permissions = .init(accessibility: .requiresUserAction)
        XCTAssertEqual(appState.permissionSummary, "需要处理")

        appState.permissions = .init(accessibility: .granted)
        XCTAssertEqual(appState.permissionSummary, "已授权")
    }
}

@MainActor
final class AppCoordinatorPermissionFlowTests: XCTestCase {
    func testHandleAppLaunchStartsMappingWhenAccessibilityIsGranted() async {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        defaults.set(true, forKey: SettingsStore.Key.hasCompletedOnboarding)
        defaults.set(true, forKey: SettingsStore.Key.isKeyboardMappingEnabled)

        let appState = AppState(settingsStore: SettingsStore(userDefaults: defaults))
        let keyboardMappingService = MockKeyboardMappingService(status: .paused)
        let coordinator = AppCoordinator(
            appState: appState,
            settingsStore: SettingsStore(userDefaults: defaults),
            permissionService: MockPermissionService(
                refreshedSnapshot: .init(accessibility: .granted),
                requestedSnapshot: .init(accessibility: .granted)
            ),
            launchAtLoginService: MockLaunchAtLoginService(),
            keyboardMappingService: keyboardMappingService,
            diagnosticsService: MockDiagnosticsService()
        )

        await coordinator.handleAppLaunch()

        XCTAssertEqual(appState.runtimeStatus, .running)
        XCTAssertEqual(keyboardMappingService.startCallCount, 1)
    }

    func testHandleAppLaunchStopsAtMissingPermissionsWithoutAccessibility() async {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        defaults.set(true, forKey: SettingsStore.Key.hasCompletedOnboarding)
        defaults.set(true, forKey: SettingsStore.Key.isKeyboardMappingEnabled)

        let appState = AppState(settingsStore: SettingsStore(userDefaults: defaults))
        let keyboardMappingService = MockKeyboardMappingService(status: .paused)
        let coordinator = AppCoordinator(
            appState: appState,
            settingsStore: SettingsStore(userDefaults: defaults),
            permissionService: MockPermissionService(
                refreshedSnapshot: .init(accessibility: .requiresUserAction),
                requestedSnapshot: .init(accessibility: .requiresUserAction)
            ),
            launchAtLoginService: MockLaunchAtLoginService(),
            keyboardMappingService: keyboardMappingService,
            diagnosticsService: MockDiagnosticsService()
        )

        await coordinator.handleAppLaunch()

        XCTAssertEqual(appState.runtimeStatus, .missingPermissions)
        XCTAssertEqual(keyboardMappingService.startCallCount, 0)
        XCTAssertEqual(keyboardMappingService.stopCallCount, 1)
    }
}

private struct MockPermissionService: PermissionService {
    let refreshedSnapshot: PermissionsSnapshot
    let requestedSnapshot: PermissionsSnapshot

    func refreshStatus() async -> PermissionsSnapshot {
        refreshedSnapshot
    }

    func requestRequiredPermissions() async -> PermissionsSnapshot {
        requestedSnapshot
    }

    func openSystemSettings() {}

    func canStartMapping(_ permissions: PermissionsSnapshot) -> Bool {
        permissions.accessibility == .granted
    }
}

private struct MockLaunchAtLoginService: LaunchAtLoginService {
    func currentStatus() -> LaunchAtLoginStatus {
        .disabled
    }

    func setEnabled(_ enabled: Bool) throws {}
}

private final class MockKeyboardMappingService: KeyboardMappingService, @unchecked Sendable {
    private(set) var status: RuntimeStatus
    private(set) var startCallCount = 0
    private(set) var stopCallCount = 0

    init(status: RuntimeStatus) {
        self.status = status
    }

    func start(with snapshot: RuleSnapshot) async {
        startCallCount += 1
        status = .running
    }

    func stop() async {
        stopCallCount += 1
        status = .paused
    }

    func reloadRules(_ snapshot: RuleSnapshot) async {
        status = .running
    }

    func currentStatus() async -> RuntimeStatus {
        status
    }
}

private struct MockDiagnosticsService: DiagnosticsService {
    func log(_ message: String, category: DiagnosticsCategory) {}
    func error(_ message: String, category: DiagnosticsCategory) {}
}
