import Foundation

final class SettingsStore {
    enum Key {
        static let hasCompletedOnboarding = "hasCompletedOnboarding"
        static let isKeyboardMappingEnabled = "isKeyboardMappingEnabled"
        static let launchAtLoginDesired = "launchAtLoginDesired"
    }

    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        registerDefaults()
    }

    var hasCompletedOnboarding: Bool {
        get { userDefaults.bool(forKey: Key.hasCompletedOnboarding) }
        set { userDefaults.set(newValue, forKey: Key.hasCompletedOnboarding) }
    }

    var isKeyboardMappingEnabled: Bool {
        get { userDefaults.bool(forKey: Key.isKeyboardMappingEnabled) }
        set { userDefaults.set(newValue, forKey: Key.isKeyboardMappingEnabled) }
    }

    var launchAtLoginDesired: Bool {
        get { userDefaults.bool(forKey: Key.launchAtLoginDesired) }
        set { userDefaults.set(newValue, forKey: Key.launchAtLoginDesired) }
    }

    private func registerDefaults() {
        userDefaults.register(defaults: [
            Key.hasCompletedOnboarding: false,
            Key.isKeyboardMappingEnabled: true,
            Key.launchAtLoginDesired: false,
        ])
    }
}
