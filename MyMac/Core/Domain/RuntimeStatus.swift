enum RuntimeStatus: Sendable, Equatable {
    case starting
    case running
    case paused
    case missingPermissions
    case tapDisabled
    case unavailable
    case failed(String)

    var displayName: String {
        switch self {
        case .starting:
            return "启动中"
        case .running:
            return "运行中"
        case .paused:
            return "已暂停"
        case .missingPermissions:
            return "缺少权限"
        case .tapDisabled:
            return "监听已停用"
        case .unavailable:
            return "不可用"
        case .failed(let message):
            return "失败：\(message)"
        }
    }
}
