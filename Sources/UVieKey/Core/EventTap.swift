import Cocoa
import Carbon

// MARK: - App Classification

/// Default apps that need empty-character sentinel before backspace (invalidate autocomplete).
/// Matched by prefix OR exact bundle ID.
private let defaultCompoundApps: Set<String> = [
    "com.apple.Safari",
    "com.apple.Notes",
    "com.apple.TextEdit",
    "com.apple.mail",
    "com.apple.iWork",
    "com.google.Chrome",
    "com.google.Chrome.canary",
    "com.brave.Browser",
    "com.brave.Browser.nightly",
    "com.microsoft.edgemac",
    "com.microsoft.edgemac.Dev",
    "com.microsoft.edgemac.Beta",
    "com.microsoft.Edge.Dev",
    "com.microsoft.Edge",
    "org.chromium.Chromium",
]

/// Get compound apps from UserDefaults (defaults + custom)
private func getCompoundApps() -> Set<String> {
    let custom = UserDefaults.standard.stringArray(forKey: DefaultsKey.customCompoundApps) ?? []
    return Set(defaultCompoundApps).union(Set(custom))
}

/// Apps that need Accessibility text injection instead of CGEventTap.
/// Spotlight and some secure text fields don't accept synthetic key events.
private let axApps: Set<String> = [
    "com.apple.Spotlight",
]

/// Apps that should bypass IME entirely (system UI, lock screen, etc.)
private let bypassApps: Set<String> = [
    "com.apple.loginwindow",
    "com.apple.securityagent",
    "com.apple.ScreenSaver.Engine",
    "com.apple.systemuiserver",
]

/// Default Chromium browsers that need Shift+Left Arrow selection
/// instead of plain backspace (avoids duplicate chars).
private let defaultChromiumBrowsers: Set<String> = [
    "com.google.Chrome",
    "com.google.Chrome.canary",
    "com.brave.Browser",
    "com.brave.Browser.nightly",
    "com.microsoft.edgemac",
    "com.microsoft.edgemac.Dev",
    "com.microsoft.edgemac.Beta",
    "com.microsoft.Edge.Dev",
    "com.microsoft.Edge",
    "org.chromium.Chromium",
    "ai.perplexity.comet",
]

/// Get Chromium browsers from UserDefaults (defaults + custom)
private func getChromiumBrowsers() -> Set<String> {
    let custom = UserDefaults.standard.stringArray(forKey: DefaultsKey.customChromiumApps) ?? []
    return Set(defaultChromiumBrowsers).union(Set(custom))
}

private func checkIsCompoundApp(_ bundleID: String) -> Bool {
    getCompoundApps().contains(bundleID)
}

private func checkIsChromiumBrowser(_ bundleID: String) -> Bool {
    getChromiumBrowsers().contains(bundleID)
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

    /// Auto-capitalize state: track if we're at the start of a sentence
    private var isAtSentenceStart = true

    /// App switch detection: prevent ghost characters from previous app
    private var previousBundleID: String = ""
    private var engineResetObserver: NSObjectProtocol?

    /// Performance logging for keystroke latency (only logs slow / high-event paths).
    private let perfLogHandle: FileHandle? = {
        let path = "/tmp/uviekey_perf.log"
        if !FileManager.default.fileExists(atPath: path) {
            FileManager.default.createFile(atPath: path, contents: nil, attributes: nil)
        }
        guard let handle = FileHandle(forWritingAtPath: path) else { return nil }
        handle.seekToEndOfFile()
        return handle
    }()
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
        guard AccessibilityChecker.isTrusted else {
            print("EventTap: Accessibility not granted")
            return
        }

        appDetector.start()

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
            print("EventTap: Failed to create tap")
            return
        }

        self.tap = newTap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, newTap, 0)
        self.runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: newTap, enable: true)

        DispatchQueue.global(qos: .userInteractive).async {
            CFRunLoopRun()
        }
    }

    func stop() {
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        }
        tap = nil
        runLoopSource = nil
        appDetector.stop()
    }

    // MARK: - Helpers
    
    private func getCurrentText() -> String {
        return _engine.currentOutput()
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
        let line = String(
            format: "[%.3f ms] %@ keyCode=%lld events=%d app=%@",
            elapsedMs, label, keyCode, perfEventCount, app
        )
        perfLog(line)
    }

    private func perfLog(_ message: String) {
        guard let handle = perfLogHandle else { return }
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let line = "\(timestamp) \(message)\n"
        if let data = line.data(using: .utf8) {
            try? handle.write(contentsOf: data)
        }
    }
    
    // MARK: - Settings

    /// Read all engine-relevant settings from UserDefaults and push to the
    /// shared engine. Called on init and whenever defaults change at runtime.
    func applyEngineSettings() {
        let defaults = UserDefaults.standard
        let method = defaults.string(forKey: DefaultsKey.inputMethod) ?? "telex"
        _engine.setInputMethod(method == "vni" ? .vni : .telex)
        _engine.setModernOrthography(defaults.bool(forKey: DefaultsKey.modernOrthography))
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
            #if DEBUG
            let committed = _engine.committedText()
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
                // Simply reset the engine without sending any backspaces ourselves.
                // The OS will handle the word deletion natively.
                // We only need to ensure our internal state is cleared.
                if _engine.isComposing {
                    _engine.reset()
                }
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
                    // Step 1: invalidate autocomplete dropdown with empty char
                    sendEmptyCharacter()
                    // Step 2: Add +1 backspace for compound apps
                    let adjustedBs = bs + 1
                    if isChromium {
                        // Chromium: Shift+Left select then overwrite
                        applySelectionBackspaces(adjustedBs)
                    } else {
                        // Safari/Notes: normal backspace
                        applyBackspaces(adjustedBs)
                    }
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
                                sendEmptyCharacter()
                                let adjustedBs = bs + 1
                                if isChromium {
                                    applySelectionBackspaces(adjustedBs)
                                } else {
                                    applyBackspaces(adjustedBs)
                                }
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
                        sendEmptyCharacter()
                        let adjustedBs = bs + 1
                        if isChromium {
                            applySelectionBackspaces(adjustedBs)
                        } else {
                            applyBackspaces(adjustedBs)
                        }
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
                                sendEmptyCharacter()
                                let adjustedBs = bs + 1
                                if isChromium {
                                    applySelectionBackspaces(adjustedBs)
                                } else {
                                    applyBackspaces(adjustedBs)
                                }
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
                        sendEmptyCharacter()
                        let adjustedBs = bs + 1
                        if isChromium {
                            applySelectionBackspaces(adjustedBs)
                        } else {
                            applyBackspaces(adjustedBs)
                        }
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
                sendEmptyCharacter()
                let adjustedBs = bs + 1
                if isChromium {
                    applySelectionBackspaces(adjustedBs)
                } else {
                    applyBackspaces(adjustedBs)
                }
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

    /// Chromium fix: Shift+Left Arrow to select, then type overwrites.
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
        perfNoteEvent(2)
        let utf16 = Array(string.utf16)
        guard !utf16.isEmpty else { return }
        let down = CGEvent(keyboardEventSource: eventSource, virtualKey: 0, keyDown: true)
        down?.setIntegerValueField(.eventSourceStateID, value: syntheticTag)
        down?.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)
        down?.post(tap: .cghidEventTap)
        let up = CGEvent(keyboardEventSource: eventSource, virtualKey: 0, keyDown: false)
        up?.setIntegerValueField(.eventSourceStateID, value: syntheticTag)
        up?.post(tap: .cghidEventTap)
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
