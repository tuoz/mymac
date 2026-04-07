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

        let action = engine.action(for: event, effectiveModifiers: [.fn], snapshot: snapshot)

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

        let action = engine.action(for: event, effectiveModifiers: [.fn, .command], snapshot: snapshot)

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

        XCTAssertNil(engine.action(for: event, effectiveModifiers: [.fn], snapshot: snapshot))
    }

    func testRemovesFnFromOutputModifiers() {
        let event = KeyEventSnapshot(
            kind: .keyUp,
            keyCode: KeyCode.ansiL,
            modifiers: [.fn, .shift, .option],
            isAutorepeat: true
        )

        let action = engine.action(for: event, effectiveModifiers: [.fn, .shift, .option], snapshot: snapshot)

        XCTAssertEqual(
            action,
            .keyboard(keyCode: KeyCode.rightArrow, modifiers: [.shift, .option], kind: .keyUp, isAutorepeat: true)
        )
    }

    func testUsesEffectiveModifiersForFnTracking() {
        let event = KeyEventSnapshot(
            kind: .keyDown,
            keyCode: KeyCode.ansiJ,
            modifiers: [],
            isAutorepeat: false
        )

        let action = engine.action(for: event, effectiveModifiers: [.fn, .command], snapshot: snapshot)

        XCTAssertEqual(
            action,
            .keyboard(keyCode: KeyCode.downArrow, modifiers: [.command], kind: .keyDown, isAutorepeat: false)
        )
    }
}

final class ModifierSetTests: XCTestCase {
    func testConvertsFromCGEventFlags() {
        let flags: CGEventFlags = [.maskCommand, .maskShift, .maskSecondaryFn]
        let modifiers = ModifierSet(cgEventFlags: flags)

        XCTAssertTrue(modifiers.contains(.command))
        XCTAssertTrue(modifiers.contains(.shift))
        XCTAssertTrue(modifiers.contains(.fn))
        XCTAssertFalse(modifiers.contains(.option))
    }

    func testConvertsToCGEventFlagsWithoutFn() {
        let modifiers: ModifierSet = [.command, .option, .fn]
        let flags = modifiers.cgEventFlags

        XCTAssertTrue(flags.contains(.maskCommand))
        XCTAssertTrue(flags.contains(.maskAlternate))
        XCTAssertFalse(flags.contains(.maskSecondaryFn))
    }

    func testReadsEventMarkerFromInjectedEvent() {
        let marker: Int64 = 0x123456
        let event = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(KeyCode.leftArrow), keyDown: true)

        XCTAssertNotNil(event)
        event?.setIntegerValueField(.eventSourceUserData, value: marker)
        XCTAssertEqual(event?.eventMarker, marker)
    }
}
