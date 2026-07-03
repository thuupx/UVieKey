import Cocoa
import Carbon

// MARK: - EventTap

final class EventTap: ObservableObject {
    @Published var isEnabled = true

    var tap: CFMachPort?
    var runLoopSource: CFRunLoopSource?
    /// The runloop that hosts the `CGEventTap` callback. Tracked so `stop()`
    /// can remove the source from the *correct* runloop instead of the caller's
    /// runloop (Bug #8: removing from the wrong runloop is a no-op and leaves
    /// the tap firing into a deallocated `self`, causing occasional crashes).
    var tapRunLoop: CFRunLoop?
    let _engine = EngineBridge()
    var engine: EngineBridge { _engine }
    let eventSource: CGEventSource?

    let inputMethodManager: InputMethodManager
    let appDetector = AppContextDetector()
    let axInjector: AXTextInjector
    let macroManager = MacroManager.shared
    let layoutMonitor = KeyboardLayoutMonitor.shared

    /// Tag synthetic events so we don't process our own output.
    let syntheticTag: Int64 = 0x55564945 // "UVIE"

    /// Observer token for UserDefaults runtime changes.
    var defaultsObserver: NSObjectProtocol?

    /// Fn-key hotkey state (event-tap callback thread only).
    var fnIsDown = false
    var fnWasTap = false
    var fnHandledByKeyEvent = false
    var lastToggleTime: Date?

    /// Retry state for `start()` (Bug #1, #6, #10). After a fresh login or
    /// onboarding, `AXIsProcessTrustedWithOptions` can return true from a
    /// stale cache while `CGEvent.tapCreate` still fails — the accessibility
    /// grant has not yet propagated to the event-tap subsystem. We retry with
    /// exponential backoff for up to 60s, re-checking trust each attempt,
    /// and stop retrying once the tap is created or the engine is stopped.
    var startRetryWorkItem: DispatchWorkItem?
    static let startRetryMaxAttempts = 8
    static let startRetryDelays: [TimeInterval] = [0.5, 1, 1.5, 2, 3, 5, 8, 10]

    /// Auto-capitalize state: track if we're at the start of a sentence
    var isAtSentenceStart = true

    /// App switch detection: prevent ghost characters from previous app
    var engineResetObserver: NSObjectProtocol?

    /// Performance logging for keystroke latency (only logs slow / high-event paths).
    /// Backed by `Logger.shared` so concurrent writes are serialized on a
    /// dedicated queue (Bug #8: previous `FileHandle` was written from the
    /// event-tap runloop without locking, which could crash).
    var perfEventCount = 0
    var perfStartTime: CFAbsoluteTime = 0

    init(inputMethodManager: InputMethodManager) {
        self.inputMethodManager = inputMethodManager
        self.axInjector = AXTextInjector(engine: _engine)
        eventSource = CGEventSource(stateID: .privateState)
        applyEngineSettings()
        observeSettingsChanges()
        observeEngineResetNotification()
    }

    deinit {
        stop()
        appDetector.stop()
        if let defaultsObserver {
            NotificationCenter.default.removeObserver(defaultsObserver)
        }
        if let engineResetObserver {
            NotificationCenter.default.removeObserver(engineResetObserver)
        }
    }

    // MARK: - Lifecycle

    func start() {
        guard tap == nil else { return }
        // Cancel any pending retry before a fresh attempt.
        startRetryWorkItem?.cancel()
        startRetryWorkItem = nil

        guard AccessibilityChecker.isTrusted else {
            Logger.shared.warn("EventTap.start: Accessibility not granted, scheduling retry")
            print("EventTap: Accessibility not granted")
            scheduleStartRetry(attempt: 0)
            return
        }

        appDetector.start()
        Logger.shared.info("EventTap.start: creating CGEventTap")
        startTap()
    }

    /// Attempts to create the `CGEventTap`. On failure, schedules a retry with
    /// exponential backoff. Called from `start()` and from the retry path.
    private func startTap() {
        guard tap == nil else { return }

        let callback: CGEventTapCallBack = { proxy, type, event, refcon in
            guard let refcon else { return Unmanaged.passRetained(event) }
            let myself = Unmanaged<EventTap>.fromOpaque(refcon).takeUnretainedValue()
            return myself.handle(proxy: proxy, type: type, event: event)
        }

        let eventMask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.keyUp.rawValue) |
            (1 << CGEventType.flagsChanged.rawValue) |
            (1 << CGEventType.leftMouseDown.rawValue) |
            (1 << CGEventType.rightMouseDown.rawValue) |
            (1 << CGEventType.leftMouseDragged.rawValue) |
            (1 << CGEventType.rightMouseDragged.rawValue)

