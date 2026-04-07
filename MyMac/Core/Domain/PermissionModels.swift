enum PermissionState: Sendable, Equatable {
    case unknown
    case granted
    case denied
    case requiresUserAction

    var displayName: String {
        switch self {
        case .unknown:
            return "Unknown"
        case .granted:
            return "Granted"
        case .denied:
            return "Denied"
        case .requiresUserAction:
            return "Action Required"
        }
    }
}

struct PermissionsSnapshot: Sendable, Equatable {
    var accessibility: PermissionState

    static let unknown = Self(accessibility: .unknown)
}
