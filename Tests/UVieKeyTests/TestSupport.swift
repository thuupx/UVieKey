import Cocoa
import XCTest
@testable import UVieKey

// MARK: - Recording synthetic-output sink

/// Records injection calls instead of posting real CGEvents, so `handle()`
/// can be driven with simulated keystrokes without touching the host session.
final class RecordingSink: SyntheticOutputSink {
    struct Call: Equatable {
        let method: String
        let arg: String

        static func backspaces(_ n: Int) -> Call { Call(method: "backspaces", arg: "\(n)") }
        static func text(_ s: String) -> Call { Call(method: "text", arg: s) }
        static func compound(_ bs: Int, _ out: String) -> Call { Call(method: "compoundBackspaces", arg: "\(bs)|\(out)") }
        static func selection(_ n: Int) -> Call { Call(method: "selectionBackspaces", arg: "\(n)") }
        static func emptyChar() -> Call { Call(method: "emptyChar", arg: "") }
    }

    private(set) var calls: [Call] = []

    func reset() {
        calls.removeAll()
    }

    func applyCompoundBackspaces(bs: Int, out: String) {
        calls.append(.compound(bs, out))
    }

    func applyBackspaces(_ count: Int) {
        calls.append(.backspaces(count))
    }

    func applySelectionBackspaces(_ count: Int) {
        calls.append(.selection(count))
    }

    func sendEmptyCharacter() {
        calls.append(.emptyChar())
    }

    func postText(_ string: String) {
        calls.append(.text(string))
    }
}

// MARK: - Stub app detector

/// Scripted `AppContextDetector`: `refreshBundleID()` walks `refreshResults`
/// in order (repeating the last entry once exhausted), simulating e.g.
/// Spotlight finishing opening a few hundred ms after Cmd+Space.
final class StubAppDetector: AppContextDetecting {
    var bundleID: String
    private let refreshResults: [String]
    private(set) var refreshCallCount = 0

    init(bundleID: String, refreshResults: [String]) {
        self.bundleID = bundleID
        self.refreshResults = refreshResults
    }

    convenience init(bundleID: String) {
        self.init(bundleID: bundleID, refreshResults: [bundleID])
    }

    func start() {}

    func stop() {}

    func updateBundleID(_ app: NSRunningApplication) {}

    func refreshBundleID() {
        let result = refreshResults[min(refreshCallCount, refreshResults.count - 1)]
        refreshCallCount += 1
        bundleID = result
    }
}

// MARK: - Stub AX injector

final class StubAXInjector: AXTextInjecting {
    var feedSuccess = true
    private(set) var fedChars: [Character] = []
    private(set) var backspaceCount = 0
    private(set) var commitCount = 0
    private(set) var resetCount = 0

    func feed(char: Character) -> Bool {
        fedChars.append(char)
        return feedSuccess
    }

    func backspace() -> Bool {
        backspaceCount += 1
        return true
    }

    func commit() -> Bool {
        commitCount += 1
        return false
    }

    func reset() {
        resetCount += 1
    }
}

// MARK: - EventTap fixture

/// Builds an `EventTap` with deterministic settings (the app's registered
/// defaults are overridden by the user's real UserDefaults, so every
/// environment-dependent flag is pinned here).
@discardableResult
func makeEventTap(vietnamese: Bool = true) -> EventTap {
    let manager = InputMethodManager()
    manager.isVietnamese = vietnamese
    let tap = EventTap(inputMethodManager: manager)
    tap._engine.setInputMethod(.telex)
    tap.autoCapitalizeEnabled = false
    tap.autoDisableOnNonLatinLayout = false
    tap.fnHotkeyEnabled = false
    tap.cachedExcludedApps = []
    tap.cachedCompoundApps = []
    tap.cachedChromiumApps = []
    return tap
}

// MARK: - CGEvent builders

func keyDownEvent(_ keyCode: Int64, flags: CGEventFlags = [], unicode: String? = nil) -> CGEvent {
    let event = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(clamping: keyCode), keyDown: true)!
    if let unicode {
        event.keyboardSetUnicodeString(stringLength: unicode.utf16.count, unicodeString: Array(unicode.utf16))
    }
    event.flags = flags
    return event
}

func keyUpEvent(_ keyCode: Int64, flags: CGEventFlags = [], unicode: String? = nil) -> CGEvent {
    let event = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(clamping: keyCode), keyDown: false)!
    if let unicode {
        event.keyboardSetUnicodeString(stringLength: unicode.utf16.count, unicodeString: Array(unicode.utf16))
    }
    event.flags = flags
    return event
}

/// Drives `handle()` exactly like the CGEventTap callback would.
@discardableResult
func send(_ tap: EventTap, _ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
    tap.handle(proxy: CGEventTapProxy(bitPattern: 1)!, type: type, event: event)
}

/// Asserts the event was consumed (callback returned nil) and balances the
/// `passRetained` retain when it was not.
func assertConsumed(_ result: Unmanaged<CGEvent>?, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertNil(result, "expected event to be consumed \(message)", file: file, line: line)
    result?.release()
}

func assertPassed(_ result: Unmanaged<CGEvent>?, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertNotNil(result, "expected event to pass through \(message)", file: file, line: line)
    result?.release()
}

// MARK: - Engine typing helper

/// Simulates a user typing `input` on a fresh engine and reconstructs the
/// on-screen text from the (backspaces, suffix) diffs — the same math the
/// EventTap injection performs.
func typeString(_ input: String, modern: Bool = true, method: InputMethod = .telex) -> String {
    let engine = EngineBridge()
    engine.setInputMethod(method)
    engine.setModernOrthography(modern)
    var screen = ""
    for ch in input {
        let (bs, out) = engine.feed(char: ch)
        screen = String(screen.dropLast(bs)) + out
    }
    return screen
}
