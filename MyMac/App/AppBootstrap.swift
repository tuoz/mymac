import Foundation

@MainActor
final class AppBootstrap {
    static let shared = AppBootstrap()

    var coordinator: AppCoordinator?

    private init() {}
}
