import ServiceManagement

protocol LaunchAtLoginService: Sendable {
    func currentStatus() -> LaunchAtLoginStatus
    func setEnabled(_ enabled: Bool) throws
}

struct LaunchAtLoginStatusMapper {
    static func map(_ status: SMAppService.Status) -> LaunchAtLoginStatus {
        switch status {
        case .enabled:
            return .enabled
        case .notRegistered:
            return .disabled
        case .requiresApproval:
            return .requiresApproval
        case .notFound:
            return .unavailable
        @unknown default:
            return .unavailable
        }
    }
}

struct SystemLaunchAtLoginService: LaunchAtLoginService {
    private let diagnosticsService: DiagnosticsService

    init(diagnosticsService: DiagnosticsService) {
        self.diagnosticsService = diagnosticsService
    }

    func currentStatus() -> LaunchAtLoginStatus {
        LaunchAtLoginStatusMapper.map(SMAppService.mainApp.status)
    }

    func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
            diagnosticsService.log("Launch at login enabled", category: .launchAtLogin)
        } else {
            try SMAppService.mainApp.unregister()
            diagnosticsService.log("Launch at login disabled", category: .launchAtLogin)
        }
    }
}
