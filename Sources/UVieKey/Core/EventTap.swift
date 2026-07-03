import Cocoa
import Carbon

// MARK: - App Classification

/// Default apps that need empty-character sentinel before backspace (invalidate autocomplete).
/// Matched by prefix OR exact bundle ID.
private let defaultCompoundApps: Set<String> = AppDefaults.compoundApps

/// Get compound apps from UserDefaults (defaults + custom)
private func getCompoundApps() -> Set<String> {
    let custom = UserDefaults.standard.stringArray(forKey: DefaultsKey.customCompoundApps) ?? []
    return defaultCompoundApps.union(Set(custom))
}

/// Apps that need Accessibility text injection instead of CGEventTap.
/// Spotlight and some secure text fields don't accept synthetic key events.
private let axApps: Set<String> = AppDefaults.axApps

/// Apps that should bypass IME entirely (system UI, lock screen, etc.)
private let bypassApps: Set<String> = AppDefaults.bypassApps

/// Apps the user explicitly wants to exclude from UVieKey processing.
/// Events for these apps pass through untouched.
private let defaultExcludedApps: Set<String> = []

/// Get excluded apps from UserDefaults (defaults + custom)
private func getExcludedApps() -> Set<String> {
    let custom = UserDefaults.standard.stringArray(forKey: DefaultsKey.customExcludedApps) ?? []
    return defaultExcludedApps.union(Set(custom))
}

/// Default Chromium browsers that need Shift+Left Arrow selection
/// instead of plain backspace (avoids duplicate chars).
private let defaultChromiumBrowsers: Set<String> = AppDefaults.chromiumBrowsers

/// Get Chromium browsers from UserDefaults (defaults + custom)
private func getChromiumBrowsers() -> Set<String> {
    let custom = UserDefaults.standard.stringArray(forKey: DefaultsKey.customChromiumApps) ?? []
    return defaultChromiumBrowsers.union(Set(custom))
}

private func checkIsCompoundApp(_ bundleID: String) -> Bool {
    getCompoundApps().contains(bundleID)
}

private func checkIsChromiumBrowser(_ bundleID: String) -> Bool {
    getChromiumBrowsers().contains(bundleID)
}

private func checkIsExcludedApp(_ bundleID: String) -> Bool {
    getExcludedApps().contains(bundleID)
}

/// Returns true for shortcuts that select text (Cmd+A, Shift+arrows, etc.).
/// When the user selects text and types over it, the engine's diff state
/// becomes invalid because it cannot see the selection.
private func isSelectionShortcut(keyCode: Int64, flags: CGEventFlags) -> Bool {
    let isCmdA = keyCode == 0 && flags.contains(.maskCommand)
    let isShiftArrow = flags.contains(.maskShift) && (123...126).contains(keyCode)
    return isCmdA || isShiftArrow
}

// MARK: - EventTap

final class EventTap: ObservableObject {
    @Published var isEnabled = true

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    /// The runloop that hosts the `CGEventTap` callback. Tracked so `stop()`
    /// can remove the source from the *correct* runloop instead of the caller's
    /// runloop (Bug #8: removing from the wrong runloop is a no-op and leaves
    /// the tap firing into a deallocated `self`, causing occasional crashes).
    private var tapRunLoop: CFRunLoop?
    private let _engine = EngineBridge()
    var engine: EngineBridge { _engine }
    private let eventSource: CGEventSource?

    let inputMethodManager: InputMethodManager
    private let appDetector = AppContextDetector()
    private let axInjector: AXTextInjector
    private let macroManager = MacroManager.shared
    private let layoutMonitor = KeyboardLayoutMonitor.shared

    /// Tag synthetic events so we don't process our own output.
    private let syntheticTag: Int64 = 0x55564945 // "UVIE"

    /// Observer token for UserDefaults runtime changes.
    private var defaultsObserver: NSObjectProtocol?

    /// Fn-key hotkey state (event-tap callback thread only).
    private var fnIsDown = false
    private var fnWasTap = false
    private var fnHandledByKeyEvent = false
    private var lastToggleTime: Date?

