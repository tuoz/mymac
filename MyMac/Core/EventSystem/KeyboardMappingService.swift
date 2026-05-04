import Carbon.HIToolbox
import CoreGraphics
import Foundation

protocol KeyboardMappingService: Sendable {
    func updateConfiguration(_ configuration: KeyboardMappingConfiguration) async
    func start() async
    func stop() async
    func currentStatus() async -> RuntimeStatus
}

struct KeyboardMappingConfiguration: Equatable, Sendable {
    var isArrowKeyMappingEnabled: Bool
    var isInputSourceSwitchingEnabled: Bool

    static let allEnabled = Self(
        isArrowKeyMappingEnabled: true,
        isInputSourceSwitchingEnabled: true
    )

    var shouldListenForKeyboardEvents: Bool {
        isArrowKeyMappingEnabled || isInputSourceSwitchingEnabled
    }
}

actor CGEventTapKeyboardMappingService: KeyboardMappingService {
    private let controller: EventTapController

    init(
        inputSourceSwitchService: InputSourceSwitchService,
        diagnosticsService: DiagnosticsService
    ) {
        self.controller = EventTapController(
            inputSourceSwitchService: inputSourceSwitchService,
            diagnosticsService: diagnosticsService
        )
    }

    func updateConfiguration(_ configuration: KeyboardMappingConfiguration) async {
        controller.updateConfiguration(configuration)
    }

    func start() async {
        _ = controller.start()
    }

    func stop() async {
        _ = controller.stop()
    }

    func currentStatus() async -> RuntimeStatus {
        controller.currentStatus()
    }
}

private final class EventTapController: NSObject {
    private let inputSourceSwitchTrigger: InputSourceSwitchTrigger
    private let diagnosticsService: DiagnosticsService
    private let translator = KeyboardEventTranslator()
    private let executor = KeyboardActionExecutor()
    private let stateLock = NSLock()

    private var configuration: KeyboardMappingConfiguration = .allEnabled
    private var status: RuntimeStatus = .paused
    private var workerThread: Thread?
    private var startupSemaphore: DispatchSemaphore?
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var modifierTracker = ModifierStateTracker()

    init(
        inputSourceSwitchService: InputSourceSwitchService,
        diagnosticsService: DiagnosticsService
    ) {
        self.inputSourceSwitchTrigger = InputSourceSwitchTrigger(
            inputSourceSwitchService: inputSourceSwitchService,
            diagnosticsService: diagnosticsService
        )
        self.diagnosticsService = diagnosticsService
    }

    func updateConfiguration(_ configuration: KeyboardMappingConfiguration) {
        stateLock.lock()
        self.configuration = configuration
        stateLock.unlock()
    }

    func start() -> RuntimeStatus {
        stateLock.lock()
        if workerThread != nil {
            let current = status
            stateLock.unlock()
            return current
        }

        status = .starting
        modifierTracker.reset()

        let semaphore = DispatchSemaphore(value: 0)
        startupSemaphore = semaphore

        let thread = Thread(target: self, selector: #selector(runEventLoop), object: nil)
        thread.name = "com.tuoz.mymac.eventtap"
        thread.qualityOfService = .userInitiated
        workerThread = thread
        stateLock.unlock()

        thread.start()

        if semaphore.wait(timeout: .now() + 2) == .timedOut {
            diagnosticsService.error("Timed out starting event tap", category: .keyboardMapping)
            stateLock.lock()
            status = .failed("Timed out starting event tap")
            workerThread = nil
            startupSemaphore = nil
            stateLock.unlock()
        }

        return currentStatus()
    }

    func stop() -> RuntimeStatus {
        stateLock.lock()
        guard let thread = workerThread else {
            status = .paused
            stateLock.unlock()
            return .paused
        }
        stateLock.unlock()

        perform(#selector(stopEventLoop), on: thread, with: nil, waitUntilDone: true)
        return currentStatus()
    }

    func currentStatus() -> RuntimeStatus {
        stateLock.lock()
        let current = status
        stateLock.unlock()
        return current
    }

    @objc
    private func runEventLoop() {
        autoreleasepool {
            let eventMask =
                (CGEventMask(1) << CGEventType.keyDown.rawValue) |
                (CGEventMask(1) << CGEventType.keyUp.rawValue) |
                (CGEventMask(1) << CGEventType.flagsChanged.rawValue)

            guard let tap = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: eventMask,
                callback: Self.eventTapCallback,
                userInfo: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
            ) else {
                diagnosticsService.error("Failed to create event tap", category: .keyboardMapping)
                stateLock.lock()
                status = .failed("Failed to create event tap")
                workerThread = nil
                let semaphore = startupSemaphore
                startupSemaphore = nil
                stateLock.unlock()
                semaphore?.signal()
                return
            }

            let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)

            stateLock.lock()
            eventTap = tap
            runLoopSource = source
            status = .running
            let semaphore = startupSemaphore
            startupSemaphore = nil
            stateLock.unlock()

            diagnosticsService.log("Event tap started", category: .keyboardMapping)
            semaphore?.signal()
            RunLoop.current.run()
        }
    }

