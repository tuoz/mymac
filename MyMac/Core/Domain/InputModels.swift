import CoreGraphics

struct ModifierSet: OptionSet, Hashable, Sendable {
    let rawValue: Int

    init(rawValue: Int) {
        self.rawValue = rawValue
    }

    static let command = ModifierSet(rawValue: 1 << 0)
    static let shift = ModifierSet(rawValue: 1 << 1)
    static let option = ModifierSet(rawValue: 1 << 2)
    static let control = ModifierSet(rawValue: 1 << 3)
    static let fn = ModifierSet(rawValue: 1 << 4)

    func removing(_ modifiers: ModifierSet) -> ModifierSet {
        ModifierSet(rawValue: rawValue & ~modifiers.rawValue)
    }

    init(cgEventFlags: CGEventFlags) {
        var modifiers: ModifierSet = []

        if cgEventFlags.contains(.maskCommand) {
            modifiers.insert(.command)
        }
        if cgEventFlags.contains(.maskShift) {
            modifiers.insert(.shift)
        }
        if cgEventFlags.contains(.maskAlternate) {
            modifiers.insert(.option)
        }
        if cgEventFlags.contains(.maskControl) {
            modifiers.insert(.control)
        }
        if cgEventFlags.contains(.maskSecondaryFn) {
            modifiers.insert(.fn)
        }

        self = modifiers
    }

    var cgEventFlags: CGEventFlags {
        var flags: CGEventFlags = []

        if contains(.command) {
            flags.insert(.maskCommand)
        }
        if contains(.shift) {
            flags.insert(.maskShift)
        }
        if contains(.option) {
            flags.insert(.maskAlternate)
        }
        if contains(.control) {
            flags.insert(.maskControl)
        }

        return flags
    }
}

enum KeyEventKind: Sendable, Equatable {
    case keyDown
    case keyUp
    case flagsChanged
}

struct KeyEventSnapshot: Sendable, Equatable {
    var kind: KeyEventKind
    var keyCode: UInt16
    var modifiers: ModifierSet
    var isAutorepeat: Bool
}

struct InputChord: Hashable, Sendable {
    var keyCode: UInt16
    var requiredModifiers: ModifierSet
}

struct RuleSnapshot: Sendable, Equatable {
    var isEnabled: Bool
    var mappings: [InputChord: OutputAction]
    var eventMarker: Int64
}

enum KeyCode {
    static let ansiH: UInt16 = 4
    static let ansiJ: UInt16 = 38
    static let ansiK: UInt16 = 40
    static let ansiL: UInt16 = 37

    static let leftArrow: UInt16 = 123
    static let rightArrow: UInt16 = 124
    static let downArrow: UInt16 = 125
    static let upArrow: UInt16 = 126
}

extension KeyEventKind {
    init?(cgEventType: CGEventType) {
        switch cgEventType {
        case .keyDown:
            self = .keyDown
        case .keyUp:
            self = .keyUp
        case .flagsChanged:
            self = .flagsChanged
        default:
            return nil
        }
    }
}

extension CGEvent {
    var keyboardKeyCode: UInt16 {
        UInt16(getIntegerValueField(.keyboardEventKeycode))
    }

    var keyboardIsAutorepeat: Bool {
        getIntegerValueField(.keyboardEventAutorepeat) != 0
    }

    var eventMarker: Int64 {
        getIntegerValueField(.eventSourceUserData)
    }
}
