import SwiftUI

@main
@MainActor
struct MyMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    private let appState: AppState
    private let coordinator: AppCoordinator

    init() {
        let settingsStore = SettingsStore()
        let diagnosticsService = LoggerDiagnosticsService()
        let permissionService = DefaultPermissionService()
        let launchAtLoginService = SystemLaunchAtLoginService(diagnosticsService: diagnosticsService)
        let keyboardMappingService = StubKeyboardMappingService(diagnosticsService: diagnosticsService)
        let appState = AppState(settingsStore: settingsStore)
        let coordinator = AppCoordinator(
            appState: appState,
            settingsStore: settingsStore,
            permissionService: permissionService,
            launchAtLoginService: launchAtLoginService,
            keyboardMappingService: keyboardMappingService,
            diagnosticsService: diagnosticsService
        )

        self.appState = appState
        self.coordinator = coordinator
        AppBootstrap.shared.coordinator = coordinator
    }

    var body: some Scene {
        MenuBarExtra("MyMac", systemImage: appState.menuBarSystemImage) {
            MenuBarContentView(coordinator: coordinator)
                .environment(appState)
        }
        .menuBarExtraStyle(.menu)
    }
}
