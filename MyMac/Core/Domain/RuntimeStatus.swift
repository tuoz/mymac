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
            return "Starting"
        case .running:
            return "Running"
        case .paused:
            return "Paused"
        case .missingPermissions:
            return "Missing Permissions"
        case .tapDisabled:
            return "Tap Disabled"
        case .unavailable:
            return "Unavailable"
        case .failed(let message):
            return "Failed: \(message)"
        }
    }
}
