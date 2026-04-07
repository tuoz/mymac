import Foundation
import XCTest
@testable import MyMac

final class SettingsStoreTests: XCTestCase {
    func testRegistersDefaults() {
        let suiteName = "SettingsStoreTests.defaults.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = SettingsStore(userDefaults: defaults)

        XCTAssertFalse(store.hasCompletedOnboarding)
        XCTAssertTrue(store.isKeyboardMappingEnabled)
        XCTAssertFalse(store.launchAtLoginDesired)
    }

    func testPersistsValues() {
        let suiteName = "SettingsStoreTests.persist.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = SettingsStore(userDefaults: defaults)
        store.hasCompletedOnboarding = true
        store.isKeyboardMappingEnabled = false
        store.launchAtLoginDesired = true

        let reloadedStore = SettingsStore(userDefaults: defaults)

        XCTAssertTrue(reloadedStore.hasCompletedOnboarding)
        XCTAssertFalse(reloadedStore.isKeyboardMappingEnabled)
        XCTAssertTrue(reloadedStore.launchAtLoginDesired)
    }
}
