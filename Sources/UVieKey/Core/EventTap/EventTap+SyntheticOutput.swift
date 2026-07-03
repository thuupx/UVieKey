import Cocoa

// MARK: - EventTap - Synthetic Output

extension EventTap {
    /// Send backspaces for compound apps (Safari, Notes, Chrome, Comet, Atlas, etc.).
    ///
    /// Strategy:
    /// - When replacing text (out is non-empty), use Shift+Left selection +
    ///   overwrite for ALL compound apps. This is atomic — the selection is
    ///   replaced by the subsequent postText in a single operation, eliminating
    ///   the "delete then insert" flicker that plain backspaces cause.
    ///   The empty-char sentinel is NOT needed with selection-based delete
    ///   because selecting text doesn't trigger autocomplete dropdowns.
    /// - For pure deletions (out is empty), use plain backspaces with the
    ///   empty-char sentinel when bs > 1 to dismiss autocomplete.
    func applyCompoundBackspaces(bs: Int, out: String) {
        if !out.isEmpty {
            // Replace case: selection-based delete is atomic (no flicker).
            // Shift+Left selects the text without deleting it, then postText
            // replaces the selection in one operation.
            applySelectionBackspaces(bs)
        } else {
            // Pure deletion: plain backspaces + sentinel for autocomplete.
            let needsEmptyChar = bs > 1
            if needsEmptyChar {
                sendEmptyCharacter()
            }
            let adjustedBs = bs + (needsEmptyChar ? 1 : 0)
            applyBackspaces(adjustedBs)
        }
    }

    /// Standard backspaces.
    ///
    /// Only posts keyDown — the synthetic keyUp is unnecessary for deletion
    /// and doubles the event count, amplifying the backspace-then-insert
    /// flicker on every diff replace. Apps process the delete on keyDown.
    func applyBackspaces(_ count: Int) {
        guard let eventSource, count > 0 else { return }
        perfNoteEvent(count)
        for _ in 0..<count {
            let down = CGEvent(keyboardEventSource: eventSource, virtualKey: 51, keyDown: true)
            down?.setIntegerValueField(.eventSourceStateID, value: syntheticTag)
            down?.post(tap: .cghidEventTap)
        }
    }

    /// Shift+Left Arrow selection used for apps where synthetic backspace causes
    /// duplicate characters. The caller must post the replacement text afterward.
    ///
    /// Only posts keyDown — same rationale as applyBackspaces.
    func applySelectionBackspaces(_ count: Int) {
        guard let eventSource, count > 0 else { return }
        perfNoteEvent(count)
        for _ in 0..<count {
            let down = CGEvent(keyboardEventSource: eventSource, virtualKey: 123, keyDown: true)
            down?.flags = .maskShift
            down?.setIntegerValueField(.eventSourceStateID, value: syntheticTag)
            down?.post(tap: .cghidEventTap)
        }
    }

    /// Send U+202F (Narrow No-Break Space) to invalidate autocomplete dropdown.
    ///
    /// Only posts keyDown — same rationale as applyBackspaces.
    func sendEmptyCharacter() {
        guard let eventSource else { return }
        perfNoteEvent(1)
        let emptyChar: UniChar = 0x202F
        let down = CGEvent(keyboardEventSource: eventSource, virtualKey: 0, keyDown: true)
        down?.setIntegerValueField(.eventSourceStateID, value: syntheticTag)
        down?.keyboardSetUnicodeString(stringLength: 1, unicodeString: [emptyChar])
        down?.post(tap: .cghidEventTap)
    }

    func postText(_ string: String) {
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
}
