struct KeyMappingEngine {
    func action(for event: KeyEventSnapshot, snapshot: RuleSnapshot) -> OutputAction? {
        guard snapshot.isEnabled else {
            return nil
        }

        guard event.kind == .keyDown || event.kind == .keyUp else {
            return nil
        }

        let chord = InputChord(keyCode: event.keyCode, requiredModifiers: .fn)
        guard event.modifiers.contains(.fn),
              let mappedAction = snapshot.mappings[chord] else {
            return nil
        }

        switch mappedAction {
        case .keyboard(let keyCode, _, _, _):
            return .keyboard(
                keyCode: keyCode,
                modifiers: event.modifiers.removing(.fn),
                kind: event.kind,
                isAutorepeat: event.isAutorepeat
            )
        }
    }
}
