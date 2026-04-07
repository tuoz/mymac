enum LaunchAtLoginStatus: Sendable, Equatable {
    case enabled
    case disabled
    case requiresApproval
    case unavailable

    var displayName: String {
        switch self {
        case .enabled:
            return "Enabled"
        case .disabled:
            return "Disabled"
        case .requiresApproval:
            return "Requires Approval"
        case .unavailable:
            return "Unavailable"
        }
    }

    var isToggleOn: Bool {
        switch self {
        case .enabled, .requiresApproval:
            return true
        case .disabled, .unavailable:
            return false
        }
    }
}
