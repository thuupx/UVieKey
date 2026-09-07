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
                editCaretBack = 0
                invalidateWebContentCache()
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

        // Pass through flags changes. A Cmd/Ctrl/Fn press is a potential
        // app-switch trigger (Cmd+Space → Spotlight, Ctrl+Space input source,
        // Globe key) — arm the one-shot AX refresh so the next keyDown in an
        // unclassified app re-resolves the bundleID. Shift is excluded:
        // Shift presses are common (capital letters) and never switch apps.
        if type == .flagsChanged {
            let flags = event.flags
            if flags.contains(.maskCommand) || flags.contains(.maskControl)
                || flags.contains(.maskSecondaryFn) {
                axRefreshAttempts = EventTap.axRefreshMaxAttempts
            }
            return Unmanaged.passRetained(event)
        }

        // Mouse down/drag starts a new editing session (selection, click, etc.).
        // Reset the engine so stale composing state cannot be applied after the
        // user selects text with the mouse. Also reset auto-capitalize state —
        // clicking into a new text field means we don't know if we're at a
        // sentence start, so default to true (safe for new text fields).
        // A click can also change the focused app without a workspace
        // notification (menu-bar Spotlight icon) — arm the AX refresh.
        //
        // Save isAtSentenceStart before resetting — but ONLY on the initial
        // down: dragged events fire repeatedly during a drag and would
        // overwrite the pre-click value with the already-reset `true`. If
        // this click switches to a different app, handleSentenceStartAcross
        // AppSwitch restores the saved value (the click was an app-switch,
        // not a cursor reposition) and files it under the leaving app in the
        // per-app memory. Without this, clicking to switch back to an app
        // mid-sentence causes the next letter to be incorrectly capitalized.
        if type == .leftMouseDown || type == .rightMouseDown ||
           type == .leftMouseDragged || type == .rightMouseDragged {
            _engine.reset()
            editCaretBack = 0
            invalidateWebContentCache()
            if type == .leftMouseDown || type == .rightMouseDown {
                savedIsAtSentenceStart = isAtSentenceStart
            }
            isAtSentenceStart = true
            axRefreshAttempts = EventTap.axRefreshMaxAttempts
            return Unmanaged.passRetained(event)
        }

        // Only handle keyDown/keyUp
        guard type == .keyDown || type == .keyUp else {
            return Unmanaged.passRetained(event)
        }

        // Discard any saved sentence-start state from a mouse-down. If an app
        // switch had followed the mouse down, observeAppSwitch would have
        // already restored it. Reaching here means no switch occurred (click
        // within the same app), so the reset to `true` stays.
        if type == .keyDown {
            savedIsAtSentenceStart = nil
        }

        // If the CGEventSource is nil (rare, but possible if construction
        // failed), we cannot post synthetic events. Pass everything through
        // to avoid consuming keystrokes that can't be replaced — a lost
        // keystroke is worse than no Vietnamese processing.
        guard eventSource != nil else {
            return Unmanaged.passRetained(event)
        }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags
        var app = appDetector.bundleID
        perfBegin()

        // Spotlight and other system UI overlays don't trigger
        // didActivateApplicationNotification, so bundleID stays stale as
        // the previous app. When a potential app-switch trigger was observed
        // (Cmd/Ctrl/Fn keyDown, mouse down — see `axRefreshAttempts`), spend
        // budgeted attempts on fresh AX lookups. The budget matters for
        // Cmd+Space: the Space keyDown itself spends one attempt while
        // Spotlight is still opening (AX still reports the previous app), so
        // the remaining attempts must keep retrying until the lookup returns
        // a DIFFERENT app — only then is the detection consumed. The AX call
        // is ~1-5ms, so the cost stays bounded at N lookups per trigger.
        if type == .keyDown,
           axRefreshAttempts > 0,
           !cachedExcludedApps.contains(app),
           !cachedCompoundApps.contains(app),
           !cachedChromiumApps.contains(app),
           !axApps.contains(app) {
            appDetector.refreshBundleID()
            let fresh = appDetector.bundleID
            if fresh != app {
                axRefreshAttempts = 0
            } else {
                axRefreshAttempts -= 1
            }
            app = fresh
        }

        // Detect text-selection shortcuts. The diff engine tracks text at the
        // insertion point only; when the user selects text and types over it,
        // our state becomes invalid, so reset the engine.
        if type == .keyDown && isSelectionShortcut(keyCode: keyCode, flags: flags) {
            _engine.reset()
            editCaretBack = 0
            invalidateWebContentCache()
        }

        // Plain Left/Right arrow steps: commit the composing word (it stays
        // on screen) and track the caret offset so typing at a word end
        // re-enters that word (LabanKey-style post-commit editing). This
        // MUST run before the modifier-cursor reset below: real hardware
        // arrow events carry function-key flags (.maskSecondaryFn and
        // .maskNumericPad) even with no modifier held, and that reset would
        // wipe the committed-word history on every arrow press. Only real
        // movement modifiers (Cmd/Ctrl/Option, plus Shift = selection,
        // handled above) still fall through to the reset.
        if type == .keyDown,
           keyCode == 123 || keyCode == 124,
           !flags.contains(.maskCommand), !flags.contains(.maskControl),
           !flags.contains(.maskAlternate), !flags.contains(.maskShift),
           !isAXApp {
            if _engine.isComposing {
                commitAndInject()
            }
            if keyCode == 123 {
                editCaretBack += 1
            } else {
                editCaretBack -= 1
            }
            perfEnd("break-arrow", keyCode: keyCode, app: app)
            return Unmanaged.passRetained(event)
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
        //
        // Forward Delete (keyCode 117) with modifiers has the same problem:
        // Option+Forward Del deletes the next word, Cmd+Forward Del deletes to
        // end of line/paragraph — both invisible to the engine.
        if type == .keyDown
            && (keyCode == 51 || keyCode == 117)
            && (flags.contains(.maskCommand) || flags.contains(.maskControl)) {
            _engine.reset()
            editCaretBack = 0
            invalidateWebContentCache()
        }
        if type == .keyDown
            && keyCode == 117
            && (flags.contains(.maskAlternate) || flags.contains(.maskSecondaryFn)) {
            _engine.reset()
            editCaretBack = 0
            invalidateWebContentCache()
        }

        // Cursor-movement with a movement modifier (Cmd/Ctrl/Option/Fn) jumps
        // the cursor to a position the diff engine cannot track (e.g. Cmd+
        // Arrow to line start/end, Option+Arrow word-by-word, Fn+Arrow =
        // Home/End/Page). Without resetting, the engine keeps stale composing
        // state and the next keystroke applies backspaces/suffix at the wrong
        // cursor position → ghost characters (e.g. typing "kiểu á" then
        // Cmd+Arrow left and continuing inserts stray "as"). Shift+arrows are
        // already handled by isSelectionShortcut above.
        if type == .keyDown
            && (flags.contains(.maskCommand) || flags.contains(.maskControl) ||
                flags.contains(.maskAlternate) || flags.contains(.maskSecondaryFn))
            && isCursorMovementKey(keyCode) {
            _engine.reset()
            editCaretBack = 0
            invalidateWebContentCache()
        }

        // Modifier combos pass through untouched. The Cmd/Ctrl/Fn keyDowns
        // that arm the AX refresh budget arrive as .flagsChanged (handled
        // above) — Spotlight doesn't fire didActivateApplicationNotification,
        // so without that arming the bundleID stays stale as the previous app
        // and AX mode never activates.
        if (flags.contains(.maskCommand) || flags.contains(.maskControl) ||
           flags.contains(.maskAlternate) || flags.contains(.maskSecondaryFn)) && !isOptionBackspace {
            return Unmanaged.passRetained(event)
        }

        // Pass through Command keys themselves.
        if keyCode == 55 || keyCode == 54 {
            return Unmanaged.passRetained(event)
        }

        // In English mode, re-post character keys as synthetic events to
        // suppress the OS autocomplete/autocorrect popup. Real hardware
        // keyDown events trigger the popup; synthetic events from a
        // privateState CGEventSource do not.
        guard inputMethodManager.isVietnamese else {
            return handleEnglishMode(type: type, keyCode: keyCode, event: event)
        }

        // Auto-disable on non-Latin keyboard layout (flag cached in
        // `applyEngineSettings` — no UserDefaults read on the hot path)
        if autoDisableOnNonLatinLayout,
           layoutMonitor.isNonLatinLayout {
            // Reset the engine when switching to a non-Latin layout (CJK,
            // Cyrillic, etc.) — the composing buffer holds Latin keystrokes
            // that no longer match the screen. Without this, switching back
            // to a Latin layout can produce ghost characters.
            _engine.reset()
            editCaretBack = 0
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
            editCaretBack = 0
            // Pass through to let OS handle the word deletion
            perfEnd("backspace-option", keyCode: keyCode, app: app)
            return Unmanaged.passRetained(event)
        }

        let (bs, out) = _engine.backspace()
        if Logger.shared.keystrokeTraceEnabled {
            Logger.shared.keystroke("backspace bs=\(bs) out='\(out)' compound=\(isCompoundApp) chromium=\(isChromium)")
        }
        if bs == 0 && out.isEmpty && !_engine.isComposing {
            // Not composing - let OS handle it. The caret moves 1 char left.
            // At or left of the anchor (editCaretBack >= 0) the deleted char
            // belonged to committed text the engine still remembers, so the
            // history is stale and must be dropped. Right of the anchor
            // (editCaretBack < 0, the normal post-commit position) the
            // deleted char is the commit space or later text — the history
            // stays valid and deleting the space arms editing (offset → 0).
            if editCaretBack >= 0 {
                _engine.reset()
                editCaretBack = 0
            } else {
                editCaretBack += 1
            }
            perfEnd("backspace-os", keyCode: keyCode, app: app)
            return Unmanaged.passRetained(event)
        }

        // CGEvent path: selection-based for compound apps (no flicker),
        // plain backspace for regular apps.
        if bs > 0 {
            if isCompoundApp {
                outputSink.applyCompoundBackspaces(bs: bs, out: out)
            } else {
                outputSink.applyBackspaces(bs)
            }
        }
        outputSink.postText(out)
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

            let wasComposing = _engine.isComposing
            let (bs, out) = _engine.commit()
            if bs > 0 {
                if isCompoundApp {
                    outputSink.applyCompoundBackspaces(bs: bs, out: out)
                } else {
                    outputSink.applyBackspaces(bs)
                }
            }
            outputSink.postText(out)
            // The anchor moves to the just-committed word's end. When the
            // engine was composing, the caret sits 1 right of it (the space);
            // when idle, the caret was already right of the anchor and just
            // moves 1 further right.
            editCaretBack = wasComposing ? -1 : editCaretBack - 1

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
            // Remaining cursor-movement keys (Up/Down/Home/End/PageUp/
            // PageDown) and Tab (keyCode 48) jump lines or move focus —
            // the single-line anchor model is invalid, so reset. Plain
            // Left/Right arrows never reach here: they are intercepted
            // earlier (before the modifier-cursor reset) to keep the
            // committed-word history alive for post-commit editing.
            if isCursorMovementKey(keyCode) || keyCode == 48 {
                _engine.reset()
                editCaretBack = 0
                invalidateWebContentCache()
                perfEnd("break-arrow", keyCode: keyCode, app: app)
                return Unmanaged.passRetained(event)
            }

            // Escape cancels the composing word — reset without committing,
            // matching user expectation that Esc discards in-progress input.
            if keyCode == 53 {
                _engine.reset()
                editCaretBack = 0
                perfEnd("break-esc", keyCode: keyCode, app: app)
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

            let wasComposing = _engine.isComposing
            commitAndInject()
            // The anchor moves to the just-committed word's end. When the
            // engine was composing, the caret sits 1 right of it (the break
            // char); when idle, the caret keeps its offset and moves 1
            // further right past the inserted break char.
            editCaretBack = wasComposing ? -1 : editCaretBack - 1

            // Enter/Return starts a new sentence
            updateSentenceStartStateForBreakKey(keyCode)
        }
        perfEnd("break", keyCode: keyCode, app: app)
        return Unmanaged.passRetained(event)
    }

    /// Commit the composing word and inject the resulting diff (the same
    /// output path as a normal keystroke). Used by Space, break keys and the
    /// Left/Right arrow commit-before-step-back flow.
    private func commitAndInject() {
        let (bs, out) = _engine.commit()
        if bs > 0 {
            if isCompoundApp {
                outputSink.applyCompoundBackspaces(bs: bs, out: out)
            } else {
                outputSink.applyBackspaces(bs)
            }
        }
        outputSink.postText(out)
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

        // Post-commit editing (LabanKey-style): the caret sits at the end of
        // a committed word (editCaretBack >= 0) and the user types a key —
        // re-enter that word with the key appended and re-render it in place.
        // The engine walks its committed-word history and only fires when
        // caretBack exactly matches a word-end boundary (0 = newest word,
        // + rendered_len + 1 per older word); off-boundary carets (mid-word,
        // double spaces, unseen jumps) decline and the key feeds normally.
        // Typing at caretBack < 0 (right of the newest word, the normal
        // position after a commit space) types a fresh word without
        // disturbing the history.
        if editCommittedEnabled, !isAXApp, editCaretBack >= 0, !_engine.isComposing,
           let (bs, out) = _engine.editAt(caretBack: editCaretBack, char: transformedChar) {
            if Logger.shared.keystrokeTraceEnabled {
                Logger.shared.keystroke("edit-at \(editCaretBack) char='\(transformedChar)' bs=\(bs) out='\(out)' app=\(app)")
            }
            updateSentenceStartState(after: firstChar)
            if bs > 0 {
                if isCompoundApp {
                    outputSink.applyCompoundBackspaces(bs: bs, out: out)
                } else {
                    outputSink.applyBackspaces(bs)
                }
            }
            outputSink.postText(out)
            // The anchor moves to the edited word's end, which is where the
            // caret now sits.
            editCaretBack = 0
            perfEnd("char-edit", keyCode: keyCode, app: app)
            return nil
        }
        if editCommittedEnabled, !isAXApp, editCaretBack > 0 {
            // Off-boundary typing inside earlier text invalidates the
            // committed-word history.
            _engine.reset()
            editCaretBack = 0
        }

        let (bs, out) = _engine.feed(char: transformedChar)
        // Typing right of the anchor (editCaretBack < 0) starts a fresh word
        // after it; each char moves the caret 1 further from the anchor. At
        // or left of the anchor the offset was just re-anchored to 0 above.
        if editCaretBack < 0 {
            editCaretBack -= 1
        }
        // Gate the whole trace call — when trace is off (the common case) the
        // string interpolation and the isCompoundApp/isChromium Set lookups
        // must not run. `keystrokeTraceEnabled` is a cached flag (Logger).
        if Logger.shared.keystrokeTraceEnabled {
            Logger.shared.keystroke("feed char='\(transformedChar)' keyCode=\(keyCode) bs=\(bs) out='\(out)' app=\(app) compound=\(isCompoundApp) chromium=\(isChromium)")
        }

        // Update sentence start state based on what was typed
        updateSentenceStartState(after: firstChar)

        // CGEvent path: selection-based for compound apps (no flicker),
        // plain backspace for regular apps.
        if bs > 0 {
            if isCompoundApp {
                outputSink.applyCompoundBackspaces(bs: bs, out: out)
            } else {
                outputSink.applyBackspaces(bs)
            }
        }
        outputSink.postText(out)
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
                outputSink.applyCompoundBackspaces(bs: bs, out: "")
            } else {
                outputSink.applyBackspaces(bs)
            }
        }

        // Additional backspace if engine didn't catch all
        if abbreviationLength > bs {
            let remaining = abbreviationLength - bs
            outputSink.applyBackspaces(remaining)
        }

        // Insert the expansion
        outputSink.postText(expansion)
        _engine.reset()
        editCaretBack = 0
    }

    // MARK: - English mode handler

    /// In English mode, re-post character keys as synthetic events to suppress
    /// the OS autocomplete/autocorrect popup. Real hardware keyDown events
    /// trigger the popup; synthetic events from a privateState CGEventSource
    /// do not.
    ///
    /// Non-character keys (backspace, space, arrows, function keys) pass
    /// through naturally — they don't trigger the autocomplete popup, and
    /// re-posting them could break special key handling.
    private func handleEnglishMode(type: CGEventType, keyCode: Int64, event: CGEvent) -> Unmanaged<CGEvent>? {
        // Non-character keys pass through naturally.
        if keyCode == 51 || keyCode == 49 || isBreakKey(keyCode) {
            return Unmanaged.passRetained(event)
        }

        // Character keys: consume the real event and re-post as synthetic.
        if type == .keyUp {
            // Suppress the original keyUp — the synthetic keyDown already
            // produced the visible character.
            return nil
        }

        guard let firstChar = characterFromCGEvent(event) else {
            return Unmanaged.passRetained(event)
        }

        // Re-post the same character as a synthetic event.
        outputSink.postText(String(firstChar))
        return nil
    }
}