    /// Retry state for `start()` (Bug #1, #6, #10). After a fresh login or
    /// onboarding, `AXIsProcessTrustedWithOptions` can return true from a
    /// stale cache while `CGEvent.tapCreate` still fails — the accessibility
    /// grant has not yet propagated to the event-tap subsystem. We retry with
    /// exponential backoff for up to 60s, re-checking trust each attempt,
    /// and stop retrying once the tap is created or the engine is stopped.
    private var startRetryWorkItem: DispatchWorkItem?
    private static let startRetryMaxAttempts = 8
    private static let startRetryDelays: [TimeInterval] = [0.5, 1, 1.5, 2, 3, 5, 8, 10]

    /// Auto-capitalize state: track if we're at the start of a sentence
    private var isAtSentenceStart = true

    /// App switch detection: prevent ghost characters from previous app
    private var engineResetObserver: NSObjectProtocol?

    /// Performance logging for keystroke latency (only logs slow / high-event paths).
    /// Backed by `Logger.shared` so concurrent writes are serialized on a
    /// dedicated queue (Bug #8: previous `FileHandle` was written from the
    /// event-tap runloop without locking, which could crash).
    private var perfEventCount = 0
    private var perfStartTime: CFAbsoluteTime = 0

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
    
    private func getCurrentText() -> String {
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

    private func perfBegin() {
        perfStartTime = CFAbsoluteTimeGetCurrent()
        perfEventCount = 0
    }

    private func perfNoteEvent(_ count: Int = 1) {
        perfEventCount += count
    }

    private func perfEnd(_ label: String, keyCode: Int64, app: String) {
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

    // MARK: - Event Handling

    private let breakKeyCodes: Set<Int64> = [
        36,  48,  53,  116, 121, 123, 124, 125, 126, 115, 119, 114, 117,
    ]

    private func isBreakKey(_ keyCode: Int64) -> Bool {
        breakKeyCodes.contains(keyCode)
    }

    private var isCompoundApp: Bool {
        checkIsCompoundApp(appDetector.bundleID)
    }

    private var isChromium: Bool {
        checkIsChromiumBrowser(appDetector.bundleID)
    }

    private var isExcludedApp: Bool {
        checkIsExcludedApp(appDetector.bundleID)
    }

    private var isAXApp: Bool {
        axApps.contains(appDetector.bundleID)
    }

    private var shouldBypass: Bool {
        bypassApps.contains(appDetector.bundleID)
    }

    private func handle(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // Skip our own synthetic events
        if event.getIntegerValueField(.eventSourceStateID) == syntheticTag {
            return Unmanaged.passRetained(event)
        }

        // Bypass system UI apps
        if shouldBypass {
            return Unmanaged.passRetained(event)
        }

        // User-excluded apps: pass all events through untouched.
        // Reset the engine so stale composing state doesn't leak when the user
        // switches back to a normal app.
        if isExcludedApp {
            _engine.reset()
            return Unmanaged.passRetained(event)
        }

        // Global hotkey: Fn tap toggles Vietnamese / English
        if handleHotkey(type: type, event: event) {
            return nil
        }

        // Pass through flags changes
        if type == .flagsChanged {
            return Unmanaged.passRetained(event)
        }

        // Mouse down/drag starts a new editing session (selection, click, etc.).
        // Reset the engine so stale composing state cannot be applied after the
        // user selects text with the mouse.
        if type == .leftMouseDown || type == .rightMouseDown ||
           type == .leftMouseDragged || type == .rightMouseDragged {
            _engine.reset()
            return Unmanaged.passRetained(event)
        }

        // Only handle keyDown/keyUp
        guard type == .keyDown || type == .keyUp else {
            return Unmanaged.passRetained(event)
        }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags
        let app = appDetector.bundleID
        perfBegin()

        // DEBUG: Trace ghost character issue
        if type == .keyDown {
            let composing = _engine.currentOutput()
            let committed = _engine.committedText()
            if !composing.isEmpty || !committed.isEmpty {
                Logger.shared.keystroke("keydown keyCode=\(keyCode) composing='\(composing)' committed='\(committed)' app=\(app)")
            }
            #if DEBUG
            if !composing.isEmpty || !committed.isEmpty {
                NSLog("[UVieKey] keystroke - keyCode: \(keyCode), composing: '\(composing)', committed: '\(committed)'")
            }
            #endif
        }

        // Detect text-selection shortcuts. The diff engine tracks text at the
        // insertion point only; when the user selects text and types over it,
        // our state becomes invalid, so reset the engine.
        if type == .keyDown && isSelectionShortcut(keyCode: keyCode, flags: flags) {
            _engine.reset()
        }

        // Pass through modifier combinations (except Option+Backspace which we handle specially)
        let isAlternateOnly = flags.contains(.maskAlternate) &&
                             !flags.contains(.maskCommand) &&
                             !flags.contains(.maskControl) &&
                             !flags.contains(.maskSecondaryFn)
        let isOptionBackspace = isAlternateOnly && keyCode == 51

        // Cmd+Backspace / Ctrl+Backspace delete to line start (or whole line) at the
        // OS level, which the engine cannot observe. If we pass the event through
        // without resetting, the engine keeps stale composing state and the next
        // keystroke diffs against text that no longer matches the screen → ghost
        // characters. Reset so the engine matches the now-empty (or truncated)
        // screen, then let the OS perform the deletion natively.
        if type == .keyDown && keyCode == 51
            && (flags.contains(.maskCommand) || flags.contains(.maskControl)) {
            _engine.reset()
        }

        if (flags.contains(.maskCommand) || flags.contains(.maskControl) ||
           flags.contains(.maskAlternate) || flags.contains(.maskSecondaryFn)) && !isOptionBackspace {
            return Unmanaged.passRetained(event)
        }

        // Pass through Command keys themselves
        if keyCode == 55 || keyCode == 54 {
            return Unmanaged.passRetained(event)
        }

        // In English mode, pass everything through
        guard inputMethodManager.isVietnamese else {
            return Unmanaged.passRetained(event)
        }

        // Auto-disable on non-Latin keyboard layout
        if UserDefaults.standard.bool(forKey: DefaultsKey.autoDisableOnNonLatinLayout),
           layoutMonitor.isNonLatinLayout {
            // Pass through when non-Latin layout is active (CJK, Cyrillic, etc.)
            return Unmanaged.passRetained(event)
        }

        // --- AX mode (Spotlight, etc.) ---
        if isAXApp {
            return handleAXEvent(type: type, keyCode: keyCode, event: event)
        }

        // --- Backspace ---
        if keyCode == 51 {
            // Always pass keyUp through so the OS sees the full key cycle
            if type == .keyUp {
                perfEnd("backspace-keyup", keyCode: keyCode, app: app)
                return Unmanaged.passRetained(event)
            }

            // Option+Backspace: let OS handle word deletion, just reset engine state
            if isOptionBackspace {
                // The OS deletes a whole word natively, which the engine cannot
                // observe. Reset unconditionally (not only when composing) so any
                // V-C-V auto-committed text is also dropped — otherwise the next
                // keystroke diffs against stale state and leaks ghost characters.
                _engine.reset()
                // Pass through to let OS handle the word deletion
                perfEnd("backspace-option", keyCode: keyCode, app: app)
                return Unmanaged.passRetained(event)
            }

            let (bs, out) = _engine.backspace()
            #if DEBUG
            let composingBs = _engine.currentOutput()
            let committedBs = _engine.committedText()
            let rawBs = _engine.rawChars()
            print("[UVieKey] BACKSPACE keyCode=\(keyCode) bs=\(bs) out='\(out)' composing='\(composingBs)' committed='\(committedBs)' raw='\(rawBs)' isComposing=\(_engine.isComposing) compound=\(isCompoundApp) chromium=\(isChromium)")
            #endif
            if bs == 0 && out.isEmpty && !_engine.isComposing {
                // Not composing - let OS handle it
                perfEnd("backspace-os", keyCode: keyCode, app: app)
                return Unmanaged.passRetained(event)
            }
            // Debug: log if engine is composing but backspace returned empty (shouldn't happen)
            if bs == 0 && out.isEmpty && _engine.isComposing {
                print("⚠️ EventTap: Engine isComposing but backspace returned empty")
            }

            if bs > 0 {
                if isCompoundApp {
                    applyCompoundBackspaces(bs: bs, out: out)
                } else {
                    applyBackspaces(bs)
                }
            }
            postText(out)
            perfEnd("backspace", keyCode: keyCode, app: app)
            return nil
        }

        // --- Space ---
        if keyCode == 49 {
            if type == .keyUp {
                perfEnd("space-keyup", keyCode: keyCode, app: app)
                return Unmanaged.passRetained(event)
            }
            if type == .keyDown {
                // Check for macro expansion first
                if macroManager.isEnabled() {
                    // Get the current text (committed + composing)
                    let currentText = getCurrentText()
                    if let expansion = macroManager.findExpansion(for: currentText) {
                        // Backspace the abbreviation
                        let abbreviationLength = currentText.count
                        
                        // Use the engine's commit to properly backspace first
                        let (bs, _) = _engine.commit()
                        
                        if bs > 0 {
                            if isCompoundApp {
                                applyCompoundBackspaces(bs: bs, out: "")
                            } else {
                                applyBackspaces(bs)
                            }
                        }

                        // Additional backspace if engine didn't catch all
                        if abbreviationLength > bs {
                            let remaining = abbreviationLength - bs
                            applyBackspaces(remaining)
                        }

                        // Insert the expansion
                        postText(expansion)
                        _engine.reset()
                        perfEnd("space-macro", keyCode: keyCode, app: app)
                        return nil  // Consume the space event
                    }
                }

                let (bs, out) = _engine.commit()
                if bs > 0 {
                    if isCompoundApp {
                        applyCompoundBackspaces(bs: bs, out: out)
                    } else {
                        applyBackspaces(bs)
                    }
                }
                postText(out)

                // Check if the committed text ends with sentence delimiter
                // Note: Space after .!? doesn't make it a new sentence start yet
                // The actual .!? character will set isAtSentenceStart when typed
            }
            perfEnd("space", keyCode: keyCode, app: app)
            return Unmanaged.passRetained(event)
        }

        // --- Break keys (Enter, Tab, Arrows, etc.) ---
        if isBreakKey(keyCode) {
            if type == .keyUp {
                perfEnd("break-keyup", keyCode: keyCode, app: app)
                return Unmanaged.passRetained(event)
            }
            if type == .keyDown {
                // Check for macro expansion first
                if macroManager.isEnabled() {
                    let currentText = getCurrentText()
                    if let expansion = macroManager.findExpansion(for: currentText) {
                        // Backspace the abbreviation
                        let abbreviationLength = currentText.count

                        // Use the engine's commit to properly backspace first
                        let (bs, _) = _engine.commit()

                        if bs > 0 {
                            if isCompoundApp {
                                applyCompoundBackspaces(bs: bs, out: "")
                            } else {
                                applyBackspaces(bs)
                            }
                        }

                        // Additional backspace if engine didn't catch all
                        if abbreviationLength > bs {
                            let remaining = abbreviationLength - bs
                            applyBackspaces(remaining)
                        }

                        // Insert the expansion
                        postText(expansion)
                        _engine.reset()

                        // Enter/Return after macro expansion starts new sentence
                        updateSentenceStartStateForBreakKey(keyCode)

                        perfEnd("break-macro", keyCode: keyCode, app: app)
                        return nil  // Consume the break key event
                    }
                }

                let (bs, out) = _engine.commit()
                if bs > 0 {
                    if isCompoundApp {
                        applyCompoundBackspaces(bs: bs, out: out)
                    } else {
                        applyBackspaces(bs)
                    }
                }
                postText(out)

                // Enter/Return starts a new sentence
                updateSentenceStartStateForBreakKey(keyCode)
            }
            perfEnd("break", keyCode: keyCode, app: app)
            return Unmanaged.passRetained(event)
        }

        // --- Regular character keys ---
        if type == .keyUp {
            perfEnd("char-keyup", keyCode: keyCode, app: app)
            return nil  // Suppress original keyUp; we already sent synthetic
        }

        guard let firstChar = characterFromCGEvent(event) else {
            perfEnd("char-pass", keyCode: keyCode, app: app)
            return Unmanaged.passRetained(event)
        }

        // Apply auto-capitalize if at sentence start
        let transformedChar = applyAutoCapitalize(to: firstChar)

        let (bs, out) = _engine.feed(char: transformedChar)
        Logger.shared.keystroke("feed char='\(transformedChar)' keyCode=\(keyCode) bs=\(bs) out='\(out)' compound=\(isCompoundApp) chromium=\(isChromium)")
        #if DEBUG
        let composingFeed = _engine.currentOutput()
        let committedFeed = _engine.committedText()
        let rawFeed = _engine.rawChars()
        print("[UVieKey] FEED char='\(transformedChar)' keyCode=\(keyCode) bs=\(bs) out='\(out)' composing='\(composingFeed)' committed='\(committedFeed)' raw='\(rawFeed)' compound=\(isCompoundApp) chromium=\(isChromium)")
        #endif

        // Update sentence start state based on what was typed
        updateSentenceStartState(after: firstChar)
        if bs > 0 {
            if isCompoundApp {
                applyCompoundBackspaces(bs: bs, out: out)
            } else {
                applyBackspaces(bs)
            }
        }
        postText(out)
        perfEnd("char", keyCode: keyCode, app: app)
        return nil
    }

    // MARK: - AX Mode (Accessibility text injection)

    private func handleAXEvent(type: CGEventType, keyCode: Int64, event: CGEvent) -> Unmanaged<CGEvent>? {
        // Auto-disable on non-Latin keyboard layout for AX mode
        if UserDefaults.standard.bool(forKey: DefaultsKey.autoDisableOnNonLatinLayout),
           layoutMonitor.isNonLatinLayout {
            return Unmanaged.passRetained(event)
        }

        // Backspace
        if keyCode == 51 {
            if type == .keyUp {
                return Unmanaged.passRetained(event)
            }
            let success = axInjector.backspace()
            return success ? nil : Unmanaged.passRetained(event)
        }

        // Space - commit and pass through
        if keyCode == 49 {
            if type == .keyUp {
                return Unmanaged.passRetained(event)
            }
            axInjector.commit()
            return Unmanaged.passRetained(event)
        }

        // Break keys - commit and pass through
        if isBreakKey(keyCode) {
            if type == .keyUp {
                return Unmanaged.passRetained(event)
            }
            axInjector.commit()
            return Unmanaged.passRetained(event)
        }

        // Regular character keys
        if type == .keyUp {
            return nil  // Suppress original keyUp
        }

        guard let firstChar = characterFromCGEvent(event) else {
            return Unmanaged.passRetained(event)
        }

        let success = axInjector.feed(char: firstChar)
        return success ? nil : Unmanaged.passRetained(event)
    }

    private func characterFromCGEvent(_ event: CGEvent) -> Character? {
        // Use `.characters` (not `.charactersIgnoringModifiers`) so that
        // Shift-held key events (e.g. Shift+A → 'A') preserve uppercase.
        if let nsEvent = NSEvent(cgEvent: event),
           let chars = nsEvent.characters,
           let firstChar = chars.first {
            return firstChar
        }
        var length: Int = 0
        var buffer = [UniChar](repeating: 0, count: 4)
        event.keyboardGetUnicodeString(maxStringLength: 4, actualStringLength: &length, unicodeString: &buffer)
        guard length > 0 else { return nil }
        return String(utf16CodeUnits: buffer, count: length).first
    }

    // MARK: - Auto Capitalize Helpers

    /// Check if character is a sentence delimiter (. ! ?)
    private func isSentenceDelimiter(_ char: Character) -> Bool {
        return char == "." || char == "!" || char == "?"
    }

    /// Transform a character to uppercase if auto-capitalize is enabled and at sentence start
    private func applyAutoCapitalize(to char: Character) -> Character {
        let shouldCapitalize = UserDefaults.standard.bool(forKey: DefaultsKey.uppercaseFirstChar)
        guard shouldCapitalize && isAtSentenceStart else { return char }

        // Only capitalize alphabetic characters
        guard char.isLetter else { return char }

        // Mark that we've processed the first character of sentence
        isAtSentenceStart = false
        return char.uppercased().first ?? char
    }

    /// Update sentence start state based on the key that was just typed
    private func updateSentenceStartState(after char: Character) {
        if isSentenceDelimiter(char) {
            isAtSentenceStart = true
        } else if char.isLetter || char.isNumber {
            // After typing a letter/number, we're no longer at sentence start
            isAtSentenceStart = false
        }
        // Space and other chars don't change state
    }

    /// Update sentence start state for break keys (Enter, etc.)
    private func updateSentenceStartStateForBreakKey(_ keyCode: Int64) {
        // Enter/Return starts a new sentence
        if keyCode == 36 || keyCode == 76 {  // 36 = Return, 76 = Enter (numpad)
            isAtSentenceStart = true
        }
    }

    // MARK: - Synthetic Output

    /// Send backspaces for compound apps (Safari, Notes, Chrome, Comet, Atlas, etc.).
    ///
    /// Strategy:
    /// - Send an empty-char sentinel (U+202F) to dismiss the autocomplete dropdown
    ///   when bs > 1 (multi-char replace / V-C-V split). For bs == 1 the dropdown
    ///   hasn't rendered at normal typing speed, so the sentinel is skipped.
    /// - For Chromium browsers (Chrome, Comet, Atlas, Brave, Edge, Arc, Vivaldi):
    ///   the omnibox autocomplete swallows synthetic backspaces when there is
    ///   replacement text, causing duplicate characters (e.g. "tow" → "toơ"
    ///   instead of "tơ"). Shift+Left selection + overwrite avoids this because
    ///   the selection is replaced atomically by the subsequent postText. We
    ///   only use selection when `out` is non-empty (replace case); pure
    ///   deletions (out empty) use plain backspaces which work fine.
    private func applyCompoundBackspaces(bs: Int, out: String) {
        let needsEmptyChar = bs > 1
        if needsEmptyChar {
            sendEmptyCharacter()
        }
        let adjustedBs = bs + (needsEmptyChar ? 1 : 0)
        if isChromium && !out.isEmpty {
            // Chromium omnibox replace: select then overwrite to avoid dup.
            applySelectionBackspaces(adjustedBs)
        } else {
            // Non-Chromium or pure deletion: plain backspaces.
            applyBackspaces(adjustedBs)
        }
    }

    /// Standard backspaces.
    private func applyBackspaces(_ count: Int) {
        guard let eventSource, count > 0 else { return }
        perfNoteEvent(2 * count)
        for _ in 0..<count {
            let down = CGEvent(keyboardEventSource: eventSource, virtualKey: 51, keyDown: true)
            down?.setIntegerValueField(.eventSourceStateID, value: syntheticTag)
            down?.post(tap: .cghidEventTap)
            let up = CGEvent(keyboardEventSource: eventSource, virtualKey: 51, keyDown: false)
            up?.setIntegerValueField(.eventSourceStateID, value: syntheticTag)
            up?.post(tap: .cghidEventTap)
        }
    }

    /// Shift+Left Arrow selection used for apps where synthetic backspace causes
    /// duplicate characters. The caller must post the replacement text afterward.
    private func applySelectionBackspaces(_ count: Int) {
        guard let eventSource, count > 0 else { return }
        perfNoteEvent(2 * count)
        for _ in 0..<count {
            let down = CGEvent(keyboardEventSource: eventSource, virtualKey: 123, keyDown: true)
            down?.flags = .maskShift
            down?.setIntegerValueField(.eventSourceStateID, value: syntheticTag)
            down?.post(tap: .cghidEventTap)
            let up = CGEvent(keyboardEventSource: eventSource, virtualKey: 123, keyDown: false)
            up?.flags = .maskShift
            up?.setIntegerValueField(.eventSourceStateID, value: syntheticTag)
            up?.post(tap: .cghidEventTap)
        }
    }

    /// Send U+202F (Narrow No-Break Space) to invalidate autocomplete dropdown.
    private func sendEmptyCharacter() {
        guard let eventSource else { return }
        perfNoteEvent(2)
        let emptyChar: UniChar = 0x202F
        let down = CGEvent(keyboardEventSource: eventSource, virtualKey: 0, keyDown: true)
        down?.setIntegerValueField(.eventSourceStateID, value: syntheticTag)
        down?.keyboardSetUnicodeString(stringLength: 1, unicodeString: [emptyChar])
        down?.post(tap: .cghidEventTap)
        let up = CGEvent(keyboardEventSource: eventSource, virtualKey: 0, keyDown: false)
        up?.setIntegerValueField(.eventSourceStateID, value: syntheticTag)
        up?.post(tap: .cghidEventTap)
    }

    private func postText(_ string: String) {
        guard let eventSource, !string.isEmpty else { return }
        perfNoteEvent(1)
        let utf16 = Array(string.utf16)
        guard !utf16.isEmpty else { return }
        // Only post keyDown — apps render text on keyDown; the synthetic keyUp
        // is unnecessary for text input and doubles the event count, amplifying
        // the backspace-then-insert flicker on every diff replace.
        let down = CGEvent(keyboardEventSource: eventSource, virtualKey: 0, keyDown: true)
        down?.setIntegerValueField(.eventSourceStateID, value: syntheticTag)
        down?.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)
        down?.post(tap: .cghidEventTap)
    }

    // MARK: - Hotkey

    /// Detects a "Fn tap" (press-and-release with no other keys) and toggles
    /// the input method. Returns `true` when the event was consumed by the
    /// hotkey system; otherwise returns `false` so the caller can continue
    /// normal processing.
    private func handleHotkey(type: CGEventType, event: CGEvent) -> Bool {
        guard UserDefaults.standard.bool(forKey: DefaultsKey.inputMethodHotkeyEnabled) else { return false }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags
        let fnNow = flags.contains(.maskSecondaryFn)

        // ---- Modern Mac keyboards: Fn/Globe sends keyDown/keyUp (keyCode 179) ----
        if keyCode == 179 {
            if type == .keyDown {
                fnIsDown = true
                fnWasTap = true
                fnHandledByKeyEvent = true
                // Suppress so the emoji picker doesn't fire
                return true
            }
            if type == .keyUp {
                fnIsDown = false
                if fnWasTap {
                    triggerToggle()
                }
                fnHandledByKeyEvent = false
                fnWasTap = false
                // Suppress so the emoji picker doesn't fire
                return true
            }
        }

        // ---- Older keyboards / fallback: detect via flagsChanged ----
        if type == .flagsChanged {
            if fnNow && !fnIsDown {
                // Fn just pressed
                fnIsDown = true
                fnWasTap = true
                // Suppress the modifier-change event
                return true
            }

            if !fnNow && fnIsDown {
                // Fn just released
                fnIsDown = false
                if fnWasTap {
                    triggerToggle()
                }
                fnWasTap = false
                // Suppress the modifier-change event
                return true
            }
        }

        // Any real keypress while Fn is held cancels the tap.
        if (type == .keyDown || type == .keyUp) && fnIsDown && keyCode != 179 {
            fnWasTap = false
        }

        return false
    }

    private func triggerToggle() {
        // Debounce: prevent double-toggle when keyboard sends both flagsChanged AND keyCode 179
        let now = Date()
        if let last = lastToggleTime, now.timeIntervalSince(last) < 0.2 {
            return
        }
        lastToggleTime = now

        DispatchQueue.main.async { [self] in
            inputMethodManager.toggle()
            NSSound.beep()
        }
    }
}
