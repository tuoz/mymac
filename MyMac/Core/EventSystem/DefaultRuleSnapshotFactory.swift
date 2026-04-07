struct DefaultRuleSnapshotFactory {
    private static let eventMarker: Int64 = 0x4D594D4143

    func makeSnapshot(isEnabled: Bool) -> RuleSnapshot {
        RuleSnapshot(
            isEnabled: isEnabled,
            mappings: [
                InputChord(keyCode: KeyCode.ansiH, requiredModifiers: .fn): .keyboard(
                    keyCode: KeyCode.leftArrow,
                    modifiers: [],
                    kind: .keyDown,
                    isAutorepeat: false
                ),
                InputChord(keyCode: KeyCode.ansiJ, requiredModifiers: .fn): .keyboard(
                    keyCode: KeyCode.downArrow,
                    modifiers: [],
                    kind: .keyDown,
                    isAutorepeat: false
                ),
                InputChord(keyCode: KeyCode.ansiK, requiredModifiers: .fn): .keyboard(
                    keyCode: KeyCode.upArrow,
                    modifiers: [],
                    kind: .keyDown,
                    isAutorepeat: false
                ),
                InputChord(keyCode: KeyCode.ansiL, requiredModifiers: .fn): .keyboard(
                    keyCode: KeyCode.rightArrow,
                    modifiers: [],
                    kind: .keyDown,
                    isAutorepeat: false
                ),
            ],
            eventMarker: Self.eventMarker
        )
    }
}
