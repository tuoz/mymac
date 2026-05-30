import AppKit
import Carbon.HIToolbox
import CoreGraphics
import Foundation

private let systemDefinedEventType = CGEventType(rawValue: 14)!

private let keyNames: [Int64: String] = [
    Int64(kVK_ANSI_A): "A",
    Int64(kVK_ANSI_B): "B",
    Int64(kVK_ANSI_C): "C",
    Int64(kVK_ANSI_D): "D",
    Int64(kVK_ANSI_E): "E",
    Int64(kVK_ANSI_F): "F",
    Int64(kVK_ANSI_G): "G",
    Int64(kVK_ANSI_H): "H",
    Int64(kVK_ANSI_I): "I",
    Int64(kVK_ANSI_J): "J",
    Int64(kVK_ANSI_K): "K",
    Int64(kVK_ANSI_L): "L",
    Int64(kVK_ANSI_M): "M",
    Int64(kVK_ANSI_N): "N",
    Int64(kVK_ANSI_O): "O",
    Int64(kVK_ANSI_P): "P",
    Int64(kVK_ANSI_Q): "Q",
    Int64(kVK_ANSI_R): "R",
    Int64(kVK_ANSI_S): "S",
    Int64(kVK_ANSI_T): "T",
    Int64(kVK_ANSI_U): "U",
    Int64(kVK_ANSI_V): "V",
    Int64(kVK_ANSI_W): "W",
    Int64(kVK_ANSI_X): "X",
    Int64(kVK_ANSI_Y): "Y",
    Int64(kVK_ANSI_Z): "Z",
    Int64(kVK_ANSI_0): "0",
    Int64(kVK_ANSI_1): "1",
    Int64(kVK_ANSI_2): "2",
    Int64(kVK_ANSI_3): "3",
    Int64(kVK_ANSI_4): "4",
    Int64(kVK_ANSI_5): "5",
    Int64(kVK_ANSI_6): "6",
    Int64(kVK_ANSI_7): "7",
    Int64(kVK_ANSI_8): "8",
    Int64(kVK_ANSI_9): "9",
    Int64(kVK_Return): "Return",
    Int64(kVK_Tab): "Tab",
    Int64(kVK_Space): "Space",
    Int64(kVK_Delete): "Delete",
    Int64(kVK_Escape): "Escape",
    Int64(kVK_Command): "LeftCommand",
    Int64(kVK_Shift): "LeftShift",
    Int64(kVK_CapsLock): "CapsLock",
    Int64(kVK_Option): "LeftOption",
    Int64(kVK_Control): "LeftControl",
    Int64(kVK_RightCommand): "RightCommand",
    Int64(kVK_RightShift): "RightShift",
    Int64(kVK_RightOption): "RightOption",
    Int64(kVK_RightControl): "RightControl",
    Int64(kVK_Function): "Fn",
    Int64(kVK_F1): "F1",
    Int64(kVK_F2): "F2",
    Int64(kVK_F3): "F3",
    Int64(kVK_F4): "F4",
    Int64(kVK_F5): "F5",
    Int64(kVK_F6): "F6",
    Int64(kVK_F7): "F7",
    Int64(kVK_F8): "F8",
    Int64(kVK_F9): "F9",
    Int64(kVK_F10): "F10",
    Int64(kVK_F11): "F11",
    Int64(kVK_F12): "F12",
    Int64(kVK_F13): "F13",
    Int64(kVK_F14): "F14",
    Int64(kVK_F15): "F15",
    Int64(kVK_F16): "F16",
    Int64(kVK_F17): "F17",
    Int64(kVK_F18): "F18",
    Int64(kVK_F19): "F19",
    Int64(kVK_F20): "F20",
    Int64(kVK_Home): "Home",
    Int64(kVK_End): "End",
    Int64(kVK_PageUp): "PageUp",
    Int64(kVK_PageDown): "PageDown",
    Int64(kVK_LeftArrow): "LeftArrow",
    Int64(kVK_RightArrow): "RightArrow",
    Int64(kVK_DownArrow): "DownArrow",
    Int64(kVK_UpArrow): "UpArrow"
]

private let nxKeyTypeNames: [Int: String] = [
    0: "soundUp",
    1: "soundDown",
    2: "brightnessUp",
    3: "brightnessDown",
    4: "capsLock",
    6: "help",
    7: "power",
    8: "mute",
    10: "upArrowKeypad",
    11: "downArrowKeypad",
    12: "numLock",
    14: "contrastUp",
    15: "contrastDown",
    16: "launchPanel",
    17: "eject",
    18: "vidMirror",
    19: "play",
    20: "next",
    21: "previous",
    22: "fast",
    23: "rewind",
    24: "illuminationUp",
    25: "illuminationDown",
    26: "illuminationToggle"
]

private final class KeyboardEventLogger {
    private let dateFormatter: DateFormatter

    init() {
        dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "HH:mm:ss.SSS"
    }

