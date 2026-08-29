import Cocoa
import ApplicationServices

/// Injects text via Accessibility API (AXUIElement) instead of CGEventTap.
/// Used for apps where synthetic key events don't work (Spotlight, some secure fields).
///
/// Shares the same `EngineBridge` instance as `EventTap` so that configuration
/// (input method, quick modes, modern orthography) is always consistent.
final class AXTextInjector {
    private let engine: EngineBridge
    private let macroManager = MacroManager.shared

    init(engine: EngineBridge) {
        self.engine = engine
    }

    // MARK: - Keystroke handling

    /// Feed a character. Returns true if AX injection succeeded.
    func feed(char: Character) -> Bool {
        guard let element = getFocusedTextElement() else {
            return false
        }

        let (bs, out) = engine.feed(char: char)
        // Check if engine processed the character (even if output is empty for literal chars)
        // If engine is composing or produced output, we should inject
        guard engine.isComposing || bs > 0 || !out.isEmpty else {
            // Engine didn't process and we're not composing - let OS handle it
            return false
        }

        if tryInject(bs: bs, out: out, element: element) {
            return true
        }
        // AX injection failed but engine already consumed the char.
        // Only reset if engine state diverged from screen (bs > 0 or
        // output differs from raw char). If output == char and bs == 0,
        // engine just appended a literal — screen will get it from the
        // passed-through OS event, so no desync.
        if bs > 0 || out != String(char) {
            engine.reset()
        }
        return false
    }

    /// Backspace. Returns true if AX injection succeeded.
    func backspace() -> Bool {
        guard let element = getFocusedTextElement() else {
            return false
        }

        let (bs, out) = engine.backspace()
        // Inject if: we have backspaces, we have output, or engine is still composing
        guard engine.isComposing || bs > 0 || !out.isEmpty else {
            // Nothing to do - let OS handle backspace
            return false
        }

        if tryInject(bs: bs, out: out, element: element) {
            return true
        }
        // AX injection failed but engine already processed backspace.
        // Reset to prevent desync — backspace always changes engine state.
        engine.reset()
        return false
    }

    /// Try to inject (bs, out) via AX. Returns true if successful.
    /// Used by EventTap as a hybrid fallback: try AX first, then CGEvent.
    /// The engine has already processed the keystroke — this only handles
    /// the visual update.
    func tryInject(bs: Int, out: String) -> Bool {
        guard let element = getFocusedTextElement() else { return false }
        return tryInject(bs: bs, out: out, element: element)
    }

    private func tryInject(bs: Int, out: String, element: AXUIElement) -> Bool {
        guard let current = getTextValue(element) else {
            return false
        }

        var newText = current
        for _ in 0..<bs { newText = String(newText.dropLast()) }
        newText += out

        setTextValue(element, text: newText)
        // AX ranges are measured in UTF-16 code units, not Swift Character
        // (grapheme) count. Using .count for decomposed Vietnamese or emoji
        // places the cursor before the real end. Use utf16.count instead.
        setCursorToEnd(element, length: newText.utf16.count)

        if let after = getTextValue(element) {
            if after == newText {
                return true
            } else {
                return false
            }
        } else {
            return false
        }
    }

    /// Commit on word boundary. Returns true if a macro expansion was
    /// performed (caller should consume the triggering key to avoid a
    /// trailing space/return after the expanded text).
    @discardableResult
    func commit() -> Bool {
        // Check for macro expansion first
        if macroManager.isEnabled() {
            // Include V-C-V auto-committed prefix + composing for macro matching.
            let currentText = engine.committedText() + engine.currentOutput()
            if let expansion = macroManager.findExpansion(for: currentText) {
                guard let element = getFocusedTextElement() else { return false }
                guard let current = getTextValue(element) else { return false }

                // Backspace the abbreviation
                let abbreviationLength = currentText.count
                var newText = current
                for _ in 0..<abbreviationLength { newText = String(newText.dropLast()) }
                newText += expansion

                setTextValue(element, text: newText)
                setCursorToEnd(element, length: newText.utf16.count)
                engine.reset()
                return true
            }
        }
        _ = engine.commit()
        return false
    }

    func reset() {
        engine.reset()
    }

    // MARK: - AX Helpers

    private func getFocusedTextElement() -> AXUIElement? {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedElement: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &focusedElement
        )
        guard result == .success, let focused = focusedElement else { return nil }
        // In Swift, CFTypeRef from Copy functions is ARC-managed — no
        // manual CFRelease needed. The bridge to AXUIElement transfers
        // ownership to ARC automatically.
        let element = focused as! AXUIElement

        // Verify it's a text field (has Value attribute)
        var value: CFTypeRef?
        let hasValue = AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value)
        guard hasValue == .success else { return element }

        return element
    }

    private func getTextValue(_ element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value) == .success else {
            return nil
        }
        return value as? String
    }

    private func setTextValue(_ element: AXUIElement, text: String) {
        AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, text as CFTypeRef)
    }

    private func setCursorToEnd(_ element: AXUIElement, length: Int) {
        var range = CFRange(location: length, length: 0)
        guard let axRange = AXValueCreate(.cfRange, &range) else { return }
        AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, axRange)
    }
}
