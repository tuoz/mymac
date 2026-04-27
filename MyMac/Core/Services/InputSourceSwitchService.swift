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
        client: InputSourceSwitchingClient = CarbonInputSourceSwitchingClient(),
        diagnosticsService: DiagnosticsService
    ) {
        self.client = client
        self.diagnosticsService = diagnosticsService
    }

    func switchRomanNonRoman() -> InputSourceSwitchResult {
        let target = preferredTarget() ?? fallbackTarget()

        guard let target else {
            diagnosticsService.error("No input source switch target available", category: .keyboardMapping)
            return .unavailable("No input source switch target available")
        }

        return switchWithRetry(target)
    }

    private func switchWithRetry(_ target: InputSourceDescriptor) -> InputSourceSwitchResult {
        for i in 0..<2 {
            let status = client.selectInputSource(target)
            guard status == noErr else {
                diagnosticsService.error(
                    "Failed to select input source \(target.id): status=\(status)",
                    category: .keyboardMapping
                )
                return .selectionFailed(status)
            }
            if i < 1 {
                Thread.sleep(forTimeInterval: 0.018)
            }
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

        return TISSelectInputSource(reference.rawValue)
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
