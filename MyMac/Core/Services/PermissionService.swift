import AppKit
import ApplicationServices

protocol PermissionService: Sendable {
    func refreshStatus() async -> PermissionsSnapshot
    func openSystemSettings()
    func canStartMapping(_ permissions: PermissionsSnapshot) -> Bool
}

struct DefaultPermissionService: PermissionService {
    func refreshStatus() async -> PermissionsSnapshot {
        let accessibilityState: PermissionState = AXIsProcessTrusted() ? .granted : .requiresUserAction
        return PermissionsSnapshot(
            accessibility: accessibilityState,
            inputMonitoring: accessibilityState
        )
    }

    func openSystemSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else {
            return
        }

        NSWorkspace.shared.open(url)
    }

    func canStartMapping(_ permissions: PermissionsSnapshot) -> Bool {
        permissions.accessibility == .granted && permissions.inputMonitoring == .granted
    }
}
