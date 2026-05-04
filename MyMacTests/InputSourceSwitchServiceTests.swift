import XCTest
@testable import MyMac

final class InputSourceSwitchServiceTests: XCTestCase {
    func testSwitchesFromNonRomanToASCIIUsingPreferredTarget() {
        let client = MockInputSourceSwitchingClient(
            current: .pinyin,
            nonRoman: .pinyin,
            ascii: .abc,
            enabled: [.abc, .pinyin]
        )
        let service = DefaultInputSourceSwitchService(
            client: client,
            diagnosticsService: MockDiagnosticsService()
        )

        XCTAssertEqual(service.switchRomanNonRoman(), InputSourceSwitchResult.success)
        XCTAssertEqual(client.selectedIDs, ["abc"])
    }

    func testSwitchesFromASCIIToNonRomanUsingPreferredTarget() {
        let client = MockInputSourceSwitchingClient(
            current: .abc,
            nonRoman: .pinyin,
            ascii: .abc,
            enabled: [.abc, .pinyin]
        )
        let service = DefaultInputSourceSwitchService(
            client: client,
            diagnosticsService: MockDiagnosticsService()
        )

        XCTAssertEqual(service.switchRomanNonRoman(), InputSourceSwitchResult.success)
        XCTAssertEqual(client.selectedIDs, ["pinyin"])
    }

    func testFallsBackFromASCIIToFirstNonASCIIInputSource() {
        let client = MockInputSourceSwitchingClient(
            current: .abc,
            nonRoman: nil,
            ascii: .abc,
            enabled: [.abc, .pinyin]
        )
        let service = DefaultInputSourceSwitchService(
            client: client,
            diagnosticsService: MockDiagnosticsService()
        )

        XCTAssertEqual(service.switchRomanNonRoman(), InputSourceSwitchResult.success)
        XCTAssertEqual(client.selectedIDs, ["pinyin"])
    }

    func testFallsBackFromNonASCIIToASCIIInputSource() {
        let client = MockInputSourceSwitchingClient(
            current: .pinyin,
            nonRoman: nil,
            ascii: .abc,
            enabled: [.abc, .pinyin]
        )
        let service = DefaultInputSourceSwitchService(
            client: client,
            diagnosticsService: MockDiagnosticsService()
        )

        XCTAssertEqual(service.switchRomanNonRoman(), InputSourceSwitchResult.success)
        XCTAssertEqual(client.selectedIDs, ["abc"])
    }

    func testReturnsUnavailableWhenNoTargetExists() {
        let client = MockInputSourceSwitchingClient(
            current: .abc,
            nonRoman: nil,
            ascii: .abc,
            enabled: [.abc]
        )
        let service = DefaultInputSourceSwitchService(
            client: client,
            diagnosticsService: MockDiagnosticsService()
        )

        if case .unavailable = service.switchRomanNonRoman() {
            XCTAssertTrue(client.selectedIDs.isEmpty)
        } else {
            XCTFail("Expected unavailable result")
        }
    }

    func testReturnsSelectionFailedWhenClientRejectsTarget() {
        let client = MockInputSourceSwitchingClient(
            current: .abc,
            nonRoman: .pinyin,
            ascii: .abc,
            enabled: [.abc, .pinyin],
            selectionStatus: OSStatus(paramErr)
        )
        let service = DefaultInputSourceSwitchService(
            client: client,
            diagnosticsService: MockDiagnosticsService()
        )

        XCTAssertEqual(service.switchRomanNonRoman(), InputSourceSwitchResult.selectionFailed(OSStatus(paramErr)))
        XCTAssertEqual(client.selectedIDs, ["pinyin"])
    }

    func testRefreshCurrentInputSourceReSelectsCurrentInputSource() {
        let client = MockInputSourceSwitchingClient(
            current: .pinyin,
            nonRoman: .pinyin,
            ascii: .abc,
            enabled: [.abc, .pinyin]
        )
        let service = DefaultInputSourceSwitchService(
            client: client,
            diagnosticsService: MockDiagnosticsService()
        )

        XCTAssertEqual(service.refreshCurrentInputSource(), InputSourceSwitchResult.success)
        XCTAssertEqual(client.selectedIDs, ["pinyin"])
    }

    func testRefreshCurrentInputSourceReturnsUnavailableWhenCurrentIsMissing() {
        let client = MockInputSourceSwitchingClient(
            current: nil,
            nonRoman: .pinyin,
            ascii: .abc,
            enabled: [.abc, .pinyin]
        )
        let service = DefaultInputSourceSwitchService(
            client: client,
            diagnosticsService: MockDiagnosticsService()
        )

        if case .unavailable = service.refreshCurrentInputSource() {
            XCTAssertTrue(client.selectedIDs.isEmpty)
        } else {
            XCTFail("Expected unavailable result")
        }
    }

