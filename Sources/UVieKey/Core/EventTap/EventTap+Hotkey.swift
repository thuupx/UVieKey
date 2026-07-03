import Cocoa

// MARK: - EventTap - Hotkey (Fn tap toggle)

extension EventTap {
    /// Detects a "Fn tap" (press-and-release with no other keys) and toggles
    /// the input method. Returns `true` when the event was consumed by the
    /// hotkey system; otherwise returns `false` so the caller can continue
    /// normal processing.
    func handleHotkey(type: CGEventType, event: CGEvent) -> Bool {
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

    func triggerToggle() {
        // Debounce: prevent double-toggle when keyboard sends both flagsChanged AND keyCode 179
        let now = Date()
        if let last = lastToggleTime, now.timeIntervalSince(last) < 0.2 {
            return
        }
        lastToggleTime = now

        DispatchQueue.main.async { [weak self] in
            self?.inputMethodManager.toggle()
            NSSound.beep()
        }
    }
}
