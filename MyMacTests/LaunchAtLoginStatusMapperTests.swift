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
    var accessibilityTrusted = false

    func isAccessibilityTrusted() -> Bool { accessibilityTrusted }
    func requestAccessibilityPrompt() {}
}

private final class SpyPermissionSystemClient: PermissionSystemClient, @unchecked Sendable {
    var accessibilityTrusted = false
    private(set) var requestAccessibilityPromptCallCount = 0

    func isAccessibilityTrusted() -> Bool { accessibilityTrusted }

    func requestAccessibilityPrompt() {
        requestAccessibilityPromptCallCount += 1
    }
}

final class PermissionServiceTests: XCTestCase {
    func testRefreshStatusRequiresAccessibilityTrust() async {
        let service = DefaultPermissionService(
            client: MockPermissionSystemClient(
                accessibilityTrusted: false
            )
        )

        let snapshot = await service.refreshStatus()

        XCTAssertEqual(snapshot.accessibility, .requiresUserAction)
    }

    func testRefreshStatusGrantsAccessWhenAccessibilityIsTrusted() async {
        let service = DefaultPermissionService(
            client: MockPermissionSystemClient(
                accessibilityTrusted: true
            )
        )

        let snapshot = await service.refreshStatus()

        XCTAssertEqual(snapshot.accessibility, .granted)
    }

    func testCanStartMappingRequiresAccessibilityOnly() {
        let service = DefaultPermissionService(client: MockPermissionSystemClient())

        XCTAssertFalse(service.canStartMapping(.init(accessibility: .requiresUserAction)))
        XCTAssertTrue(service.canStartMapping(.init(accessibility: .granted)))
    }

    func testRequestRequiredPermissionsPromptsAccessibilityWhenNeeded() async {
        let client = SpyPermissionSystemClient()
        let service = DefaultPermissionService(client: client)

        let snapshot = await service.requestRequiredPermissions()

        XCTAssertEqual(snapshot.accessibility, .requiresUserAction)
        XCTAssertEqual(client.requestAccessibilityPromptCallCount, 1)
    }

    func testRequestRequiredPermissionsSkipsPromptWhenAlreadyTrusted() async {
        let client = SpyPermissionSystemClient()
        client.accessibilityTrusted = true
        let service = DefaultPermissionService(client: client)

        let snapshot = await service.requestRequiredPermissions()

        XCTAssertEqual(snapshot.accessibility, .granted)
        XCTAssertEqual(client.requestAccessibilityPromptCallCount, 0)
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
        let permissionService = MockPermissionService(
            refreshResponses: [.init(accessibility: .granted)],
            requestedSnapshot: .init(accessibility: .granted)
        )
        let coordinator = AppCoordinator(
            appState: appState,
            settingsStore: SettingsStore(userDefaults: defaults),
            permissionService: permissionService,
            launchAtLoginService: MockLaunchAtLoginService(),
            keyboardMappingService: keyboardMappingService,
            diagnosticsService: MockDiagnosticsService()
        )

        await coordinator.handleAppLaunch()

        XCTAssertEqual(appState.runtimeStatus, .running)
        XCTAssertEqual(keyboardMappingService.startCallCount, 1)
        XCTAssertEqual(permissionService.requestCallCount, 0)
    }

    func testHandleAppLaunchStopsAtMissingPermissionsWithoutAccessibility() async {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        defaults.set(true, forKey: SettingsStore.Key.hasCompletedOnboarding)
        defaults.set(true, forKey: SettingsStore.Key.isKeyboardMappingEnabled)

        let appState = AppState(settingsStore: SettingsStore(userDefaults: defaults))
        let keyboardMappingService = MockKeyboardMappingService(status: .paused)
        let permissionService = MockPermissionService(
            refreshResponses: [.init(accessibility: .requiresUserAction)],
            requestedSnapshot: .init(accessibility: .requiresUserAction)
        )
        let coordinator = AppCoordinator(
            appState: appState,
            settingsStore: SettingsStore(userDefaults: defaults),
            permissionService: permissionService,
            launchAtLoginService: MockLaunchAtLoginService(),
            keyboardMappingService: keyboardMappingService,
            diagnosticsService: MockDiagnosticsService()
        )

        await coordinator.handleAppLaunch()

        XCTAssertEqual(appState.runtimeStatus, .missingPermissions)
        XCTAssertEqual(keyboardMappingService.startCallCount, 0)
        XCTAssertEqual(keyboardMappingService.stopCallCount, 1)
        XCTAssertEqual(permissionService.requestCallCount, 0)
    }

    func testRecheckPermissionsRestartsMappingAfterAccessibilityGranted() async {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        defaults.set(true, forKey: SettingsStore.Key.hasCompletedOnboarding)
        defaults.set(true, forKey: SettingsStore.Key.isKeyboardMappingEnabled)

        let appState = AppState(settingsStore: SettingsStore(userDefaults: defaults))
        let keyboardMappingService = MockKeyboardMappingService(status: .paused)
        let permissionService = MockPermissionService(
            refreshResponses: [
                .init(accessibility: .requiresUserAction),
                .init(accessibility: .granted)
            ],
            requestedSnapshot: .init(accessibility: .granted)
        )
        let coordinator = AppCoordinator(
            appState: appState,
            settingsStore: SettingsStore(userDefaults: defaults),
            permissionService: permissionService,
            launchAtLoginService: MockLaunchAtLoginService(),
            keyboardMappingService: keyboardMappingService,
            diagnosticsService: MockDiagnosticsService()
        )

        await coordinator.handleAppLaunch()
        await coordinator.recheckPermissions()

        XCTAssertEqual(appState.runtimeStatus, .running)
        XCTAssertEqual(keyboardMappingService.startCallCount, 1)
    }

