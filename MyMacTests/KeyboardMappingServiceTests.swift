import Carbon.HIToolbox
import XCTest
@testable import MyMac

final class KeyboardEventTranslatorTests: XCTestCase {
    private let translator = KeyboardEventTranslator()

    func testMapsFnBackspacePressRepeatAndReleaseToForwardDelete() {
        for (eventType, isAutorepeat) in [(CGEventType.keyDown, false), (.keyDown, true), (.keyUp, false)] {
            let payload = translator.translate(
                eventType: eventType,
                keyCode: CGKeyCode(kVK_Delete),
                eventFlags: [.maskSecondaryFn, .maskShift, .maskAlternate],
                trackedFlags: [],
                isAutorepeat: isAutorepeat
            )

            XCTAssertEqual(payload, InjectedKeyEventPayload(
                targetKeyCode: CGKeyCode(kVK_ForwardDelete),
                outputFlags: [.maskShift, .maskAlternate],
                isKeyDown: eventType == .keyDown,
                isAutorepeat: isAutorepeat
            ))
        }
    }

    func testMapsBackspaceUsingTrackedFnState() {
        let payload = translator.translate(
            eventType: .keyDown,
            keyCode: CGKeyCode(kVK_Delete),
            eventFlags: [],
            trackedFlags: [.maskSecondaryFn],
            isAutorepeat: false
        )

        XCTAssertEqual(payload, InjectedKeyEventPayload(
            targetKeyCode: CGKeyCode(kVK_ForwardDelete),
            outputFlags: [],
            isKeyDown: true,
            isAutorepeat: false
        ))
    }

    func testPassesThroughOrdinaryBackspaceAndNativeForwardDelete() {
        for eventType in [CGEventType.keyDown, .keyUp] {
            for (keyCode, flags) in [
                (kVK_Delete, CGEventFlags()),
                (kVK_ForwardDelete, CGEventFlags.maskSecondaryFn),
            ] {
                XCTAssertNil(translator.translate(
                    eventType: eventType,
                    keyCode: CGKeyCode(keyCode),
                    eventFlags: flags,
                    trackedFlags: [],
                    isAutorepeat: false
                ))
            }
        }
    }

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

final class KeyPressRouterTests: XCTestCase {
    private var router = KeyPressRouter()
    private var injected: [InjectedKeyEventPayload] = []
    private var injectionSucceeds = true
    private var heldFlags: CGEventFlags = []
    private var configuration = KeyboardMappingConfiguration.allEnabled

    func testFnBackspaceThenJWithFnReleasedFirstEmitsMatchingKeyUps() {
        for releaseBackspaceFirst in [false, true] {
            resetState()

            heldFlags = [.maskSecondaryFn]
            XCTAssertEqual(send(.keyDown, kVK_Delete), .consume)
            XCTAssertEqual(send(.keyDown, kVK_ANSI_J), .consume)
            XCTAssertEqual(send(.keyDown, kVK_ANSI_J, isAutorepeat: true), .consume)
            heldFlags = []

            let releaseOrder = releaseBackspaceFirst ? [kVK_Delete, kVK_ANSI_J] : [kVK_ANSI_J, kVK_Delete]
            for keyCode in releaseOrder {
                XCTAssertEqual(send(.keyUp, keyCode), .consume)
            }

            let releasedTargets = releaseOrder.map { $0 == kVK_Delete ? kVK_ForwardDelete : kVK_DownArrow }
            XCTAssertEqual(injected, [
                key(kVK_ForwardDelete, isKeyDown: true),
                key(kVK_DownArrow, isKeyDown: true),
                key(kVK_DownArrow, isKeyDown: true, isAutorepeat: true),
            ] + releasedTargets.map { key($0, isKeyDown: false) })
            XCTAssertEqual(router.activeRoutes, [:])
        }
    }

