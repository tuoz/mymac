import AppKit
import ApplicationServices

protocol PermissionService: Sendable {
    func refreshStatus() async -> PermissionsSnapshot
    func requestRequiredPermissions() async -> PermissionsSnapshot
    func openSystemSettings()
    func canStartMapping(_ permissions: PermissionsSnapshot) -> Bool
}

protocol PermissionSystemClient: Sendable {
    func isAccessibilityTrusted() -> Bool
    func requestAccessibilityPrompt()
}

struct CoreGraphicsPermissionSystemClient: PermissionSystemClient {
    func isAccessibilityTrusted() -> Bool {
        AXIsProcessTrusted()
    }

    func requestAccessibilityPrompt() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }
}

struct DefaultPermissionService: PermissionService {
    private let client: PermissionSystemClient

    init(client: PermissionSystemClient = CoreGraphicsPermissionSystemClient()) {
        self.client = client
    }

    func refreshStatus() async -> PermissionsSnapshot {
        let accessibilityState: PermissionState = client.isAccessibilityTrusted() ? .granted : .requiresUserAction

        return PermissionsSnapshot(accessibility: accessibilityState)
    }

    func requestRequiredPermissions() async -> PermissionsSnapshot {
        if !client.isAccessibilityTrusted() {
            client.requestAccessibilityPrompt()
        }

        return await refreshStatus()
    }

    func openSystemSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else {
            return
        }

        NSWorkspace.shared.open(url)
    }

    func canStartMapping(_ permissions: PermissionsSnapshot) -> Bool {
        permissions.accessibility == .granted
    }
}
