import Cocoa

// MARK: - EventTap - Hotkey (Fn tap toggle)

extension EventTap {
    /// Detects a "Fn tap" (press-and-release with no other keys) and toggles
    /// the input method. Returns `true` when the event was consumed by the
    /// hotkey system; otherwise returns `false` so the caller can continue
    /// normal processing.
    ///
    /// **Critical (macOS 15 Bug #14):** `flagsChanged` events are NEVER consumed.
    /// Previously, the Fn `flagsChanged` was suppressed (return true), which:
    /// 1. Broke system-level Fn combinations (Fn+arrow=Home/End, Fn+Backspace=Forward Delete)
    /// 2. Caused stale `fnIsDown` to consume OTHER modifiers' flagsChanged events
    ///    (Cmd/Shift/Option) when Fn was released while the tap was disabled
    ///    (timeout or excluded app), intermittently breaking copy/paste and all
    ///    Cmd/Ctrl/Option shortcuts in apps like Photoshop.
    ///
    /// Now we only track Fn state for tap detection and let all `flagsChanged`
    /// events pass through to the system. The Fn tap toggle still works because
    /// we call `triggerToggle()` on release. Only keyCode 179 (modern Fn/Globe
    /// keyDown/keyUp) is consumed to prevent the emoji picker.
    func handleHotkey(type: CGEventType, event: CGEvent) -> Bool {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags

        if handleCustomHotkey(type: type, keyCode: keyCode, flags: flags, event: event) {
            return true
        }

        guard fnHotkeyEnabled else { return false }

        let fnNow = flags.contains(.maskSecondaryFn)

        // ---- Modern Mac keyboards: Fn/Globe sends keyDown/keyUp (keyCode 179) ----
        // Only this path consumes events — suppress the Globe key action (emoji picker).
        // The accompanying flagsChanged still passes through (handled below), so the
        // system sees the modifier state change for Fn+key combinations.
        if keyCode == 179 {
            if type == .keyDown {
                fnIsDown = true
                fnWasTap = true
                // Suppress so the emoji picker doesn't fire
                return true
            }
            if type == .keyUp {
                fnIsDown = false
                if fnWasTap {
                    triggerToggle()
                }
                fnWasTap = false
                // Suppress so the emoji picker doesn't fire
                return true
            }
        }

        // ---- Older keyboards / fallback: detect via flagsChanged ----
        // IMPORTANT: We track Fn state but do NOT consume the event. Consuming
        // flagsChanged breaks system Fn combinations and risks stale-state bugs
        // where Cmd/Shift/Option flagsChanged events get swallowed.
        if type == .flagsChanged {
            if fnNow && !fnIsDown {
                // Fn just pressed — track state, pass through to system
                fnIsDown = true
                fnWasTap = true
                return false
            }

            if !fnNow && fnIsDown {
                // Fn just released — track state, fire toggle if it was a tap,
                // then pass through to system so Fn+key state is consistent.
                fnIsDown = false
                if fnWasTap {
                    triggerToggle()
                }
                fnWasTap = false
                return false
            }
        }

        // Any real keypress while Fn is held cancels the tap.
        if (type == .keyDown || type == .keyUp) && fnIsDown && keyCode != 179 {
            fnWasTap = false
        }

        return false
    }

    /// Detects the user-configured global toggle shortcut inside the event
    /// tap. The Carbon `RegisterEventHotKey` registration (GlobalHotkeyManager)
    /// stays as a fallback for when the tap is disabled (excluded apps), but
    /// Carbon only fires when the frontmost app reports the key unhandled —
    /// MS Word and other apps with custom text engines consume every keyDown,
    /// so the hotkey never fires there. The tap sees the keyDown before any
    /// app, and a consumed event never reaches Carbon's dispatch, so the two
    /// mechanisms can never double-fire.
    ///
    /// Two binding shapes:
    /// - **Key combo** (keyCode >= 0, e.g. ⌘⇧N): the matching keyDown/keyUp
    ///   is consumed and the toggle fires on keyDown. Only the chord's four
    ///   modifiers are compared — padding flags (`.maskNumericPad`,
    ///   `.maskSecondaryFn`, CapsLock) are ignored — and both events are
    ///   swallowed so the frontmost app never sees a release for a keyDown
    ///   it didn't receive.
    /// - **Modifier-only chord** (keyCode == -1, recorded via the recorder's
    ///   Done button): fires when the recorded modifiers are TAPPED —
    ///   pressed and released with no other key in between. Never consumes
    ///   anything (modifiers must reach the app); any real keyDown cancels
    ///   the pending tap, so app shortcuts like ⌘⇧N keep working.
    ///
    /// Returns `true` when the event belongs to a key-combo binding and was
    /// consumed; modifier-only tracking always returns `false`.
    private func handleCustomHotkey(type: CGEventType, keyCode: Int64, flags: CGEventFlags, event: CGEvent) -> Bool {
        // Require a real binding: an empty flag mask would otherwise match
        // EVERY unmodified press of the key. KeyCode 0 is valid (the A key) —
        // the non-empty flag mask is what distinguishes a real binding from
        // an unset default (both read back as 0 from UserDefaults).
        guard customHotkeyEnabled, !customHotkeyFlags.isEmpty
        else { return false }

        if customHotkeyKeyCode < 0 {
            trackCustomChordTap(type: type, flags: flags)
            return false
        }

        guard keyCode == customHotkeyKeyCode,
              flags.intersection(EventTap.chordModifierMask) == customHotkeyFlags
        else { return false }

        if type == .keyDown {
            // Swallow auto-repeat so holding the chord doesn't toggle the
            // language back and forth on every repeat.
            if event.getIntegerValueField(.keyboardEventAutorepeat) == 0 {
                triggerToggle()
            }
            return true
        }
        return type == .keyUp
    }

    /// Tracks a modifier-only chord tap: the chord arms when the recorded
    /// modifiers are all down (exact match), stays armed through partial
    /// releases (users release keys in any order), and fires the toggle when
    /// every modifier is back up with no key pressed in between. Any real
    /// keyDown/keyUp disarms — the user is typing an app shortcut, not
    /// toggling.
    private func trackCustomChordTap(type: CGEventType, flags: CGEventFlags) {
        if type == .flagsChanged {
            let chord = flags.intersection(EventTap.chordModifierMask)
            if chord.isEmpty {
                if customChordTapArmed {
                    triggerToggle()
                }
                customChordTapArmed = false
            } else if chord == customHotkeyFlags {
                customChordTapArmed = true
            }
            // Non-empty mismatch (chord not yet complete, or partially
            // released): keep the armed state so release order doesn't matter.
        } else if type == .keyDown || type == .keyUp {
            // A real key was pressed while the chord was held — the user is
            // typing an app shortcut (⌘⇧N), not toggling.
            customChordTapArmed = false
        }
    }

    func triggerToggle() {
        // Debounce: prevent double-toggle when keyboard sends both flagsChanged AND keyCode 179
        let now = Date()
        if let last = lastToggleTime, now.timeIntervalSince(last) < 0.2 {
            return
        }
        lastToggleTime = now

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            // Reset the engine BEFORE toggling — stale composing state from
            // the previous language can produce ghost characters when the
            // user starts typing in the new language.
            self._engine.reset()
            self.editCaretBack = 0
            self.inputMethodManager.toggle()
            NSSound.beep()
        }
    }
}
