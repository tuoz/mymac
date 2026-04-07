enum OutputAction: Sendable, Equatable {
    case keyboard(keyCode: UInt16, modifiers: ModifierSet, kind: KeyEventKind, isAutorepeat: Bool)
}