    @objc
    private func stopEventLoop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        }

        eventTap = nil
        runLoopSource = nil
        modifierTracker.reset()

        stateLock.lock()
        workerThread = nil
        status = .paused
        stateLock.unlock()

        diagnosticsService.log("Event tap stopped", category: .keyboardMapping)
        CFRunLoopStop(CFRunLoopGetCurrent())
    }

    private func handleTapDisabled(_ type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        switch type {
        case .tapDisabledByTimeout:
            diagnosticsService.log("Event tap disabled by timeout; attempting re-enable", category: .keyboardMapping)
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
                stateLock.lock()
                status = .running
                stateLock.unlock()
            } else {
                stateLock.lock()
                status = .tapDisabled
                stateLock.unlock()
            }
        case .tapDisabledByUserInput:
            diagnosticsService.error("Event tap disabled by user input", category: .keyboardMapping)
            stateLock.lock()
            status = .tapDisabled
            stateLock.unlock()
        default:
            break
        }

        return Unmanaged.passUnretained(event)
    }

    private func handle(eventType: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if eventType == .tapDisabledByTimeout || eventType == .tapDisabledByUserInput {
            return handleTapDisabled(eventType, event: event)
        }

        if event.eventMarker == KeyboardEventTranslator.eventMarker {
            return Unmanaged.passUnretained(event)
        }

        if eventType == .flagsChanged {
            modifierTracker.update(with: event.flags)
            return Unmanaged.passUnretained(event)
        }

        let currentConfiguration = currentConfiguration()

        if currentConfiguration.isInputSourceSwitchingEnabled,
           let inputSourceSwitchAction = InputSourceSwitchShortcut.action(
               eventType: eventType,
               keyCode: event.keyboardKeyCode,
               eventFlags: event.flags,
               trackedFlags: modifierTracker.activeFlags,
               isAutorepeat: event.keyboardIsAutorepeat
           ) {
            if inputSourceSwitchAction.shouldTriggerSwitch {
                inputSourceSwitchTrigger.trigger()
            }

            return nil
        }

        guard currentConfiguration.isArrowKeyMappingEnabled,
              let payload = translator.translate(
                  eventType: eventType,
                  keyCode: event.keyboardKeyCode,
                  eventFlags: event.flags,
                  trackedFlags: modifierTracker.activeFlags,
                  isAutorepeat: event.keyboardIsAutorepeat
              ) else {
            return Unmanaged.passUnretained(event)
        }

        if executor.execute(payload, eventMarker: KeyboardEventTranslator.eventMarker) {
            return nil
        }

        diagnosticsService.error("Failed to inject mapped key event", category: .keyboardMapping)
        return Unmanaged.passUnretained(event)
    }

    private func currentConfiguration() -> KeyboardMappingConfiguration {
        stateLock.lock()
        let current = configuration
        stateLock.unlock()
        return current
    }

    private static let eventTapCallback: CGEventTapCallBack = { _, type, event, userInfo in
        guard let userInfo else {
            return Unmanaged.passUnretained(event)
        }

        let controller = Unmanaged<EventTapController>.fromOpaque(userInfo).takeUnretainedValue()
        return controller.handle(eventType: type, event: event)
    }
}