    func start() -> Never {
        printHeader()

        let mask =
            (CGEventMask(1) << CGEventType.keyDown.rawValue) |
            (CGEventMask(1) << CGEventType.keyUp.rawValue) |
            (CGEventMask(1) << CGEventType.flagsChanged.rawValue) |
            (CGEventMask(1) << systemDefinedEventType.rawValue)

        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: Self.callback,
            userInfo: refcon
        ) else {
            fputs(
                """
                Failed to create CGEventTap.

                Open System Settings > Privacy & Security > Accessibility, then enable the terminal app running this tool.
                After granting permission, restart this command.

                """,
                stderr
            )
            exit(1)
        }

        let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        print("Listening. Press Ctrl+C to quit.\n")
        CFRunLoopRun()
        fatalError("CFRunLoopRun returned unexpectedly")
    }

    private func printHeader() {
        print(
            """
            KeyboardEventLogger

            Test order:
            1. Press F1-F12 directly.
            2. Press the keyboard's own Fn + F1-F12.
            3. Press the key mapped to macOS Fn + F1-F12.
            4. Optional: compare with Apple/Magic Keyboard Fn + F1-F12.

            Fields:
            - keyDown/keyUp/flagsChanged show keyCode, key name, flags, modifiers, autorepeat.
            - systemDefined shows subtype, data1, NX key type, state, repeat, and known system key name.

            """
        )
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        switch type {
        case .keyDown, .keyUp, .flagsChanged:
            printKeyboardEvent(type: type, event: event)
        case systemDefinedEventType:
            printSystemDefinedEvent(event)
        default:
            break
        }

        return Unmanaged.passUnretained(event)
    }

    private func printKeyboardEvent(type: CGEventType, event: CGEvent) {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let autorepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
        let flags = event.flags
        let name = keyNames[keyCode] ?? "unknown"

        print(
            "\(timestamp()) \(eventTypeName(type)) " +
            "keyCode=\(keyCode) name=\(name) " +
            "flags=\(hex(flags.rawValue)) modifiers=[\(modifierNames(flags).joined(separator: ","))] " +
            "autorepeat=\(autorepeat)"
        )
        fflush(stdout)
    }

    private func printSystemDefinedEvent(_ event: CGEvent) {
        guard let nsEvent = NSEvent(cgEvent: event) else {
            print("\(timestamp()) systemDefined failedToCreateNSEvent")
            fflush(stdout)
            return
        }

        let data1 = nsEvent.data1
        let nxKeyType = (data1 >> 16) & 0xFFFF
        let keyFlags = data1 & 0xFFFF
        let keyState = (keyFlags >> 8) & 0xFF
        let keyRepeat = keyFlags & 0x1
        let keyName = nxKeyTypeNames[nxKeyType] ?? "unknown"

        print(
            "\(timestamp()) systemDefined " +
            "subtype=\(nsEvent.subtype.rawValue) data1=\(data1) data1Hex=\(hex(UInt64(UInt32(bitPattern: Int32(data1))))) " +
            "nxKeyType=\(nxKeyType) nxKeyName=\(keyName) " +
            "state=\(systemDefinedKeyStateName(keyState)) repeat=\(keyRepeat != 0) " +
            "flags=\(hex(event.flags.rawValue)) modifiers=[\(modifierNames(event.flags).joined(separator: ","))]"
        )
        fflush(stdout)
    }

    private func timestamp() -> String {
        dateFormatter.string(from: Date())
    }

    private static let callback: CGEventTapCallBack = { _, type, event, userInfo in
        guard let userInfo else {
            return Unmanaged.passUnretained(event)
        }

        let logger = Unmanaged<KeyboardEventLogger>.fromOpaque(userInfo).takeUnretainedValue()
        return logger.handle(type: type, event: event)
    }
}

private func eventTypeName(_ type: CGEventType) -> String {
    switch type {
    case .keyDown:
        return "keyDown"
    case .keyUp:
        return "keyUp"
    case .flagsChanged:
        return "flagsChanged"
    case systemDefinedEventType:
        return "systemDefined"
    default:
        return "eventType(\(type.rawValue))"
    }
}

private func modifierNames(_ flags: CGEventFlags) -> [String] {
    var names: [String] = []

    if flags.contains(.maskCommand) {
        names.append("cmd")
    }
    if flags.contains(.maskShift) {
        names.append("shift")
    }
    if flags.contains(.maskAlternate) {
        names.append("option")
    }
    if flags.contains(.maskControl) {
        names.append("control")
    }
    if flags.contains(.maskSecondaryFn) {
        names.append("fn")
    }
    if flags.contains(.maskAlphaShift) {
        names.append("capsLock")
    }

    return names
}

private func systemDefinedKeyStateName(_ keyState: Int) -> String {
    switch keyState {
    case 0x0A:
        return "down"
    case 0x0B:
        return "up"
    default:
        return "unknown(\(keyState))"
    }
}

private func hex(_ value: UInt64) -> String {
    "0x" + String(value, radix: 16, uppercase: true)
}

KeyboardEventLogger().start()