    func testMapsEveryKeyForAWholePressCycle() {
        let mappings = [
            (kVK_Delete, kVK_ForwardDelete),
            (kVK_ANSI_H, kVK_LeftArrow),
            (kVK_ANSI_J, kVK_DownArrow),
            (kVK_ANSI_K, kVK_UpArrow),
            (kVK_ANSI_L, kVK_RightArrow),
        ]

        for (keyCode, targetKeyCode) in mappings {
            resetState()
            heldFlags = [.maskSecondaryFn]

            send(.keyDown, keyCode)
            send(.keyDown, keyCode, isAutorepeat: true)
            send(.keyUp, keyCode)

            XCTAssertEqual(injected, [
                key(targetKeyCode, isKeyDown: true),
                key(targetKeyCode, isKeyDown: true, isAutorepeat: true),
                key(targetKeyCode, isKeyDown: false),
            ])
            XCTAssertEqual(router.activeRoutes, [:])
        }
    }

    func testKeepsMappingForAutorepeatAfterFnIsReleased() {
        heldFlags = [.maskSecondaryFn]
        send(.keyDown, kVK_Delete)
        heldFlags = []

        XCTAssertEqual(send(.keyDown, kVK_Delete, isAutorepeat: true), .consume)
        XCTAssertEqual(send(.keyUp, kVK_Delete), .consume)

        XCTAssertEqual(injected, [
            key(kVK_ForwardDelete, isKeyDown: true),
            key(kVK_ForwardDelete, isKeyDown: true, isAutorepeat: true),
            key(kVK_ForwardDelete, isKeyDown: false),
        ])
    }

    func testUnrelatedKeyDuringMappedPressPassesThrough() {
        heldFlags = [.maskSecondaryFn]
        send(.keyDown, kVK_Delete)

        XCTAssertEqual(send(.keyDown, kVK_ANSI_F), .passThrough)
        XCTAssertEqual(send(.keyDown, kVK_ANSI_F, isAutorepeat: true), .passThrough)
        heldFlags = []
        XCTAssertEqual(send(.keyUp, kVK_ANSI_F), .passThrough)
        XCTAssertEqual(send(.keyUp, kVK_Delete), .consume)

        XCTAssertEqual(injected, [
            key(kVK_ForwardDelete, isKeyDown: true),
            key(kVK_ForwardDelete, isKeyDown: false),
        ])
    }

    func testKeyPressedBeforeFnStaysUnmappedForWholePress() {
        XCTAssertEqual(send(.keyDown, kVK_Delete), .passThrough)
        heldFlags = [.maskSecondaryFn]
        XCTAssertEqual(send(.keyDown, kVK_Delete, isAutorepeat: true), .passThrough)
        XCTAssertEqual(send(.keyUp, kVK_Delete), .passThrough)

        XCTAssertEqual(injected, [])
        XCTAssertEqual(router.activeRoutes, [:])
    }

    func testAutorepeatWithoutInitialKeyDownIsNotMapped() {
        heldFlags = [.maskSecondaryFn]

        XCTAssertEqual(send(.keyDown, kVK_ANSI_L, isAutorepeat: true), .passThrough)
        XCTAssertEqual(send(.keyUp, kVK_ANSI_L), .passThrough)
        XCTAssertEqual(injected, [])
    }

    func testUsesCurrentModifiersForAutorepeatAndKeyUp() {
        heldFlags = [.maskSecondaryFn]
        send(.keyDown, kVK_ANSI_L)
        heldFlags = [.maskSecondaryFn, .maskShift]
        send(.keyDown, kVK_ANSI_L, isAutorepeat: true)
        heldFlags = [.maskControl]
        send(.keyUp, kVK_ANSI_L)

        XCTAssertEqual(injected, [
            key(kVK_RightArrow, isKeyDown: true),
            key(kVK_RightArrow, isKeyDown: true, isAutorepeat: true, flags: [.maskShift]),
            key(kVK_RightArrow, isKeyDown: false, flags: [.maskControl]),
        ])
    }

