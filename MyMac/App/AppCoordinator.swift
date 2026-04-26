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
        diagnosticsService: DiagnosticsService
    ) {
        self.appState = appState
        self.settingsStore = settingsStore
        self.permissionService = permissionService
        self.launchAtLoginService = launchAtLoginService
        self.keyboardMappingService = keyboardMappingService
        self.diagnosticsService = diagnosticsService
    }

    var isLaunchAtLoginToggleOn: Bool {
        appState.launchAtLoginStatus.isToggleOn
    }

    func handleAppLaunch() async {
        diagnosticsService.log("Application launched", category: .app)
        syncStateFromStore()
        syncLaunchAtLoginStatus()

        if !appState.hasCompletedOnboarding {
            showOnboarding()
        }

        await synchronizePermissionsAndRuntimeState(trigger: .appLaunch)
    }

    func handleAppDidBecomeActive() async {
        await synchronizePermissionsAndRuntimeState(trigger: .appDidBecomeActive)
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

    func recheckPermissions() async {
        await synchronizePermissionsAndRuntimeState(trigger: .manualRecheck)
    }

    func requestPermissions() async {
        diagnosticsService.log(
            "User requested Accessibility prompt",
            category: .permissions
        )
        let requestedPermissions = await permissionService.requestRequiredPermissions()
        await synchronizePermissionsAndRuntimeState(
            trigger: .userRequestedPrompt,
            permissions: requestedPermissions
        )
    }

    func openSystemSettings() {
        permissionService.openSystemSettings()
    }

    func setKeyboardMappingEnabled(_ enabled: Bool) async {
        settingsStore.isKeyboardMappingEnabled = enabled
        appState.isKeyboardMappingEnabled = enabled
        await reconcileKeyboardMappingState()
    }

    func setInputSourceSwitchingEnabled(_ enabled: Bool) async {
        settingsStore.isInputSourceSwitchingEnabled = enabled
        appState.isInputSourceSwitchingEnabled = enabled
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
        await synchronizePermissionsAndRuntimeState(trigger: .onboardingCompleted)
    }

    private func syncStateFromStore() {
        appState.isKeyboardMappingEnabled = settingsStore.isKeyboardMappingEnabled
        appState.isInputSourceSwitchingEnabled = settingsStore.isInputSourceSwitchingEnabled
        appState.hasCompletedOnboarding = settingsStore.hasCompletedOnboarding
    }

    private func syncLaunchAtLoginStatus() {
        appState.launchAtLoginStatus = launchAtLoginService.currentStatus()
    }

    private func synchronizePermissionsAndRuntimeState(
        trigger: PermissionSynchronizationTrigger,
        permissions: PermissionsSnapshot? = nil
    ) async {
        if let permissions {
            appState.permissions = permissions
        } else {
            appState.permissions = await permissionService.refreshStatus()
        }

        diagnosticsService.log(
            "Permissions synchronized (\(trigger.logDescription)): accessibility=\(appState.permissions.accessibility.displayName)",
            category: .permissions
        )

        await reconcileKeyboardMappingState()
        diagnosticsService.log(
            "Runtime reconciled (\(trigger.logDescription)): status=\(appState.runtimeStatus.displayName)",
            category: .permissions
        )
    }

    private func reconcileKeyboardMappingState() async {
        let configuration = KeyboardMappingConfiguration(
            isArrowKeyMappingEnabled: appState.isKeyboardMappingEnabled,
            isInputSourceSwitchingEnabled: appState.isInputSourceSwitchingEnabled
        )

        await keyboardMappingService.updateConfiguration(configuration)

        if !configuration.shouldListenForKeyboardEvents {
            await keyboardMappingService.stop()
            appState.runtimeStatus = .paused
            return
        }

        if !permissionService.canStartMapping(appState.permissions) {
            await keyboardMappingService.stop()
            appState.runtimeStatus = .missingPermissions
            return
        }

        let currentStatus = await keyboardMappingService.currentStatus()

        switch currentStatus {
        case .running:
            break
        case .tapDisabled, .failed:
            await keyboardMappingService.stop()
            await keyboardMappingService.start()
        default:
            await keyboardMappingService.start()
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

private enum PermissionSynchronizationTrigger {
    case appLaunch
    case appDidBecomeActive
    case manualRecheck
    case onboardingCompleted
    case userRequestedPrompt

    var logDescription: String {
        switch self {
        case .appLaunch:
            return "app launch"
        case .appDidBecomeActive:
            return "app became active"
        case .manualRecheck:
            return "manual recheck"
        case .onboardingCompleted:
            return "onboarding completed"
        case .userRequestedPrompt:
            return "user requested prompt"
        }
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
