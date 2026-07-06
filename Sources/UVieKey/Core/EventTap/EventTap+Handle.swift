import Cocoa

// MARK: - EventTap - Main event dispatcher

extension EventTap {
    /// Main event-tap callback. Dispatches to specialized handlers based on
    /// event type and key code.
    func handle(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // Re-enable the tap if the system disabled it (callback timeout,
        // system sleep). Don't re-enable if we intentionally disabled it
        // for an excluded app — that would defeat the purpose.
        // kCGEventTapDisabledByTimeout = 0xFFFFFFFE,
        // kCGEventTapDisabledByUserInput = 0xFFFFFFFF
        let rawType = type.rawValue
        if rawType == 0xFFFFFFFE || rawType == 0xFFFFFFFF {
            if let tap, !lastExcludedState {
                CGEvent.tapEnable(tap: tap, enable: true)
                // Reset Fn tracking state — the tap was disabled (timeout or
                // user input), so any Fn release events were missed. Stale
                // fnIsDown could cause the next non-Fn flagsChanged (Cmd,
                // Shift, Option) to be misidentified as an Fn release.
                fnIsDown = false
                fnWasTap = false
                Logger.shared.warn("EventTap: tap was disabled (rawType=\(rawType)), re-enabled, Fn state reset")
            }
            return Unmanaged.passRetained(event)
        }

        // Skip our own synthetic events
        if event.getIntegerValueField(.eventSourceStateID) == syntheticTag {
            return Unmanaged.passRetained(event)
        }

        // Bypass system UI apps
        if shouldBypass {
            return Unmanaged.passRetained(event)
        }

        // Safety net: the CGEventTap is disabled entirely when the user is
        // in an excluded app (see `updateExcludedTapState` in EventTap.swift).
        // If a keystroke arrives before the tap was disabled (very fast app
        // switch), pass it through untouched.
        if isExcludedApp {
            if !lastExcludedState {
                _engine.reset()
                lastExcludedState = true
            }
            return Unmanaged.passRetained(event)
        } else if lastExcludedState {
            lastExcludedState = false
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
        var app = appDetector.bundleID
        perfBegin()

        // Spotlight and other system UI overlays don't trigger
        // didActivateApplicationNotification, so bundleID stays stale as
        // the previous app. If the current bundleID isn't classified,
        // do a fresh AX lookup on every keyDown. AX call is ~5ms and
        // only runs for unclassified apps — classified apps (Notes,
        // Safari, Chromium) skip it.
        if type == .keyDown,
           !cachedExcludedApps.contains(app),
           !cachedCompoundApps.contains(app),
           !cachedChromiumApps.contains(app),
           !axApps.contains(app) {
            appDetector.refreshBundleID()
            app = appDetector.bundleID
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

        // Set needsAXRefresh on Cmd key down so the next keyDown after
        // Cmd+Space (Spotlight) does a fresh AX bundleID lookup. Spotlight
        // doesn't fire didActivateApplicationNotification, so without this
        // the bundleID stays stale as the previous app and AX mode never
        // activates. Cmd key comes as .flagsChanged, handled above.
        if (flags.contains(.maskCommand) || flags.contains(.maskControl) ||
           flags.contains(.maskAlternate) || flags.contains(.maskSecondaryFn)) && !isOptionBackspace {
            return Unmanaged.passRetained(event)
        }

        // Pass through Command keys themselves.
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
            return handleBackspace(type: type, keyCode: keyCode, isOptionBackspace: isOptionBackspace, app: app, event: event)
        }

        // --- Space ---
        if keyCode == 49 {
            return handleSpace(type: type, keyCode: keyCode, app: app, event: event)
        }

        // --- Break keys (Enter, Tab, Arrows, etc.) ---
        if isBreakKey(keyCode) {
            return handleBreakKey(type: type, keyCode: keyCode, app: app, event: event)
        }

        // --- Regular character keys ---
        return handleCharacterKey(type: type, keyCode: keyCode, app: app, event: event)
    }

    // MARK: - Backspace handler

    private func handleBackspace(type: CGEventType, keyCode: Int64, isOptionBackspace: Bool, app: String, event: CGEvent) -> Unmanaged<CGEvent>? {
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
        if bs == 0 && out.isEmpty && !_engine.isComposing {
            // Not composing - let OS handle it
            perfEnd("backspace-os", keyCode: keyCode, app: app)
            return Unmanaged.passRetained(event)
        }

        // CGEvent path: selection-based for compound apps (no flicker),
        // plain backspace for regular apps.
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

    // MARK: - Space handler

    private func handleSpace(type: CGEventType, keyCode: Int64, app: String, event: CGEvent) -> Unmanaged<CGEvent>? {
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
                    applyMacroExpansion(expansion: expansion, currentText: currentText)
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

    // MARK: - Break key handler

    private func handleBreakKey(type: CGEventType, keyCode: Int64, app: String, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .keyUp {
            perfEnd("break-keyup", keyCode: keyCode, app: app)
            return Unmanaged.passRetained(event)
        }
        if type == .keyDown {
            // Arrow keys move the cursor within text. The diff engine tracks
            // text only at the insertion point; once the cursor moves, our
            // on-screen model is invalid. Reset (don't commit) so stale
            // composing state cannot be applied at the new cursor position.
            // Enter/Tab/Escape/etc. are true word boundaries → commit.
            if isArrowKey(keyCode) {
                _engine.reset()
                perfEnd("break-arrow", keyCode: keyCode, app: app)
                return Unmanaged.passRetained(event)
            }

            // Check for macro expansion first
            if macroManager.isEnabled() {
                let currentText = getCurrentText()
                if let expansion = macroManager.findExpansion(for: currentText) {
                    applyMacroExpansion(expansion: expansion, currentText: currentText)
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

    // MARK: - Regular character handler

    private func handleCharacterKey(type: CGEventType, keyCode: Int64, app: String, event: CGEvent) -> Unmanaged<CGEvent>? {
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

        // Update sentence start state based on what was typed
        updateSentenceStartState(after: firstChar)

        // CGEvent path: selection-based for compound apps (no flicker),
        // plain backspace for regular apps.
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

    // MARK: - Macro expansion helper

    /// Shared macro expansion logic for Space and Break keys.
    /// Backspaces the abbreviation, inserts the expansion, and resets the engine.
    private func applyMacroExpansion(expansion: String, currentText: String) {
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
    }
}
