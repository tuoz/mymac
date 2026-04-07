import AppKit
import ApplicationServices
import CoreGraphics

protocol PermissionService: Sendable {
    func refreshStatus() async -> PermissionsSnapshot
    func requestRequiredPermissions() async -> PermissionsSnapshot
    func openSystemSettings(for kind: PermissionKind?)
    func canStartMapping(_ permissions: PermissionsSnapshot) -> Bool
}

protocol PermissionSystemClient: Sendable {
    func preflightListenEventAccess() -> Bool
    func requestListenEventAccess() -> Bool
    func preflightPostEventAccess() -> Bool
    func requestPostEventAccess() -> Bool
    func isAccessibilityTrusted() -> Bool
    func requestAccessibilityPrompt()
}

struct CoreGraphicsPermissionSystemClient: PermissionSystemClient {
    func preflightListenEventAccess() -> Bool {
        CGPreflightListenEventAccess()
    }

    func requestListenEventAccess() -> Bool {
        CGRequestListenEventAccess()
    }

    func preflightPostEventAccess() -> Bool {
        CGPreflightPostEventAccess()
    }

    func requestPostEventAccess() -> Bool {
        CGRequestPostEventAccess()
    }

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
        let inputMonitoringState: PermissionState = client.preflightListenEventAccess() ? .granted : .requiresUserAction
        let accessibilityState: PermissionState = (client.preflightPostEventAccess() && client.isAccessibilityTrusted()) ? .granted : .requiresUserAction

        return PermissionsSnapshot(
            accessibility: accessibilityState,
            inputMonitoring: inputMonitoringState
        )
    }

    func requestRequiredPermissions() async -> PermissionsSnapshot {
        if !client.preflightListenEventAccess() {
            _ = client.requestListenEventAccess()
        }

        if !client.preflightPostEventAccess() {
            _ = client.requestPostEventAccess()
        }

        if !client.isAccessibilityTrusted() {
            client.requestAccessibilityPrompt()
        }

        return await refreshStatus()
    }

    func openSystemSettings(for kind: PermissionKind?) {
        let urlString: String

        switch kind {
        case .inputMonitoring:
            urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"
        case .accessibility, .none:
            urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        }

        guard let url = URL(string: urlString) else {
            return
        }

        NSWorkspace.shared.open(url)
    }

    func canStartMapping(_ permissions: PermissionsSnapshot) -> Bool {
        permissions.accessibility == .granted && permissions.inputMonitoring == .granted
    }
}
