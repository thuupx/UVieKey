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

    /// Cached focused element to avoid repeated lookups.
    private weak var cachedElement: AXUIElement?
    private var lastElementPID: pid_t = 0

    init(engine: EngineBridge) {
        self.engine = engine
    }

    // MARK: - Keystroke handling

    /// Feed a character. Returns true if AX injection succeeded.
    func feed(char: Character) -> Bool {
        guard let element = getFocusedTextElement() else { return false }

        let (bs, out) = engine.feed(char: char)
        // Check if engine processed the character (even if output is empty for literal chars)
        // If engine is composing or produced output, we should inject
        guard engine.isComposing || bs > 0 || !out.isEmpty else {
            // Engine didn't process and we're not composing - let OS handle it
            return false
        }

        guard let current = getTextValue(element) else { return false }

        var newText = current
        for _ in 0..<bs { newText = String(newText.dropLast()) }
        newText += out

        setTextValue(element, text: newText)
        setCursorToEnd(element, length: newText.count)
        return true
    }

    /// Backspace. Returns true if AX injection succeeded.
    func backspace() -> Bool {
        guard let element = getFocusedTextElement() else { return false }

        let (bs, out) = engine.backspace()
        // Inject if: we have backspaces, we have output, or engine is still composing
        guard engine.isComposing || bs > 0 || !out.isEmpty else {
            // Nothing to do - let OS handle backspace
            return false
        }

        guard let current = getTextValue(element) else { return false }

        var newText = current
        for _ in 0..<bs { newText = String(newText.dropLast()) }
        newText += out

        setTextValue(element, text: newText)
        setCursorToEnd(element, length: newText.count)
        return true
    }

    /// Commit on word boundary.
    func commit() {
        // Check for macro expansion first
        if macroManager.isEnabled() {
            let currentText = engine.currentOutput()
            if let expansion = macroManager.findExpansion(for: currentText) {
                guard let element = getFocusedTextElement() else { return }
                guard let current = getTextValue(element) else { return }
                
                // Backspace the abbreviation
                let abbreviationLength = currentText.count
                var newText = current
                for _ in 0..<abbreviationLength { newText = String(newText.dropLast()) }
                newText += expansion
                
                setTextValue(element, text: newText)
                setCursorToEnd(element, length: newText.count)
                engine.reset()
                return
            }
        }
        _ = engine.commit()
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
        guard result == .success else { return nil }
        let element = focusedElement as! AXUIElement

        // Verify it's a text field (has Value attribute)
        var value: CFTypeRef?
        let hasValue = AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value)
        guard hasValue == .success else { return nil }

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
