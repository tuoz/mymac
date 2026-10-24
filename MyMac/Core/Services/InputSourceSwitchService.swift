import Carbon.HIToolbox
import Darwin
import Foundation

enum InputSourceSwitchResult: Equatable, Sendable {
    case success
    case unavailable(String)
    case selectionFailed(OSStatus)
}

protocol InputSourceSwitchService: Sendable {
    func switchRomanNonRoman() -> InputSourceSwitchResult
}

struct InputSourceDescriptor: Equatable, Sendable {
    let id: String
    let isASCIICapable: Bool
    fileprivate let reference: InputSourceReference?

    init(id: String, isASCIICapable: Bool) {
        self.id = id
        self.isASCIICapable = isASCIICapable
        self.reference = nil
    }

    fileprivate init(id: String, isASCIICapable: Bool, reference: InputSourceReference) {
        self.id = id
        self.isASCIICapable = isASCIICapable
        self.reference = reference
    }

    static func == (lhs: InputSourceDescriptor, rhs: InputSourceDescriptor) -> Bool {
        lhs.id == rhs.id && lhs.isASCIICapable == rhs.isASCIICapable
    }
}

protocol InputSourceSwitchingClient: Sendable {
    func currentInputSource() -> InputSourceDescriptor?
    func currentNonRomanInputSourceForRomanSwitch() -> InputSourceDescriptor?
    func currentASCIICapableInputSource() -> InputSourceDescriptor?
    func enabledInputSources() -> [InputSourceDescriptor]
    func selectInputSource(_ inputSource: InputSourceDescriptor) -> OSStatus
}

struct DefaultInputSourceSwitchService: InputSourceSwitchService {
    private let client: InputSourceSwitchingClient
    private let diagnosticsService: DiagnosticsService

    init(
        client: InputSourceSwitchingClient? = nil,
        diagnosticsService: DiagnosticsService
    ) {
        self.client = client ?? CarbonInputSourceSwitchingClient(diagnosticsService: diagnosticsService)
        self.diagnosticsService = diagnosticsService
    }

    func switchRomanNonRoman() -> InputSourceSwitchResult {
        let target = preferredTarget() ?? fallbackTarget()

        guard let target else {
            diagnosticsService.error("No input source switch target available", category: .keyboardMapping)
            return .unavailable("No input source switch target available")
        }

        let status = client.selectInputSource(target)
        guard status == noErr else {
            diagnosticsService.error(
                "Failed to select input source \(target.id): status=\(status)",
                category: .keyboardMapping
            )
            return .selectionFailed(status)
        }

        return .success
    }

    private func preferredTarget() -> InputSourceDescriptor? {
        guard
            let current = client.currentInputSource(),
            let nonRomanTarget = client.currentNonRomanInputSourceForRomanSwitch(),
            let asciiTarget = client.currentASCIICapableInputSource()
        else {
            return nil
        }

        if current.id == nonRomanTarget.id {
            return asciiTarget
        }

        return nonRomanTarget
    }

    private func fallbackTarget() -> InputSourceDescriptor? {
        guard let current = client.currentInputSource() else {
            return nil
        }

        if current.isASCIICapable {
            return client.enabledInputSources().first { !$0.isASCIICapable }
        }

        return client.currentASCIICapableInputSource()
    }
}

private final class InputSourceReference: @unchecked Sendable {
    let rawValue: TISInputSource

    init(_ rawValue: TISInputSource) {
        self.rawValue = rawValue
    }
}

struct CarbonInputSourceSwitchingClient: InputSourceSwitchingClient {
    private typealias CopyCurrentNonRomanInputSource = @convention(c) () -> Unmanaged<TISInputSource>?

    private static let hitoolboxPath =
        "/System/Library/Frameworks/Carbon.framework/Versions/A/Frameworks/HIToolbox.framework/Versions/A/HIToolbox"

    private let focusedAppSelector = FocusedAppInputSourceSelector()
    private let diagnosticsService: DiagnosticsService

    init(diagnosticsService: DiagnosticsService) {
        self.diagnosticsService = diagnosticsService
    }