        guard let newTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            Logger.shared.error("EventTap.startTap: CGEvent.tapCreate returned nil — accessibility grant may not be active yet, scheduling retry")
            print("EventTap: Failed to create tap")
            scheduleStartRetry(attempt: 0)
            return
        }

        self.tap = newTap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, newTap, 0)
        self.runLoopSource = source
        // Add the source to the MAIN runloop (same as the original design).
        // The CGEventTap callback fires on the runloop that owns the source;
        // keeping it on main avoids thread-safety issues with AppKit state
        // accessed inside `handle()` (NSApp, NSEvent, AXUIElement, etc.).
        // The main runloop is already driven by NSApplication.run(), so no
        // background CFRunLoopRun() is needed.
        let mainRunLoop = CFRunLoopGetMain()
        CFRunLoopAddSource(mainRunLoop, source, .commonModes)
        self.tapRunLoop = mainRunLoop
        CGEvent.tapEnable(tap: newTap, enable: true)

        // Success — clear any pending retry and notify the host.
        startRetryWorkItem?.cancel()
        startRetryWorkItem = nil
        Logger.shared.info("EventTap: tap created successfully")
        NotificationCenter.default.post(name: .eventTapDidStart, object: nil)
    }

    /// Schedule a `start()` retry after `delay`. Re-checks accessibility trust
    /// before each attempt so a user granting permission mid-retry is picked up.
    private func scheduleStartRetry(attempt: Int) {
        guard attempt < Self.startRetryMaxAttempts else {
            Logger.shared.error("EventTap: gave up after \(Self.startRetryMaxAttempts) retry attempts — user must restart UVieKey after granting Accessibility")
            NotificationCenter.default.post(name: .eventTapStartFailed, object: nil)
            return
        }
        let delay = Self.startRetryDelays[min(attempt, Self.startRetryDelays.count - 1)]
        let workItem = DispatchWorkItem { [weak self] in
            guard let self, self.tap == nil else { return }
            guard AccessibilityChecker.isTrusted else {
                Logger.shared.warn("EventTap: still not trusted on retry #\(attempt + 1)")
                self.scheduleStartRetry(attempt: attempt + 1)
                return
            }
            Logger.shared.info("EventTap: retry #\(attempt + 1) creating tap")
            // appDetector.start() is already called in start(); don't double-start.
            self.startTap()
        }
        startRetryWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    func stop() {
        startRetryWorkItem?.cancel()
        startRetryWorkItem = nil
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let runLoopSource, let tapRunLoop {
            CFRunLoopRemoveSource(tapRunLoop, runLoopSource, .commonModes)
        }
        tap = nil
        runLoopSource = nil
        tapRunLoop = nil
        appDetector.stop()
        Logger.shared.info("EventTap.stop: tap released")
    }

    // MARK: - Helpers

    func getCurrentText() -> String {
        // Macro matching must consider the full on-screen text: the V-C-V
        // auto-committed prefix (diff_committed) plus the current composing
        // portion. Using currentOutput() alone misses the committed prefix,
        // so a macro typed across a V-C-V split (e.g. "neebo" → "nê" + "bo")
        // would only match against "bo" instead of "nêbo".
        let committed = _engine.committedText()
        let composing = _engine.currentOutput()
        return committed + composing
    }

    // MARK: - Performance Logging

    func perfBegin() {
        perfStartTime = CFAbsoluteTimeGetCurrent()
        perfEventCount = 0
    }

    func perfNoteEvent(_ count: Int = 1) {
        perfEventCount += count
    }

    func perfEnd(_ label: String, keyCode: Int64, app: String) {
        let elapsedMs = (CFAbsoluteTimeGetCurrent() - perfStartTime) * 1000
        // Log anything that takes >5ms or posts >4 synthetic events (normal path is 1 event).
        guard elapsedMs > 5.0 || perfEventCount > 4 else { return }
        Logger.shared.debug(String(
            format: "[perf %.3f ms] %@ keyCode=%lld events=%d app=%@",
            elapsedMs, label, keyCode, perfEventCount, app
        ))
    }

    // MARK: - Settings

    /// Read all engine-relevant settings from UserDefaults and push to the
    /// shared engine. Called on init and whenever defaults change at runtime.
    func applyEngineSettings() {
        let defaults = UserDefaults.standard
        let method = defaults.string(forKey: DefaultsKey.inputMethod) ?? "telex"
        _engine.setInputMethod(method == "vni" ? .vni : .telex)
        _engine.setModernOrthography(defaults.bool(forKey: DefaultsKey.modernOrthography))
        _engine.setRelaxedCoda(defaults.bool(forKey: DefaultsKey.relaxedCoda))
        _engine.setQuickTelex(defaults.bool(forKey: DefaultsKey.quickTelex))
        _engine.setQuickStart(defaults.bool(forKey: DefaultsKey.quickStart))
    }

    /// Observe runtime setting changes so toggling Quick Telex, Modern
    /// Orthography, etc. in Settings takes effect without restart.
    private func observeSettingsChanges() {
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.applyEngineSettings()
        }
    }

    private func observeEngineResetNotification() {
        engineResetObserver = NotificationCenter.default.addObserver(
            forName: .resetEngineAfterAppSwitch,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            // Reset engine to clear ghost characters from previous app
            self._engine.reset()
            // Reset auto-capitalize state for new app context
            self.isAtSentenceStart = true
        }
    }

    // MARK: - App classification helpers

    let breakKeyCodes: Set<Int64> = [
        36,  48,  53,  116, 121, 123, 124, 125, 126, 115, 119, 114, 117,
    ]

    func isBreakKey(_ keyCode: Int64) -> Bool {
        breakKeyCodes.contains(keyCode)
    }

    /// Arrow key codes: left=123, right=124, down=125, up=126.
    /// These move the cursor within text, so the engine must reset (not commit)
    /// to avoid applying stale composing state at the new cursor position.
    func isArrowKey(_ keyCode: Int64) -> Bool {
        keyCode == 123 || keyCode == 124 || keyCode == 125 || keyCode == 126
    }

    var isCompoundApp: Bool {
        checkIsCompoundApp(appDetector.bundleID)
    }

    var isChromium: Bool {
        checkIsChromiumBrowser(appDetector.bundleID)
    }

    var isExcludedApp: Bool {
        checkIsExcludedApp(appDetector.bundleID)
    }

    var isAXApp: Bool {
        axApps.contains(appDetector.bundleID)
    }

    var shouldBypass: Bool {
        bypassApps.contains(appDetector.bundleID)
    }
}
