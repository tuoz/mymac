protocol KeyboardMappingService: Sendable {
    func start(with snapshot: RuleSnapshot) async
    func stop() async
    func reloadRules(_ snapshot: RuleSnapshot) async
    func currentStatus() async -> RuntimeStatus
}

actor StubKeyboardMappingService: KeyboardMappingService {
    private let diagnosticsService: DiagnosticsService
    private var status: RuntimeStatus = .paused
    private var activeSnapshot: RuleSnapshot?

    init(diagnosticsService: DiagnosticsService) {
        self.diagnosticsService = diagnosticsService
    }

    func start(with snapshot: RuleSnapshot) async {
        activeSnapshot = snapshot
        status = snapshot.isEnabled ? .running : .paused
        diagnosticsService.log("Stub keyboard mapping started", category: .keyboardMapping)
    }

    func stop() async {
        activeSnapshot = nil
        status = .paused
        diagnosticsService.log("Stub keyboard mapping stopped", category: .keyboardMapping)
    }

    func reloadRules(_ snapshot: RuleSnapshot) async {
        activeSnapshot = snapshot
        status = snapshot.isEnabled ? .running : .paused
        diagnosticsService.log("Stub keyboard mapping reloaded", category: .keyboardMapping)
    }

    func currentStatus() async -> RuntimeStatus {
        status
    }
}
