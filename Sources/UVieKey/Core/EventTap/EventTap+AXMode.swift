import Cocoa

// MARK: - EventTap - AX Mode (Accessibility text injection)

/// The AX-injection surface used by `handleAXEvent`. Production talks to the
/// real Accessibility API via `AXTextInjector`; tests substitute a stub so
/// Spotlight routing can be simulated without AX IPC.
protocol AXTextInjecting: AnyObject {
    func feed(char: Character) -> Bool
    func backspace() -> Bool
    @discardableResult
    func commit() -> Bool
    func reset()
}

extension AXTextInjector: AXTextInjecting {}

extension EventTap {
    func handleAXEvent(type: CGEventType, keyCode: Int64, event: CGEvent) -> Unmanaged<CGEvent>? {
        // Auto-disable on non-Latin keyboard layout for AX mode (flag cached
        // in `applyEngineSettings` — no UserDefaults read on the hot path)
        if autoDisableOnNonLatinLayout,
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

        // Space - commit and pass through (unless macro expansion consumed it)
        if keyCode == 49 {
            if type == .keyUp {
                return Unmanaged.passRetained(event)
            }
            let expanded = axInjector.commit()
            // If a macro was expanded, consume the space to avoid a trailing
            // space after the expanded text. Otherwise pass through so the
            // app inserts the space natively.
            return expanded ? nil : Unmanaged.passRetained(event)
        }

        // Break keys - commit and pass through (unless macro expansion consumed it)
        if isBreakKey(keyCode) {
            if type == .keyUp {
                return Unmanaged.passRetained(event)
            }
            let expanded = axInjector.commit()
            return expanded ? nil : Unmanaged.passRetained(event)
        }

        // Regular character keys
        if type == .keyUp {
            return nil  // Suppress original keyUp
        }

        guard let firstChar = characterFromCGEvent(event) else {
            return Unmanaged.passRetained(event)
        }

        // Apply auto-capitalize if at sentence start (mirrors the CGEvent path)
        let transformedChar = applyAutoCapitalize(to: firstChar)
        updateSentenceStartState(after: firstChar)

        let success = axInjector.feed(char: transformedChar)
        if Logger.shared.keystrokeTraceEnabled {
            Logger.shared.keystroke("axFeed char='\(transformedChar)' success=\(success)")
        }
        return success ? nil : Unmanaged.passRetained(event)
    }

    func characterFromCGEvent(_ event: CGEvent) -> Character? {
        // Direct translation — equivalent to `NSEvent.characters` (which wraps
        // this same call) but without the per-keystroke NSEvent allocation.
        // Shift-held key events preserve uppercase.
        var length: Int = 0
        event.keyboardGetUnicodeString(
            maxStringLength: charBuffer.count,
            actualStringLength: &length,
            unicodeString: &charBuffer
        )
        guard length > 0 else { return nil }
        return String(utf16CodeUnits: charBuffer, count: length).first
    }
}