    func testRefreshCurrentInputSourceReturnsSelectionFailedWhenClientRejectsCurrent() {
        let client = MockInputSourceSwitchingClient(
            current: .pinyin,
            nonRoman: .pinyin,
            ascii: .abc,
            enabled: [.abc, .pinyin],
            selectionStatus: OSStatus(paramErr)
        )
        let service = DefaultInputSourceSwitchService(
            client: client,
            diagnosticsService: MockDiagnosticsService()
        )

        XCTAssertEqual(service.refreshCurrentInputSource(), InputSourceSwitchResult.selectionFailed(OSStatus(paramErr)))
        XCTAssertEqual(client.selectedIDs, ["pinyin"])
    }

    func testMockKeepsCurrentInputSourceWhenSelectionFails() {
        let client = MockInputSourceSwitchingClient(
            current: .abc,
            nonRoman: .pinyin,
            ascii: .abc,
            enabled: [.abc, .pinyin],
            selectionStatus: OSStatus(paramErr)
        )

        XCTAssertEqual(client.selectInputSource(.pinyin), OSStatus(paramErr))
        XCTAssertEqual(client.currentInputSource(), .abc)
        XCTAssertEqual(client.selectedIDs, ["pinyin"])
    }
}

final class InputSourceSwitchTriggerTests: XCTestCase {
    func testSuccessfulTriggerSwitchesOnceAndReselectsTwice() {
        let service = MockInputSourceSwitchService()
        let scheduler = ManualInputSourceSwitchScheduler()
        let trigger = InputSourceSwitchTrigger(
            inputSourceSwitchService: service,
            diagnosticsService: MockDiagnosticsService(),
            scheduler: scheduler
        )

        trigger.trigger()

        XCTAssertEqual(scheduler.pendingCount, 1)
        scheduler.runNext()
        XCTAssertEqual(service.switchCount, 1)
        XCTAssertEqual(service.refreshCount, 0)
        XCTAssertEqual(scheduler.pendingCount, 1)

        scheduler.runNext()
        XCTAssertEqual(service.refreshCount, 1)
        XCTAssertEqual(scheduler.recordedDelays, [0.018, 0.018])

        scheduler.runNext()
        XCTAssertEqual(service.refreshCount, 2)
        XCTAssertEqual(scheduler.recordedDelays, [0.018, 0.018])
        XCTAssertEqual(scheduler.pendingCount, 0)
    }

    func testTriggerSuppressesConcurrentSwitchWhileSessionIsActive() {
        let service = MockInputSourceSwitchService()
        let scheduler = ManualInputSourceSwitchScheduler()
        let trigger = InputSourceSwitchTrigger(
            inputSourceSwitchService: service,
            diagnosticsService: MockDiagnosticsService(),
            scheduler: scheduler
        )

        trigger.trigger()
        trigger.trigger()
        scheduler.runAll()

        XCTAssertEqual(service.switchCount, 1)
        XCTAssertEqual(service.refreshCount, 2)
    }

    func testRefreshFailureStopsRetriesAndAllowsFutureTrigger() {
        let service = MockInputSourceSwitchService(
            refreshResults: [.selectionFailed(OSStatus(paramErr))]
        )
        let scheduler = ManualInputSourceSwitchScheduler()
        let trigger = InputSourceSwitchTrigger(
            inputSourceSwitchService: service,
            diagnosticsService: MockDiagnosticsService(),
            scheduler: scheduler
        )

        trigger.trigger()
        scheduler.runAll()

        XCTAssertEqual(service.switchCount, 1)
        XCTAssertEqual(service.refreshCount, 1)
        XCTAssertEqual(scheduler.pendingCount, 0)

        trigger.trigger()
        scheduler.runAll()

        XCTAssertEqual(service.switchCount, 2)
    }

    func testInitialSwitchFailureAllowsFutureTrigger() {
        let service = MockInputSourceSwitchService(
            switchResults: [.selectionFailed(OSStatus(paramErr)), .success]
        )
        let scheduler = ManualInputSourceSwitchScheduler()
        let trigger = InputSourceSwitchTrigger(
            inputSourceSwitchService: service,
            diagnosticsService: MockDiagnosticsService(),
            scheduler: scheduler
        )

        trigger.trigger()
        scheduler.runAll()

        XCTAssertEqual(service.switchCount, 1)
        XCTAssertEqual(service.refreshCount, 0)

        trigger.trigger()
        scheduler.runAll()

        XCTAssertEqual(service.switchCount, 2)
        XCTAssertEqual(service.refreshCount, 2)
    }