    func testDisablingMappingMidPressStillReleasesMappedKey() {
        heldFlags = [.maskSecondaryFn]
        send(.keyDown, kVK_Delete)
        configuration.isKeyMappingEnabled = false

        XCTAssertEqual(send(.keyUp, kVK_Delete), .consume)
        XCTAssertEqual(send(.keyDown, kVK_Delete), .passThrough)
        XCTAssertEqual(send(.keyUp, kVK_Delete), .passThrough)

        XCTAssertEqual(injected, [
            key(kVK_ForwardDelete, isKeyDown: true),
            key(kVK_ForwardDelete, isKeyDown: false),
        ])
    }

    func testNewKeyDownClosesStaleRouteBeforeDecidingAgain() {
        heldFlags = [.maskSecondaryFn]
        send(.keyDown, kVK_Delete)
        heldFlags = []

        // The key up was lost; the next real press of the key closes the stale route.
        XCTAssertEqual(send(.keyDown, kVK_Delete), .passThrough)

        XCTAssertEqual(injected, [
            key(kVK_ForwardDelete, isKeyDown: true),
            key(kVK_ForwardDelete, isKeyDown: false),
        ])
        XCTAssertEqual(router.activeRoutes, [:])
    }

    func testFailedInitialInjectionPassesThroughWithoutRoute() {
        heldFlags = [.maskSecondaryFn]
        injectionSucceeds = false

        XCTAssertEqual(send(.keyDown, kVK_Delete), .passThrough)
        XCTAssertEqual(router.activeRoutes, [:])
        XCTAssertEqual(send(.keyUp, kVK_Delete), .passThrough)
    }

    func testFailedInjectionMidPressStillConsumesOriginalAndEndsOnKeyUp() {
        heldFlags = [.maskSecondaryFn]
        send(.keyDown, kVK_Delete)
        injectionSucceeds = false

        XCTAssertEqual(send(.keyDown, kVK_Delete, isAutorepeat: true), .consume)
        XCTAssertEqual(send(.keyUp, kVK_Delete), .consume)
        XCTAssertEqual(router.activeRoutes, [:])
    }

    func testReleaseAllEmitsKeyUpsForActiveMappedKeys() {
        heldFlags = [.maskSecondaryFn]
        send(.keyDown, kVK_ANSI_J)
        send(.keyDown, kVK_Delete)
        injected.removeAll()
        heldFlags = [.maskShift]

        let released = router.releaseAll(trackedFlags: heldFlags, inject: record)

        XCTAssertEqual(released, [CGKeyCode(kVK_ANSI_J), CGKeyCode(kVK_Delete)])
        XCTAssertEqual(injected, [
            key(kVK_DownArrow, isKeyDown: false, flags: [.maskShift]),
            key(kVK_ForwardDelete, isKeyDown: false, flags: [.maskShift]),
        ])
        XCTAssertEqual(router.activeRoutes, [:])
    }

    func testReleaseRoutesOnlyReleasesSelectedKeys() {
        heldFlags = [.maskSecondaryFn]
        send(.keyDown, kVK_ANSI_J)
        send(.keyDown, kVK_Delete)
        injected.removeAll()

        let released = router.releaseRoutes(
            where: { $0 == CGKeyCode(kVK_ANSI_J) },
            trackedFlags: [],
            inject: record
        )

        XCTAssertEqual(released, [CGKeyCode(kVK_ANSI_J)])
        XCTAssertEqual(injected, [key(kVK_DownArrow, isKeyDown: false)])
        XCTAssertEqual(router.activeRoutes, [CGKeyCode(kVK_Delete): .mapped(CGKeyCode(kVK_ForwardDelete))])
    }

