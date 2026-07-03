import Cocoa

// MARK: - EventTap - AX Mode (Accessibility text injection)

extension EventTap {
    func handleAXEvent(type: CGEventType, keyCode: Int64, event: CGEvent) -> Unmanaged<CGEvent>? {
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

    func characterFromCGEvent(_ event: CGEvent) -> Character? {
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
}
