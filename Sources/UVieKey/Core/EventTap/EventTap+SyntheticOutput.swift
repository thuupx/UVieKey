import Cocoa

// MARK: - EventTap - Synthetic Output

extension EventTap {
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
    func applyCompoundBackspaces(bs: Int, out: String) {
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
    func applyBackspaces(_ count: Int) {
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
    func applySelectionBackspaces(_ count: Int) {
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
    func sendEmptyCharacter() {
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
