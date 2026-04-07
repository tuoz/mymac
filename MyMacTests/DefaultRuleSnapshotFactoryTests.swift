import XCTest
@testable import MyMac

final class DefaultRuleSnapshotFactoryTests: XCTestCase {
    func testCreatesExpectedMappings() {
        let snapshot = DefaultRuleSnapshotFactory().makeSnapshot(isEnabled: true)

        XCTAssertTrue(snapshot.isEnabled)
        XCTAssertEqual(snapshot.mappings.count, 4)
        XCTAssertEqual(
            snapshot.mappings[InputChord(keyCode: KeyCode.ansiH, requiredModifiers: .fn)],
            .keyboard(keyCode: KeyCode.leftArrow, modifiers: [], kind: .keyDown, isAutorepeat: false)
        )
        XCTAssertEqual(
            snapshot.mappings[InputChord(keyCode: KeyCode.ansiJ, requiredModifiers: .fn)],
            .keyboard(keyCode: KeyCode.downArrow, modifiers: [], kind: .keyDown, isAutorepeat: false)
        )
        XCTAssertEqual(
            snapshot.mappings[InputChord(keyCode: KeyCode.ansiK, requiredModifiers: .fn)],
            .keyboard(keyCode: KeyCode.upArrow, modifiers: [], kind: .keyDown, isAutorepeat: false)
        )
        XCTAssertEqual(
            snapshot.mappings[InputChord(keyCode: KeyCode.ansiL, requiredModifiers: .fn)],
            .keyboard(keyCode: KeyCode.rightArrow, modifiers: [], kind: .keyDown, isAutorepeat: false)
        )
    }
}
