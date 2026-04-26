import Foundation

final class SettingsStore {
    enum Key {
        static let hasCompletedOnboarding = "hasCompletedOnboarding"
        static let isKeyboardMappingEnabled = "isKeyboardMappingEnabled"
        static let isInputSourceSwitchingEnabled = "isInputSourceSwitchingEnabled"
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

    var isInputSourceSwitchingEnabled: Bool {
        get { userDefaults.bool(forKey: Key.isInputSourceSwitchingEnabled) }
        set { userDefaults.set(newValue, forKey: Key.isInputSourceSwitchingEnabled) }
    }

    var launchAtLoginDesired: Bool {
        get { userDefaults.bool(forKey: Key.launchAtLoginDesired) }
        set { userDefaults.set(newValue, forKey: Key.launchAtLoginDesired) }
    }

    private func registerDefaults() {
        userDefaults.register(defaults: [
            Key.hasCompletedOnboarding: false,
            Key.isKeyboardMappingEnabled: true,
            Key.isInputSourceSwitchingEnabled: true,
            Key.launchAtLoginDesired: false,
        ])
    }
}