    func testFnSpaceSwitchesOnceAndConsumesItsWholePress() {
        heldFlags = [.maskSecondaryFn]

        XCTAssertEqual(send(.keyDown, kVK_Space), .consumeAndSwitchInputSource)
        XCTAssertEqual(send(.keyDown, kVK_Space, isAutorepeat: true), .consume)
        heldFlags = []
        XCTAssertEqual(send(.keyUp, kVK_Space), .consume)

        XCTAssertEqual(injected, [])
        XCTAssertEqual(router.activeRoutes, [:])
    }

    func testSpacePressedBeforeFnPassesThroughForWholePress() {
        XCTAssertEqual(send(.keyDown, kVK_Space), .passThrough)
        heldFlags = [.maskSecondaryFn]
        XCTAssertEqual(send(.keyDown, kVK_Space, isAutorepeat: true), .passThrough)
        XCTAssertEqual(send(.keyUp, kVK_Space), .passThrough)
    }

    func testFnSpaceDisabledPassesThrough() {
        configuration.isInputSourceSwitchingEnabled = false
        heldFlags = [.maskSecondaryFn]

        XCTAssertEqual(send(.keyDown, kVK_Space), .passThrough)
        XCTAssertEqual(send(.keyUp, kVK_Space), .passThrough)
    }

    func testReleaseAllDropsShortcutRouteWithoutInjecting() {
        heldFlags = [.maskSecondaryFn]
        send(.keyDown, kVK_Space)

        XCTAssertEqual(router.releaseAll(trackedFlags: [], inject: record), [CGKeyCode(kVK_Space)])
        XCTAssertEqual(injected, [])
        XCTAssertEqual(router.activeRoutes, [:])
    }

    override func setUp() {
        super.setUp()
        resetState()
    }

    private func resetState() {
        router = KeyPressRouter()
        injected = []
        injectionSucceeds = true
        heldFlags = []
        configuration = .allEnabled
    }

    @discardableResult
    private func send(_ eventType: CGEventType, _ keyCode: Int, isAutorepeat: Bool = false) -> KeyPressDecision {
        router.route(
            eventType: eventType,
            keyCode: CGKeyCode(keyCode),
            eventFlags: heldFlags,
            trackedFlags: heldFlags,
            isAutorepeat: isAutorepeat,
            configuration: configuration,
            inject: record
        )
    }

    private func record(_ payload: InjectedKeyEventPayload) -> Bool {
        injected.append(payload)
        return injectionSucceeds
    }

    private func key(
        _ keyCode: Int,
        isKeyDown: Bool,
        isAutorepeat: Bool = false,
        flags: CGEventFlags = []
    ) -> InjectedKeyEventPayload {
        InjectedKeyEventPayload(
            targetKeyCode: CGKeyCode(keyCode),
            outputFlags: flags,
            isKeyDown: isKeyDown,
            isAutorepeat: isAutorepeat
        )
    }
}

final class InputSourceSwitchShortcutTests: XCTestCase {
    func testMatchesFnSpace() {
        XCTAssertTrue(InputSourceSwitchShortcut.matches(
            keyCode: CGKeyCode(kVK_Space),
            eventFlags: [.maskSecondaryFn],
            trackedFlags: []
        ))
    }

    func testCommandFnSpaceDoesNotMatch() {
        XCTAssertFalse(InputSourceSwitchShortcut.matches(
            keyCode: CGKeyCode(kVK_Space),
            eventFlags: [.maskCommand, .maskSecondaryFn],
            trackedFlags: []
        ))
    }

    func testSpaceWithoutFnDoesNotMatch() {
        XCTAssertFalse(InputSourceSwitchShortcut.matches(
            keyCode: CGKeyCode(kVK_Space),
            eventFlags: [],
            trackedFlags: []
        ))
    }

    func testUsesTrackedFnForSpaceShortcut() {
        XCTAssertTrue(InputSourceSwitchShortcut.matches(
            keyCode: CGKeyCode(kVK_Space),
            eventFlags: [],
            trackedFlags: [.maskSecondaryFn]
        ))
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
