struct ModifierSet: OptionSet, Hashable, Sendable {
    let rawValue: Int

    static let command = ModifierSet(rawValue: 1 << 0)
    static let shift = ModifierSet(rawValue: 1 << 1)
    static let option = ModifierSet(rawValue: 1 << 2)
    static let control = ModifierSet(rawValue: 1 << 3)
    static let fn = ModifierSet(rawValue: 1 << 4)

    func removing(_ modifiers: ModifierSet) -> ModifierSet {
        ModifierSet(rawValue: rawValue & ~modifiers.rawValue)
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