    func testAppDidBecomeActiveRefreshesAndRestartsMappingAfterAccessibilityGranted() async {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        defaults.set(true, forKey: SettingsStore.Key.hasCompletedOnboarding)
        defaults.set(true, forKey: SettingsStore.Key.isKeyboardMappingEnabled)

        let appState = AppState(settingsStore: SettingsStore(userDefaults: defaults))
        let keyboardMappingService = MockKeyboardMappingService(status: .paused)
        let permissionService = MockPermissionService(
            refreshResponses: [
                .init(accessibility: .requiresUserAction),
                .init(accessibility: .granted)
            ],
            requestedSnapshot: .init(accessibility: .granted)
        )
        let coordinator = AppCoordinator(
            appState: appState,
            settingsStore: SettingsStore(userDefaults: defaults),
            permissionService: permissionService,
            launchAtLoginService: MockLaunchAtLoginService(),
            keyboardMappingService: keyboardMappingService,
            diagnosticsService: MockDiagnosticsService()
        )

        await coordinator.handleAppLaunch()
        await coordinator.handleAppDidBecomeActive()

        XCTAssertEqual(appState.runtimeStatus, .running)
        XCTAssertEqual(keyboardMappingService.startCallCount, 1)
    }

    func testHandleAppDidBecomeActiveDoesNotStartMappingWhenFeatureDisabled() async {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        defaults.set(true, forKey: SettingsStore.Key.hasCompletedOnboarding)
        defaults.set(false, forKey: SettingsStore.Key.isKeyboardMappingEnabled)

        let appState = AppState(settingsStore: SettingsStore(userDefaults: defaults))
        let keyboardMappingService = MockKeyboardMappingService(status: .paused)
        let permissionService = MockPermissionService(
            refreshResponses: [.init(accessibility: .granted)],
            requestedSnapshot: .init(accessibility: .granted)
        )
        let coordinator = AppCoordinator(
            appState: appState,
            settingsStore: SettingsStore(userDefaults: defaults),
            permissionService: permissionService,
            launchAtLoginService: MockLaunchAtLoginService(),
            keyboardMappingService: keyboardMappingService,
            diagnosticsService: MockDiagnosticsService()
        )

        await coordinator.handleAppDidBecomeActive()

        XCTAssertEqual(appState.runtimeStatus, .paused)
        XCTAssertEqual(keyboardMappingService.startCallCount, 0)
    }

    func testHandleAppLaunchPreservesFailureWhenAccessibilityGrantedButStartFails() async {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        defaults.set(true, forKey: SettingsStore.Key.hasCompletedOnboarding)
        defaults.set(true, forKey: SettingsStore.Key.isKeyboardMappingEnabled)

        let appState = AppState(settingsStore: SettingsStore(userDefaults: defaults))
        let keyboardMappingService = MockKeyboardMappingService(
            status: .paused,
            statusAfterStart: .failed("boom")
        )
        let coordinator = AppCoordinator(
            appState: appState,
            settingsStore: SettingsStore(userDefaults: defaults),
            permissionService: MockPermissionService(
                refreshResponses: [.init(accessibility: .granted)],
                requestedSnapshot: .init(accessibility: .granted)
            ),
            launchAtLoginService: MockLaunchAtLoginService(),
            keyboardMappingService: keyboardMappingService,
            diagnosticsService: MockDiagnosticsService()
        )

        await coordinator.handleAppLaunch()

        XCTAssertEqual(appState.runtimeStatus, .failed("boom"))
        XCTAssertEqual(keyboardMappingService.startCallCount, 1)
    }
}

private final class MockPermissionService: PermissionService, @unchecked Sendable {
    private let refreshResponses: [PermissionsSnapshot]
    let requestedSnapshot: PermissionsSnapshot
    private(set) var refreshCallCount = 0
    private(set) var requestCallCount = 0

    init(
        refreshResponses: [PermissionsSnapshot],
        requestedSnapshot: PermissionsSnapshot
    ) {
        self.refreshResponses = refreshResponses
        self.requestedSnapshot = requestedSnapshot
    }

    func refreshStatus() async -> PermissionsSnapshot {
        refreshCallCount += 1

        guard refreshResponses.last != nil else {
            return .unknown
        }

        let index = min(refreshCallCount - 1, refreshResponses.count - 1)
        return refreshResponses[index]
    }

    func requestRequiredPermissions() async -> PermissionsSnapshot {
        requestCallCount += 1
        return requestedSnapshot
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
    private let statusAfterStart: RuntimeStatus

    init(status: RuntimeStatus, statusAfterStart: RuntimeStatus = .running) {
        self.status = status
        self.statusAfterStart = statusAfterStart
    }

    func start() async {
        startCallCount += 1
        status = statusAfterStart
    }

    func stop() async {
        stopCallCount += 1
        status = .paused
    }

    func currentStatus() async -> RuntimeStatus {
        status
    }
}

private struct MockDiagnosticsService: DiagnosticsService {
    func log(_ message: String, category: DiagnosticsCategory) {}
    func error(_ message: String, category: DiagnosticsCategory) {}
}
