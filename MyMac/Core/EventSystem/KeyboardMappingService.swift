import CoreGraphics
import Foundation

protocol KeyboardMappingService: Sendable {
    func start(with snapshot: RuleSnapshot) async
    func stop() async
    func reloadRules(_ snapshot: RuleSnapshot) async
    func currentStatus() async -> RuntimeStatus
}

actor CGEventTapKeyboardMappingService: KeyboardMappingService {
    private let diagnosticsService: DiagnosticsService
    private let controller: EventTapController

    init(diagnosticsService: DiagnosticsService) {
        self.diagnosticsService = diagnosticsService
        self.controller = EventTapController(diagnosticsService: diagnosticsService)
    }

    func start(with snapshot: RuleSnapshot) async {
        controller.updateSnapshot(snapshot)
        _ = controller.start()
    }

    func stop() async {
        _ = controller.stop()
    }

    func reloadRules(_ snapshot: RuleSnapshot) async {
        _ = controller.reloadRules(snapshot)
    }

    func currentStatus() async -> RuntimeStatus {
        controller.currentStatus()
    }
}

private final class EventTapController: NSObject {
    private let diagnosticsService: DiagnosticsService
    private let engine = KeyMappingEngine()
    private let executor = KeyboardActionExecutor()
    private let stateLock = NSLock()

    private var snapshot: RuleSnapshot?
    private var status: RuntimeStatus = .paused
    private var workerThread: Thread?
    private var startupSemaphore: DispatchSemaphore?
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var modifierTracker = ModifierStateTracker()

    init(diagnosticsService: DiagnosticsService) {
        self.diagnosticsService = diagnosticsService
    }

    func updateSnapshot(_ snapshot: RuleSnapshot) {
        stateLock.lock()
        self.snapshot = snapshot
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
        thread.name = "com.local.mymac.eventtap"
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

    func reloadRules(_ snapshot: RuleSnapshot) -> RuntimeStatus {
        updateSnapshot(snapshot)
        diagnosticsService.log("Reloaded keyboard mapping rules", category: .keyboardMapping)
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

        stateLock.lock()
        let currentSnapshot = snapshot
        stateLock.unlock()

        guard let currentSnapshot else {
            return Unmanaged.passUnretained(event)
        }

        if event.eventMarker == currentSnapshot.eventMarker {
            return Unmanaged.passUnretained(event)
        }

        let eventModifiers = ModifierSet(cgEventFlags: event.flags)

        if eventType == .flagsChanged {
            modifierTracker.update(with: eventModifiers)
            return Unmanaged.passUnretained(event)
        }

        guard let kind = KeyEventKind(cgEventType: eventType) else {
            return Unmanaged.passUnretained(event)
        }

        let effectiveModifiers = modifierTracker.effectiveModifiers(for: eventModifiers)
        let snapshotEvent = KeyEventSnapshot(
            kind: kind,
            keyCode: event.keyboardKeyCode,
            modifiers: eventModifiers,
            isAutorepeat: event.keyboardIsAutorepeat
        )

        guard let action = engine.action(
            for: snapshotEvent,
            effectiveModifiers: effectiveModifiers,
            snapshot: currentSnapshot
        ) else {
            return Unmanaged.passUnretained(event)
        }

        if executor.execute(action, eventMarker: currentSnapshot.eventMarker) {
            return nil
        }

        diagnosticsService.error("Failed to inject mapped key event", category: .keyboardMapping)
        return Unmanaged.passUnretained(event)
    }

    private static let eventTapCallback: CGEventTapCallBack = { _, type, event, userInfo in
        guard let userInfo else {
            return Unmanaged.passUnretained(event)
        }

        let controller = Unmanaged<EventTapController>.fromOpaque(userInfo).takeUnretainedValue()
        return controller.handle(eventType: type, event: event)
    }
}

private struct ModifierStateTracker {
    private var fnIsActive = false

    mutating func update(with modifiers: ModifierSet) {
        fnIsActive = modifiers.contains(.fn)
    }

    func effectiveModifiers(for eventModifiers: ModifierSet) -> ModifierSet {
        var modifiers = eventModifiers
        if fnIsActive {
            modifiers.insert(.fn)
        }
        return modifiers
    }

    mutating func reset() {
        fnIsActive = false
    }
}

private struct KeyboardActionExecutor {
    func execute(_ action: OutputAction, eventMarker: Int64) -> Bool {
        switch action {
        case .keyboard(let keyCode, let modifiers, let kind, let isAutorepeat):
            guard let event = CGEvent(
                keyboardEventSource: nil,
                virtualKey: CGKeyCode(keyCode),
                keyDown: kind == .keyDown
            ) else {
                return false
            }

            event.flags = modifiers.cgEventFlags
            event.setIntegerValueField(.keyboardEventAutorepeat, value: isAutorepeat ? 1 : 0)
            event.setIntegerValueField(.eventSourceUserData, value: eventMarker)
            event.post(tap: .cghidEventTap)
            return true
        }
    }
}
