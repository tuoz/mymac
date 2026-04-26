enum PermissionState: Sendable, Equatable {
    case unknown
    case granted
    case denied
    case requiresUserAction

    var displayName: String {
        switch self {
        case .unknown:
            return "未知"
        case .granted:
            return "已授权"
        case .denied:
            return "已拒绝"
        case .requiresUserAction:
            return "需要处理"
        }
    }
}

struct PermissionsSnapshot: Sendable, Equatable {
    var accessibility: PermissionState

    static let unknown = Self(accessibility: .unknown)
}