enum InputSourceSwitchShortcutAction: Equatable {
    case consumeOnly
    case consumeAndSwitch

    var shouldTriggerSwitch: Bool {
        self == .consumeAndSwitch
    }
}

struct InputSourceSwitchShortcut {
    static func action(
        eventType: CGEventType,
        keyCode: CGKeyCode,
        eventFlags: CGEventFlags,
        trackedFlags: CGEventFlags,
        isAutorepeat: Bool
    ) -> InputSourceSwitchShortcutAction? {
        guard eventType == .keyDown || eventType == .keyUp,
              keyCode == CGKeyCode(kVK_Space) else {
            return nil
        }

        let effectiveFlags = KeyboardEventTranslator.effectiveFlags(
            eventFlags: eventFlags,
            trackedFlags: trackedFlags
        )

        guard effectiveFlags == [.maskSecondaryFn] else {
            return nil
        }

        if eventType == .keyDown, !isAutorepeat {
            return .consumeAndSwitch
        }

        return .consumeOnly
    }
}

private final class InputSourceSwitchTrigger: @unchecked Sendable {
    private let inputSourceSwitchService: InputSourceSwitchService
    private let diagnosticsService: DiagnosticsService
    private let stateLock = NSLock()
    private var isSwitching = false

    init(
        inputSourceSwitchService: InputSourceSwitchService,
        diagnosticsService: DiagnosticsService
    ) {
        self.inputSourceSwitchService = inputSourceSwitchService
        self.diagnosticsService = diagnosticsService
    }

    func trigger() {
        stateLock.lock()
        guard !isSwitching else {
            stateLock.unlock()
            return
        }
        isSwitching = true
        stateLock.unlock()

        DispatchQueue.main.async { [inputSourceSwitchService, diagnosticsService, weak self] in
            guard let self else {
                return
            }

            switch inputSourceSwitchService.switchRomanNonRoman() {
            case .success:
                scheduleSecondSelect()
            case .unavailable(let reason):
                diagnosticsService.error(
                    "Input source switch unavailable: \(reason)",
                    category: .keyboardMapping
                )
                finish()
            case .selectionFailed(let status):
                diagnosticsService.error(
                    "Input source switch failed: status=\(status)",
                    category: .keyboardMapping
                )
                finish()
            }
        }
    }

    private func scheduleSecondSelect(attempt: Int = 0) {
        let delay: TimeInterval = 0.018

        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [inputSourceSwitchService, diagnosticsService, weak self] in
            guard let self else { return }

            switch inputSourceSwitchService.refreshCurrentInputSource() {
            case .success:
                break
            case .unavailable(let reason):
                diagnosticsService.error(
                    "Input source re-select unavailable: \(reason)",
                    category: .keyboardMapping
                )
                finish()
                return
            case .selectionFailed(let status):
                diagnosticsService.error(
                    "Input source re-select failed: status=\(status)",
                    category: .keyboardMapping
                )
                finish()
                return
            }

            if attempt < 1 {
                scheduleSecondSelect(attempt: attempt + 1)
            } else {
                finish()
            }
        }
    }

    private func finish() {
        stateLock.lock()
        isSwitching = false
        stateLock.unlock()
    }
}

struct ModifierStateTracker {
    private(set) var activeFlags: CGEventFlags = []

    mutating func update(with flags: CGEventFlags) {
        activeFlags = KeyboardEventTranslator.sanitizeRelevantFlags(flags)
    }

    mutating func reset() {
        activeFlags = []
    }
}

struct InjectedKeyEventPayload: Equatable {
    var targetKeyCode: CGKeyCode
    var outputFlags: CGEventFlags
    var isKeyDown: Bool
    var isAutorepeat: Bool
}

struct KeyboardEventTranslator {
    static let eventMarker: Int64 = 0x4D594D4143