    func testCancelPreventsPendingReselectAndAllowsFutureTrigger() {
        let service = MockInputSourceSwitchService()
        let scheduler = ManualInputSourceSwitchScheduler()
        let trigger = InputSourceSwitchTrigger(
            inputSourceSwitchService: service,
            diagnosticsService: MockDiagnosticsService(),
            scheduler: scheduler
        )

        trigger.trigger()
        scheduler.runNext()
        XCTAssertEqual(service.switchCount, 1)
        XCTAssertEqual(scheduler.pendingCount, 1)

        trigger.cancel()
        scheduler.runAll()
        XCTAssertEqual(service.refreshCount, 0)

        trigger.trigger()
        scheduler.runAll()
        XCTAssertEqual(service.switchCount, 2)
        XCTAssertEqual(service.refreshCount, 2)
    }
}

private extension InputSourceDescriptor {
    static let abc = InputSourceDescriptor(id: "abc", isASCIICapable: true)
    static let pinyin = InputSourceDescriptor(id: "pinyin", isASCIICapable: false)
}

private final class MockInputSourceSwitchingClient: InputSourceSwitchingClient, @unchecked Sendable {
    private var current: InputSourceDescriptor?
    private let nonRoman: InputSourceDescriptor?
    private let ascii: InputSourceDescriptor?
    private let enabled: [InputSourceDescriptor]
    private let selectionStatus: OSStatus
    private(set) var selectedIDs: [String] = []

    init(
        current: InputSourceDescriptor?,
        nonRoman: InputSourceDescriptor?,
        ascii: InputSourceDescriptor?,
        enabled: [InputSourceDescriptor],
        selectionStatus: OSStatus = noErr
    ) {
        self.current = current
        self.nonRoman = nonRoman
        self.ascii = ascii
        self.enabled = enabled
        self.selectionStatus = selectionStatus
    }

    func currentInputSource() -> InputSourceDescriptor? {
        current
    }

    func currentNonRomanInputSourceForRomanSwitch() -> InputSourceDescriptor? {
        nonRoman
    }

    func currentASCIICapableInputSource() -> InputSourceDescriptor? {
        ascii
    }

    func enabledInputSources() -> [InputSourceDescriptor] {
        enabled
    }

    func selectInputSource(_ inputSource: InputSourceDescriptor) -> OSStatus {
        selectedIDs.append(inputSource.id)
        if selectionStatus == noErr {
            current = inputSource
        }
        return selectionStatus
    }
}

private struct MockDiagnosticsService: DiagnosticsService {
    func log(_ message: String, category: DiagnosticsCategory) {}
    func error(_ message: String, category: DiagnosticsCategory) {}
}

private final class MockInputSourceSwitchService: InputSourceSwitchService, @unchecked Sendable {
    private var switchResults: [InputSourceSwitchResult]
    private var refreshResults: [InputSourceSwitchResult]
    private(set) var switchCount = 0
    private(set) var refreshCount = 0

    init(
        switchResults: [InputSourceSwitchResult] = [],
        refreshResults: [InputSourceSwitchResult] = []
    ) {
        self.switchResults = switchResults
        self.refreshResults = refreshResults
    }

    func switchRomanNonRoman() -> InputSourceSwitchResult {
        switchCount += 1
        guard !switchResults.isEmpty else {
            return .success
        }
        return switchResults.removeFirst()
    }

    func refreshCurrentInputSource() -> InputSourceSwitchResult {
        refreshCount += 1
        guard !refreshResults.isEmpty else {
            return .success
        }
        return refreshResults.removeFirst()
    }
}

private final class ManualInputSourceSwitchScheduler: InputSourceSwitchScheduling, @unchecked Sendable {
    private var actions: [@Sendable () -> Void] = []
    private(set) var recordedDelays: [TimeInterval] = []

    var pendingCount: Int {
        actions.count
    }

    func async(_ action: @escaping @Sendable () -> Void) {
        actions.append(action)
    }

    func asyncAfter(_ delay: TimeInterval, _ action: @escaping @Sendable () -> Void) {
        recordedDelays.append(delay)
        actions.append(action)
    }

    func runNext() {
        guard !actions.isEmpty else {
            return
        }

        let action = actions.removeFirst()
        action()
    }

    func runAll() {
        while !actions.isEmpty {
            runNext()
        }
    }
}
