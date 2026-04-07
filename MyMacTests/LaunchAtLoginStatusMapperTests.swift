import ServiceManagement
import XCTest
@testable import MyMac

final class LaunchAtLoginStatusMapperTests: XCTestCase {
    func testMapsServiceManagementStatuses() {
        XCTAssertEqual(LaunchAtLoginStatusMapper.map(.enabled), .enabled)
        XCTAssertEqual(LaunchAtLoginStatusMapper.map(.notRegistered), .disabled)
        XCTAssertEqual(LaunchAtLoginStatusMapper.map(.requiresApproval), .requiresApproval)
        XCTAssertEqual(LaunchAtLoginStatusMapper.map(.notFound), .unavailable)
    }
}