    func currentInputSource() -> InputSourceDescriptor? {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else {
            return nil
        }

        return descriptor(for: source)
    }

    func currentNonRomanInputSourceForRomanSwitch() -> InputSourceDescriptor? {
        guard
            let handle = dlopen(Self.hitoolboxPath, RTLD_NOW),
            let symbol = dlsym(handle, "TISCopyCurrentNonRomanInputSourceForRomanSwitch")
        else {
            return nil
        }
        defer { dlclose(handle) }

        let function = unsafeBitCast(symbol, to: CopyCurrentNonRomanInputSource.self)
        guard let source = function()?.takeRetainedValue() else {
            return nil
        }

        return descriptor(for: source)
    }

    func currentASCIICapableInputSource() -> InputSourceDescriptor? {
        guard let source = TISCopyCurrentASCIICapableKeyboardInputSource()?.takeRetainedValue() else {
            return nil
        }

        return descriptor(for: source)
    }

    func enabledInputSources() -> [InputSourceDescriptor] {
        let properties: [String: Any] = [
            kTISPropertyInputSourceIsEnabled as String: true
        ]

        guard let sources = TISCreateInputSourceList(properties as CFDictionary, false)?.takeRetainedValue() as? [TISInputSource] else {
            return []
        }

        return sources.compactMap { descriptor(for: $0) }
    }

    func selectInputSource(_ inputSource: InputSourceDescriptor) -> OSStatus {
        guard let reference = inputSource.reference else {
            return OSStatus(paramErr)
        }

        switch focusedAppSelector.select(reference.rawValue) {
        case .selected:
            return noErr
        case .unavailable(let reason):
            diagnosticsService.log(
                "Focused app selection of \(inputSource.id) unavailable, falling back to TIS: \(reason)",
                category: .keyboardMapping
            )
            return TISSelectInputSource(reference.rawValue)
        }
    }

    private func descriptor(for source: TISInputSource) -> InputSourceDescriptor? {
        guard let id = inputSourceProperty(source, kTISPropertyInputSourceID) as? String else {
            return nil
        }

        let isASCIICapable = inputSourceProperty(
            source,
            kTISPropertyInputSourceIsASCIICapable
        ) as? Bool ?? false

        return InputSourceDescriptor(
            id: id,
            isASCIICapable: isASCIICapable,
            reference: InputSourceReference(source)
        )
    }

    private func inputSourceProperty(_ source: TISInputSource, _ key: CFString) -> Any? {
        guard let pointer = TISGetInputSourceProperty(source, key) else {
            return nil
        }

        return Unmanaged<AnyObject>.fromOpaque(pointer).takeUnretainedValue()
    }
}

enum FocusedAppSelectionResult: Equatable, Sendable {
    case selected
    case unavailable(String)
}

// Selects an input source the way the Input menu does: the process with keyboard
// focus is asked to switch through its Text Services Manager port (message ID 7).
// TISSelectInputSource from a background process commits the source system-wide
// before the focused app is told, and CJK input methods are then deactivated
// right after activation, leaving the menu bar switched while typing stays latin.
// The symbols are private and resolved at run time; callers fall back to TIS.
struct FocusedAppInputSourceSelector: Sendable {
    private typealias KeyFocusProcess = @convention(c) (
        UnsafeMutablePointer<ProcessSerialNumber>,
        UnsafeMutablePointer<DarwinBoolean>
    ) -> Int32
    private typealias ProcessPID = @convention(c) (
        UnsafePointer<ProcessSerialNumber>,
        UnsafeMutablePointer<pid_t>
    ) -> OSStatus
    private typealias PerProcessRemotePort = @convention(c) (
        CFAllocator?,
        CFString,
        pid_t
    ) -> Unmanaged<CFMessagePort>?
    private typealias FlattenInputSource = @convention(c) (
        TISInputSource,
        UnsafeMutablePointer<Unmanaged<AnyObject>?>
    ) -> DarwinBoolean

