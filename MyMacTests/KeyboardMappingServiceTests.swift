import Carbon.HIToolbox
import XCTest
@testable import MyMac

final class KeyboardEventTranslatorTests: XCTestCase {
    private let translator = KeyboardEventTranslator()

    func testMapsFnHKeyDownToLeftArrow() {
        let payload = translator.translate(
            eventType: .keyDown,
            keyCode: CGKeyCode(kVK_ANSI_H),
            eventFlags: [.maskSecondaryFn],
            trackedFlags: [],
            isAutorepeat: false
        )

        XCTAssertEqual(
            payload,
            InjectedKeyEventPayload(
                targetKeyCode: CGKeyCode(kVK_LeftArrow),
                outputFlags: [],
                isKeyDown: true,
                isAutorepeat: false
            )
        )
    }

    func testMapsCommandFnLToCommandRightArrow() {
        let payload = translator.translate(
            eventType: .keyDown,
            keyCode: CGKeyCode(kVK_ANSI_L),
            eventFlags: [.maskCommand, .maskSecondaryFn],
            trackedFlags: [],
            isAutorepeat: false
        )

        XCTAssertEqual(
            payload,
            InjectedKeyEventPayload(
                targetKeyCode: CGKeyCode(kVK_RightArrow),
                outputFlags: [.maskCommand],
                isKeyDown: true,
                isAutorepeat: false
            )
        )
    }

    func testMapsControlFnLKeyDownToControlRightArrow() {
        let payload = translator.translate(
            eventType: .keyDown,
            keyCode: CGKeyCode(kVK_ANSI_L),
            eventFlags: [.maskControl, .maskSecondaryFn],
            trackedFlags: [],
            isAutorepeat: false
        )

        XCTAssertEqual(
            payload,
            InjectedKeyEventPayload(
                targetKeyCode: CGKeyCode(kVK_RightArrow),
                outputFlags: [.maskControl],
                isKeyDown: true,
                isAutorepeat: false
            )
        )
    }

    func testPreservesRawFlagsWhenRemovingFn() {
        let payload = translator.translate(
            eventType: .keyDown,
            keyCode: CGKeyCode(kVK_ANSI_L),
            eventFlags: CGEventFlags(rawValue: 0x842100),
            trackedFlags: CGEventFlags(rawValue: 0x840000),
            isAutorepeat: false
        )

        XCTAssertEqual(payload?.targetKeyCode, CGKeyCode(kVK_RightArrow))
        XCTAssertEqual(payload?.outputFlags.rawValue, 0x42100)
        XCTAssertEqual(payload?.outputFlags.contains(.maskControl), true)
        XCTAssertEqual(payload?.outputFlags.contains(.maskSecondaryFn), false)
    }

    func testPreservesRawFlagsForCommandMappings() {
        let payload = translator.translate(
            eventType: .keyDown,
            keyCode: CGKeyCode(kVK_ANSI_L),
            eventFlags: CGEventFlags(rawValue: 0x900108),
            trackedFlags: CGEventFlags(rawValue: 0x900000),
            isAutorepeat: false
        )

        XCTAssertEqual(payload?.targetKeyCode, CGKeyCode(kVK_RightArrow))
        XCTAssertEqual(payload?.outputFlags.rawValue, 0x100108)
        XCTAssertEqual(payload?.outputFlags.contains(.maskCommand), true)
        XCTAssertEqual(payload?.outputFlags.contains(.maskSecondaryFn), false)
    }

    func testMapsControlFnLKeyUpToControlRightArrow() {
        let payload = translator.translate(
            eventType: .keyUp,
            keyCode: CGKeyCode(kVK_ANSI_L),
            eventFlags: [.maskControl, .maskSecondaryFn],
            trackedFlags: [],
            isAutorepeat: false
        )

        XCTAssertEqual(
            payload,
            InjectedKeyEventPayload(
                targetKeyCode: CGKeyCode(kVK_RightArrow),
                outputFlags: [.maskControl],
                isKeyDown: false,
                isAutorepeat: false
            )
        )
    }

