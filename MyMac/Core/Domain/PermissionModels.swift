enum PermissionKind: Sendable, Equatable {
    case accessibility
    case inputMonitoring

    var displayName: String {
        switch self {
        case .accessibility:
            return "Accessibility"
        case .inputMonitoring:
            return "Input Monitoring"
        }
    }
}

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
    var inputMonitoring: PermissionState

    static let unknown = Self(accessibility: .unknown, inputMonitoring: .unknown)
}
