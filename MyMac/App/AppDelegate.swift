import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var hasSkippedInitialActivationRefresh = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor in
            await AppBootstrap.shared.coordinator?.handleAppLaunch()
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        guard hasSkippedInitialActivationRefresh else {
            hasSkippedInitialActivationRefresh = true
            return
        }

        Task { @MainActor in
            await AppBootstrap.shared.coordinator?.handleAppDidBecomeActive()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