    private struct Symbols {
        let keyFocusProcess: KeyFocusProcess
        let processPID: ProcessPID
        let perProcessRemotePort: PerProcessRemotePort
        let flattenInputSource: FlattenInputSource
    }

    private static let symbols: Symbols? = {
        let handle = UnsafeMutableRawPointer(bitPattern: -2)
        guard
            let keyFocusProcess = dlsym(handle, "CPSGetKeyFocusProcess"),
            let processPID = dlsym(handle, "GetProcessPID"),
            let perProcessRemotePort = dlsym(handle, "CFMessagePortCreatePerProcessRemote"),
            let flattenInputSource = dlsym(handle, "_CreateFlattenedInputSource")
        else {
            return nil
        }

        return Symbols(
            keyFocusProcess: unsafeBitCast(keyFocusProcess, to: KeyFocusProcess.self),
            processPID: unsafeBitCast(processPID, to: ProcessPID.self),
            perProcessRemotePort: unsafeBitCast(perProcessRemotePort, to: PerProcessRemotePort.self),
            flattenInputSource: unsafeBitCast(flattenInputSource, to: FlattenInputSource.self)
        )
    }()

    static let requestKey = "tsmInputSourceSelectedInpSrcKey"
    static let replyErrorKey = "tsmInputModeReplyToServerErrorKey"
    private static let portName = "com.apple.tsm.portname"
    private static let selectInputSourceMessageID: Int32 = 7
    private static let timeout: CFTimeInterval = 0.3

    func select(_ source: TISInputSource) -> FocusedAppSelectionResult {
        guard let symbols = Self.symbols else {
            return .unavailable("TSM symbols unavailable")
        }

        guard let pid = keyFocusPID(symbols) else {
            return .unavailable("No key focus process")
        }

        // TISSelectInputSource is reliable for this process's own text input.
        guard pid != getpid() else {
            return .unavailable("Key focus is this process")
        }

        var flattenedReference: Unmanaged<AnyObject>?
        guard
            symbols.flattenInputSource(source, &flattenedReference).boolValue,
            let flattened = flattenedReference?.takeRetainedValue(),
            let data = Self.makeRequestData(flattened: flattened)
        else {
            return .unavailable("Failed to flatten input source")
        }

        guard let port = symbols.perProcessRemotePort(nil, Self.portName as CFString, pid)?.takeRetainedValue() else {
            return .unavailable("No TSM port for pid \(pid)")
        }

        var reply: Unmanaged<CFData>?
        let status = CFMessagePortSendRequest(
            port,
            Self.selectInputSourceMessageID,
            data as CFData,
            Self.timeout,
            Self.timeout,
            CFRunLoopMode.defaultMode.rawValue,
            &reply
        )
        guard status == kCFMessagePortSuccess else {
            return .unavailable("TSM request to pid \(pid) failed: status=\(status)")
        }

        guard Self.isSuccessfulReply(reply?.takeRetainedValue() as Data?) else {
            return .unavailable("TSM request to pid \(pid) rejected")
        }

        return .selected
    }

    static func makeRequestData(flattened: AnyObject) -> Data? {
        let request = [requestKey: flattened] as CFDictionary
        return CFPropertyListCreateData(nil, request, .xmlFormat_v1_0, 0, nil)?.takeRetainedValue() as Data?
    }

    // Only an explicit non-zero error rejects the request; the port accepted it.
    static func isSuccessfulReply(_ data: Data?) -> Bool {
        guard
            let data,
            let reply = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
            let error = reply[replyErrorKey] as? Int
        else {
            return true
        }

        return error == 0
    }

    // The process that receives key events, which is not always the frontmost
    // app: a non-activating panel such as Spotlight can hold keyboard focus.
    private func keyFocusPID(_ symbols: Symbols) -> pid_t? {
        var psn = ProcessSerialNumber()
        var ignored: DarwinBoolean = false
        var pid: pid_t = -1
        guard
            symbols.keyFocusProcess(&psn, &ignored) == 0,
            symbols.processPID(&psn, &pid) == noErr,
            pid > 0
        else {
            return nil
        }

        return pid
    }
}
