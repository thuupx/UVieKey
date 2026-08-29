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
        guard fnHotkeyEnabled else { return false }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags
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
            self.inputMethodManager.toggle()
            NSSound.beep()
        }
    }
}