    func testMapsShiftOptionFnLToShiftOptionRightArrow() {
        let payload = translator.translate(
            eventType: .keyDown,
            keyCode: CGKeyCode(kVK_ANSI_L),
            eventFlags: [.maskShift, .maskAlternate, .maskSecondaryFn],
            trackedFlags: [],
            isAutorepeat: false
        )

        XCTAssertEqual(
            payload,
            InjectedKeyEventPayload(
                targetKeyCode: CGKeyCode(kVK_RightArrow),
                outputFlags: [.maskShift, .maskAlternate],
                isKeyDown: true,
                isAutorepeat: false
            )
        )
    }

    func testPreservesAutorepeat() {
        let payload = translator.translate(
            eventType: .keyDown,
            keyCode: CGKeyCode(kVK_ANSI_L),
            eventFlags: [.maskSecondaryFn],
            trackedFlags: [],
            isAutorepeat: true
        )

        XCTAssertEqual(payload?.isAutorepeat, true)
    }

    func testUsesTrackedFlagsWhenEventFlagsMissControl() {
        let payload = translator.translate(
            eventType: .keyDown,
            keyCode: CGKeyCode(kVK_ANSI_L),
            eventFlags: CGEventFlags(rawValue: 0x800100),
            trackedFlags: [.maskControl, .maskSecondaryFn],
            isAutorepeat: false
        )

        XCTAssertEqual(payload?.targetKeyCode, CGKeyCode(kVK_RightArrow))
        XCTAssertEqual(payload?.outputFlags.rawValue, 0x40100)
        XCTAssertEqual(payload?.outputFlags.contains(.maskControl), true)
        XCTAssertEqual(payload?.outputFlags.contains(.maskSecondaryFn), false)
        XCTAssertEqual(payload?.isKeyDown, true)
        XCTAssertEqual(payload?.isAutorepeat, false)
    }

    func testIgnoresNonMappedKeys() {
        let payload = translator.translate(
            eventType: .keyDown,
            keyCode: CGKeyCode(kVK_ANSI_A),
            eventFlags: [.maskSecondaryFn],
            trackedFlags: [],
            isAutorepeat: false
        )

        XCTAssertNil(payload)
    }

    func testIgnoresKeysWithoutFn() {
        let payload = translator.translate(
            eventType: .keyDown,
            keyCode: CGKeyCode(kVK_ANSI_L),
            eventFlags: [.maskControl],
            trackedFlags: [],
            isAutorepeat: false
        )

        XCTAssertNil(payload)
    }

    func testOutputFlagsNeverContainFn() {
        let payload = translator.translate(
            eventType: .keyDown,
            keyCode: CGKeyCode(kVK_ANSI_L),
            eventFlags: [.maskCommand, .maskSecondaryFn],
            trackedFlags: [],
            isAutorepeat: false
        )

        XCTAssertEqual(payload?.outputFlags.contains(.maskSecondaryFn), false)
    }
}

final class ModifierStateTrackerTests: XCTestCase {
    func testTracksOnlyRelevantFlags() {
        var tracker = ModifierStateTracker()
        tracker.update(with: [.maskControl, .maskSecondaryFn, .maskAlphaShift])

        XCTAssertEqual(tracker.activeFlags, [.maskControl, .maskSecondaryFn])
    }

    func testResetClearsTrackedFlags() {
        var tracker = ModifierStateTracker()
        tracker.update(with: [.maskControl, .maskSecondaryFn])
        tracker.reset()

        XCTAssertEqual(tracker.activeFlags, [])
    }
}

final class CGEventHelpersTests: XCTestCase {
    func testReadsEventMarkerFromInjectedEvent() {
        let marker: Int64 = 0x123456
        let event = CGEvent(
            keyboardEventSource: nil,
            virtualKey: CGKeyCode(kVK_LeftArrow),
            keyDown: true
        )

        XCTAssertNotNil(event)
        event?.setIntegerValueField(.eventSourceUserData, value: marker)
        XCTAssertEqual(event?.eventMarker, marker)
    }
}
