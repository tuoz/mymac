import AppKit
import SwiftUI

@MainActor
final class AppCoordinator {
    private let appState: AppState
    private let settingsStore: SettingsStore
    private let permissionService: PermissionService
    private let launchAtLoginService: LaunchAtLoginService
    private let keyboardMappingService: KeyboardMappingService
    private let diagnosticsService: DiagnosticsService
    private let ruleSnapshotFactory: DefaultRuleSnapshotFactory

    private var settingsWindowController: NSWindowController?
    private var onboardingWindowController: NSWindowController?
    private var settingsWindowDelegate: WindowCloseObserver?
    private var onboardingWindowDelegate: WindowCloseObserver?

    init(
        appState: AppState,
        settingsStore: SettingsStore,
        permissionService: PermissionService,
        launchAtLoginService: LaunchAtLoginService,
        keyboardMappingService: KeyboardMappingService,
        diagnosticsService: DiagnosticsService,
        ruleSnapshotFactory: DefaultRuleSnapshotFactory = .init()
    ) {
        self.appState = appState
        self.settingsStore = settingsStore
        self.permissionService = permissionService
        self.launchAtLoginService = launchAtLoginService
        self.keyboardMappingService = keyboardMappingService
        self.diagnosticsService = diagnosticsService
        self.ruleSnapshotFactory = ruleSnapshotFactory
    }

    var isLaunchAtLoginToggleOn: Bool {
        appState.launchAtLoginStatus.isToggleOn
    }

    func handleAppLaunch() async {
        diagnosticsService.log("Application launched", category: .app)
        syncStateFromStore()
        syncLaunchAtLoginStatus()
        await refreshPermissions()

        if !appState.hasCompletedOnboarding {
            showOnboarding()
        }

        await reconcileKeyboardMappingState()
    }

    func showSettings() {
        if let controller = settingsWindowController {
            bringToFront(controller)
            return
        }

        let rootView = SettingsView(coordinator: self)
            .environment(appState)
        let controller = makeWindowController(
            title: "MyMac Settings",
            size: NSSize(width: 520, height: 420),
            rootView: rootView
        )

        settingsWindowDelegate = WindowCloseObserver { [weak self] in
            self?.settingsWindowController = nil
            self?.settingsWindowDelegate = nil
        }
        controller.window?.delegate = settingsWindowDelegate
        settingsWindowController = controller
        bringToFront(controller)
    }

    func showOnboarding() {
        if let controller = onboardingWindowController {
            bringToFront(controller)
            return
        }

        let rootView = OnboardingView(
            coordinator: self,
            initialLaunchAtLoginEnabled: isLaunchAtLoginToggleOn
        )
        .environment(appState)

        let controller = makeWindowController(
            title: "Welcome to MyMac",
            size: NSSize(width: 540, height: 380),
            rootView: rootView
        )

        onboardingWindowDelegate = WindowCloseObserver { [weak self] in
            self?.onboardingWindowController = nil
            self?.onboardingWindowDelegate = nil
        }
        controller.window?.delegate = onboardingWindowDelegate
        onboardingWindowController = controller
        bringToFront(controller)
    }

    func closeOnboarding() {
        onboardingWindowController?.close()
        onboardingWindowController = nil
        onboardingWindowDelegate = nil
    }

    func quit() {
        NSApp.terminate(nil)
    }

    func refreshPermissions() async {
        appState.permissions = await permissionService.refreshStatus()
        diagnosticsService.log(
            "Permissions refreshed: accessibility=\(appState.permissions.accessibility.displayName)",
            category: .permissions
        )
    }

    func requestPermissions() async {
        appState.permissions = await permissionService.requestRequiredPermissions()
        diagnosticsService.log(
            "Requested permissions: accessibility=\(appState.permissions.accessibility.displayName)",
            category: .permissions
        )
        await reconcileKeyboardMappingState(requestPermissionsIfNeeded: false)
    }

    func openSystemSettings() {
        permissionService.openSystemSettings()
    }

    func setKeyboardMappingEnabled(_ enabled: Bool) async {
        settingsStore.isKeyboardMappingEnabled = enabled
        appState.isKeyboardMappingEnabled = enabled
        await reconcileKeyboardMappingState()
    }

    func setLaunchAtLoginEnabled(_ enabled: Bool) {
        do {
            try launchAtLoginService.setEnabled(enabled)
            settingsStore.launchAtLoginDesired = enabled
            syncLaunchAtLoginStatus()
        } catch {
            appState.runtimeStatus = .failed("无法更新开机启动")
            diagnosticsService.error(
                "Failed to update launch at login: \(error.localizedDescription)",
                category: .launchAtLogin
            )
        }
    }

    func completeOnboarding(enableLaunchAtLogin: Bool) async {
        if enableLaunchAtLogin != isLaunchAtLoginToggleOn {
            setLaunchAtLoginEnabled(enableLaunchAtLogin)
        }

        settingsStore.hasCompletedOnboarding = true
        appState.hasCompletedOnboarding = true
        closeOnboarding()
        await refreshPermissions()
        await reconcileKeyboardMappingState()
    }

    private func syncStateFromStore() {
        appState.isKeyboardMappingEnabled = settingsStore.isKeyboardMappingEnabled
        appState.hasCompletedOnboarding = settingsStore.hasCompletedOnboarding
    }

    private func syncLaunchAtLoginStatus() {
        appState.launchAtLoginStatus = launchAtLoginService.currentStatus()
    }

    private func makeCurrentRuleSnapshot() -> RuleSnapshot {
        ruleSnapshotFactory.makeSnapshot(isEnabled: appState.isKeyboardMappingEnabled)
    }

    private func reconcileKeyboardMappingState(requestPermissionsIfNeeded: Bool = true) async {
        if !appState.isKeyboardMappingEnabled {
            await keyboardMappingService.stop()
            appState.runtimeStatus = .paused
            return
        }

        if !permissionService.canStartMapping(appState.permissions) {
            if requestPermissionsIfNeeded {
                appState.permissions = await permissionService.requestRequiredPermissions()
                diagnosticsService.log(
                    "Auto-requested permissions during reconciliation: accessibility=\(appState.permissions.accessibility.displayName)",
                    category: .permissions
                )
            }

            if !permissionService.canStartMapping(appState.permissions) {
                await keyboardMappingService.stop()
                appState.runtimeStatus = .missingPermissions
                return
            }
        }

        let snapshot = makeCurrentRuleSnapshot()
        let currentStatus = await keyboardMappingService.currentStatus()

        switch currentStatus {
        case .running:
            await keyboardMappingService.reloadRules(snapshot)
        case .tapDisabled, .failed:
            await keyboardMappingService.stop()
            await keyboardMappingService.start(with: snapshot)
        default:
            await keyboardMappingService.start(with: snapshot)
        }

        appState.runtimeStatus = await keyboardMappingService.currentStatus()
    }

    private func makeWindowController<Content: View>(
        title: String,
        size: NSSize,
        rootView: Content
    ) -> NSWindowController {
        let hostingController = NSHostingController(rootView: rootView)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = title
        window.center()
        window.contentViewController = hostingController
        window.isReleasedWhenClosed = false
        return NSWindowController(window: window)
    }

    private func bringToFront(_ controller: NSWindowController) {
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

private final class WindowCloseObserver: NSObject, NSWindowDelegate {
    private let onClose: () -> Void

    init(onClose: @escaping () -> Void) {
        self.onClose = onClose
    }

    func windowWillClose(_ notification: Notification) {
        onClose()
    }
}
