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
    var lastToggleTime: Date?

    /// Cached `inputMethodHotkeyEnabled` flag. Avoids a UserDefaults disk read
    /// on every event-tap callback (including flagsChanged for Cmd/Shift/Option),
    /// which on macOS 15 can be slow enough to trigger a tap timeout. Refreshed
    /// in `applyEngineSettings()` when settings change.
    var fnHotkeyEnabled = false

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
    var appSwitchObserver: NSObjectProtocol?

    /// Performance logging for keystroke latency (only logs slow / high-event paths).
    /// Backed by `Logger.shared` so concurrent writes are serialized on a
    /// dedicated queue (Bug #8: previous `FileHandle` was written from the
    /// event-tap runloop without locking, which could crash).
    var perfEventCount = 0
    var perfStartTime: CFAbsoluteTime = 0

    /// Cached app classification sets. Reading from UserDefaults on every
    /// event tap callback is expensive (disk-backed store + Set allocation)
    /// and can cause the callback to exceed the system's timeout, leading
    /// to the tap being disabled — which blocks all keyboard input including
    /// copy/paste. Cache the sets and reload only on settings change.
    var cachedExcludedApps: Set<String> = []
    var cachedCompoundApps: Set<String> = []
    var cachedChromiumApps: Set<String> = []
    /// Tracks whether the CGEventTap is currently disabled for an excluded app.
    /// Prevents redundant `CGEvent.tapEnable` calls on every app switch.
    var lastExcludedState = false

    init(inputMethodManager: InputMethodManager) {
        self.inputMethodManager = inputMethodManager
        self.axInjector = AXTextInjector(engine: _engine)
        eventSource = CGEventSource(stateID: .privateState)
        applyEngineSettings()
        reloadAppCaches()
        observeSettingsChanges()
        observeEngineResetNotification()
        observeAppSwitch()
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
        if let appSwitchObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(appSwitchObserver)
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
            // Start the app detector on the retry path too — start() skips it
            // when accessibility isn't granted, so without this the bundleID
            // stays empty forever and app classification never works.
            self.appDetector.start()
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
        let newMethod = InputMethod(rawValue: method) ?? .telex
        // Reset the engine when the input method changes — stale composing
        // state from the old method (e.g. Telex tone keys 's','f','r') would
        // be misinterpreted in the new method (VNI digits '1','2','3'),
        // producing ghost characters or wrong output.
        if newMethod != inputMethodManager.inputMethod {
            _engine.reset()
        }
        _engine.setInputMethod(newMethod)
        _engine.setModernOrthography(defaults.bool(forKey: DefaultsKey.modernOrthography))
        _engine.setRelaxedCoda(defaults.bool(forKey: DefaultsKey.relaxedCoda))
        _engine.setQuickTelex(defaults.bool(forKey: DefaultsKey.quickTelex))
        _engine.setQuickStart(defaults.bool(forKey: DefaultsKey.quickStart))
        // Cache the Fn hotkey flag so handleHotkey() doesn't read UserDefaults
        // on every event-tap callback (flagsChanged for any modifier key).
        fnHotkeyEnabled = defaults.bool(forKey: DefaultsKey.inputMethodHotkeyEnabled)
        // Reload app classification caches too — user may have added/removed
        // excluded or compound apps in Settings.
        reloadAppCaches()
    }

    /// Reload cached app classification sets from UserDefaults. Called on
    /// init and whenever settings change. Avoids per-event UserDefaults
    /// reads that can cause event tap timeouts.
    private func reloadAppCaches() {
        cachedExcludedApps = getExcludedApps()
        cachedCompoundApps = getCompoundApps()
        cachedChromiumApps = getChromiumBrowsers()
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

    /// Observe app switches directly (NSWorkspace notification) to update
    /// the excluded tap state before any events arrive. This is separate
    /// from `observeEngineResetNotification` because the Combine sink order
    /// between AppContextDetector and InputMethodManager is not guaranteed
    /// — appDetector.bundleID could be stale when the reset notification fires.
    private func observeAppSwitch() {
        appSwitchObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self,
                  let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                          as? NSRunningApplication else { return }
            self.appDetector.updateBundleID(app)
            // Reset Fn tracking on app switch — if the user released Fn while
            // the tap was disabled (excluded app), fnIsDown would be stale.
            self.fnIsDown = false
            self.fnWasTap = false
            self.updateExcludedTapState()
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
            // Reset Fn tracking — Fn may have been released while the tap was
            // disabled for an excluded app, leaving fnIsDown stale.
            self.fnIsDown = false
            self.fnWasTap = false
            // Do NOT reset isAtSentenceStart here — it should only be set
            // by sentence delimiters (. ! ?), Enter key, or app launch.
            // Resetting on every app switch causes wrong capitalization
            // when switching back to an app mid-sentence.
            self.updateExcludedTapState()
        }
    }

    /// Toggle the CGEventTap on/off based on whether the current frontmost
    /// app is in the excluded list. When excluded, the tap is disabled
    /// entirely so events flow through natively (no interception overhead,
    /// no timeout risk). Re-enables when switching back to a normal app.
    private func updateExcludedTapState() {
        let bundleID = appDetector.bundleID
        let excluded = cachedExcludedApps.contains(bundleID)
        if excluded != lastExcludedState {
            lastExcludedState = excluded
            if let tap {
                CGEvent.tapEnable(tap: tap, enable: !excluded)
                Logger.shared.info("EventTap: \(excluded ? "disabled" : "enabled") for app \(bundleID)")
            }
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
        cachedCompoundApps.contains(appDetector.bundleID)
    }

    var isChromium: Bool {
        cachedChromiumApps.contains(appDetector.bundleID)
    }

    var isExcludedApp: Bool {
        cachedExcludedApps.contains(appDetector.bundleID)
    }

    var isAXApp: Bool {
        axApps.contains(appDetector.bundleID)
    }

    var shouldBypass: Bool {
        bypassApps.contains(appDetector.bundleID)
    }
}
