import Observation

@MainActor
@Observable
final class AppState {
    var permissions: PermissionsSnapshot
    var runtimeStatus: RuntimeStatus
    var launchAtLoginStatus: LaunchAtLoginStatus
    var isKeyboardMappingEnabled: Bool
    var hasCompletedOnboarding: Bool

    init(settingsStore: SettingsStore) {
        permissions = .unknown
        runtimeStatus = .starting
        launchAtLoginStatus = .disabled
        isKeyboardMappingEnabled = settingsStore.isKeyboardMappingEnabled
        hasCompletedOnboarding = settingsStore.hasCompletedOnboarding
    }

    var permissionSummary: String {
        if permissions.accessibility == .granted && permissions.inputMonitoring == .granted {
            return "已授权"
        }

        return "需要处理"
    }

    var menuBarSystemImage: String {
        switch runtimeStatus {
        case .running:
            return "keyboard.fill"
        case .paused:
            return "pause.circle"
        case .missingPermissions:
            return "exclamationmark.triangle"
        case .tapDisabled:
            return "bolt.slash"
        case .failed:
            return "xmark.octagon"
        case .starting, .unavailable:
            return "keyboard"
        }
    }
}
