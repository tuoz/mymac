import XCTest
@testable import MyMac

final class KeyMappingEngineTests: XCTestCase {
    private let engine = KeyMappingEngine()
    private let snapshot = DefaultRuleSnapshotFactory().makeSnapshot(isEnabled: true)

    func testMapsFnHToLeftArrow() {
        let event = KeyEventSnapshot(
            kind: .keyDown,
            keyCode: KeyCode.ansiH,
            modifiers: [.fn],
            isAutorepeat: false
        )

        let action = engine.action(for: event, snapshot: snapshot)

        XCTAssertEqual(
            action,
            .keyboard(keyCode: KeyCode.leftArrow, modifiers: [], kind: .keyDown, isAutorepeat: false)
        )
    }

    func testPreservesNonFnModifiers() {
        let event = KeyEventSnapshot(
            kind: .keyDown,
            keyCode: KeyCode.ansiH,
            modifiers: [.fn, .command],
            isAutorepeat: false
        )

        let action = engine.action(for: event, snapshot: snapshot)

        XCTAssertEqual(
            action,
            .keyboard(keyCode: KeyCode.leftArrow, modifiers: [.command], kind: .keyDown, isAutorepeat: false)
        )
    }

    func testIgnoresNonMappedKeys() {
        let event = KeyEventSnapshot(
            kind: .keyDown,
            keyCode: 0,
            modifiers: [.fn],
            isAutorepeat: false
        )

        XCTAssertNil(engine.action(for: event, snapshot: snapshot))
    }

    func testRemovesFnFromOutputModifiers() {
        let event = KeyEventSnapshot(
            kind: .keyUp,
            keyCode: KeyCode.ansiL,
            modifiers: [.fn, .shift, .option],
            isAutorepeat: true
        )

        let action = engine.action(for: event, snapshot: snapshot)

        XCTAssertEqual(
            action,
            .keyboard(keyCode: KeyCode.rightArrow, modifiers: [.shift, .option], kind: .keyUp, isAutorepeat: true)
        )
    }
}
