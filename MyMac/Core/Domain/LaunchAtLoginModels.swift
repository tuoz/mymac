enum LaunchAtLoginStatus: Sendable, Equatable {
    case enabled
    case disabled
    case requiresApproval
    case unavailable

    var displayName: String {
        switch self {
        case .enabled:
            return "已启用"
        case .disabled:
            return "已停用"
        case .requiresApproval:
            return "需要批准"
        case .unavailable:
            return "不可用"
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