    func translate(
        eventType: CGEventType,
        keyCode: CGKeyCode,
        eventFlags: CGEventFlags,
        trackedFlags: CGEventFlags,
        isAutorepeat: Bool
    ) -> InjectedKeyEventPayload? {
        guard eventType == .keyDown || eventType == .keyUp else {
            return nil
        }

        // Some key events arrive before their modifier flags are fully reflected
        // on the event itself, so matching merges the event flags with tracked state.
        let effectiveFlags = Self.effectiveFlags(eventFlags: eventFlags, trackedFlags: trackedFlags)
        guard effectiveFlags.contains(.maskSecondaryFn),
              let targetKeyCode = Self.mappedArrowKeyCode(for: keyCode) else {
            return nil
        }

        let outputFlags = Self.outputFlags(
            from: eventFlags,
            trackedFlags: trackedFlags
        )

        return InjectedKeyEventPayload(
            targetKeyCode: targetKeyCode,
            outputFlags: outputFlags,
            isKeyDown: eventType == .keyDown,
            isAutorepeat: isAutorepeat
        )
    }

    static func sanitizeRelevantFlags(_ flags: CGEventFlags) -> CGEventFlags {
        var sanitized: CGEventFlags = []

        if flags.contains(.maskCommand) {
            sanitized.insert(.maskCommand)
        }
        if flags.contains(.maskShift) {
            sanitized.insert(.maskShift)
        }
        if flags.contains(.maskAlternate) {
            sanitized.insert(.maskAlternate)
        }
        if flags.contains(.maskControl) {
            sanitized.insert(.maskControl)
        }
        if flags.contains(.maskSecondaryFn) {
            sanitized.insert(.maskSecondaryFn)
        }

        return sanitized
    }

    static func effectiveFlags(eventFlags: CGEventFlags, trackedFlags: CGEventFlags) -> CGEventFlags {
        sanitizeRelevantFlags(eventFlags).union(sanitizeRelevantFlags(trackedFlags))
    }

    static func outputFlags(from eventFlags: CGEventFlags, trackedFlags: CGEventFlags) -> CGEventFlags {
        // Preserve the original event's raw bits whenever possible. Rebuilding flags
        // from only the abstract modifier mask breaks shortcuts like control+arrow.
        var outputFlags = eventFlags.removing(.maskSecondaryFn)
        let eventRelevantFlags = sanitizeRelevantFlags(eventFlags).removing(.maskSecondaryFn)
        let trackedRelevantFlags = sanitizeRelevantFlags(trackedFlags).removing(.maskSecondaryFn)
        let missingRelevantFlags = trackedRelevantFlags.removing(eventRelevantFlags)
        outputFlags.insert(missingRelevantFlags)
        return outputFlags
    }

    private static func mappedArrowKeyCode(for keyCode: CGKeyCode) -> CGKeyCode? {
        switch Int(keyCode) {
        case kVK_ANSI_H:
            return CGKeyCode(kVK_LeftArrow)
        case kVK_ANSI_J:
            return CGKeyCode(kVK_DownArrow)
        case kVK_ANSI_K:
            return CGKeyCode(kVK_UpArrow)
        case kVK_ANSI_L:
            return CGKeyCode(kVK_RightArrow)
        default:
            return nil
        }
    }
}

struct KeyboardActionExecutor {
    func execute(_ payload: InjectedKeyEventPayload, eventMarker: Int64) -> Bool {
        guard let event = CGEvent(
            keyboardEventSource: nil,
            virtualKey: payload.targetKeyCode,
            keyDown: payload.isKeyDown
        ) else {
            return false
        }

        event.flags.insert(payload.outputFlags)
        event.setIntegerValueField(.keyboardEventAutorepeat, value: payload.isAutorepeat ? 1 : 0)
        event.setIntegerValueField(.eventSourceUserData, value: eventMarker)
        event.post(tap: .cgSessionEventTap)
        return true
    }
}

private extension CGEventFlags {
    func removing(_ flags: CGEventFlags) -> CGEventFlags {
        CGEventFlags(rawValue: rawValue & ~flags.rawValue)
    }
}

extension CGEvent {
    var keyboardKeyCode: CGKeyCode {
        CGKeyCode(getIntegerValueField(.keyboardEventKeycode))
    }

    var keyboardIsAutorepeat: Bool {
        getIntegerValueField(.keyboardEventAutorepeat) != 0
    }

    var eventMarker: Int64 {
        getIntegerValueField(.eventSourceUserData)
    }
}
