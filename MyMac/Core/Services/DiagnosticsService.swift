import Foundation
import OSLog

enum DiagnosticsCategory: String, Sendable {
    case app
    case permissions
    case launchAtLogin
    case keyboardMapping
}

protocol DiagnosticsService: Sendable {
    func log(_ message: String, category: DiagnosticsCategory)
    func error(_ message: String, category: DiagnosticsCategory)
}

struct LoggerDiagnosticsService: DiagnosticsService {
    private let subsystem: String

    init(subsystem: String = Bundle.main.bundleIdentifier ?? "com.local.mymac") {
        self.subsystem = subsystem
    }

    func log(_ message: String, category: DiagnosticsCategory) {
        Logger(subsystem: subsystem, category: category.rawValue)
            .info("\(message, privacy: .public)")
    }

    func error(_ message: String, category: DiagnosticsCategory) {
        Logger(subsystem: subsystem, category: category.rawValue)
            .error("\(message, privacy: .public)")
    }
}
