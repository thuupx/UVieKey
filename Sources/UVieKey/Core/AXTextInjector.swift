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
        guard let element = getFocusedTextElement() else { return false }

        let (bs, out) = engine.feed(char: char)
        // Check if engine processed the character (even if output is empty for literal chars)
        // If engine is composing or produced output, we should inject
        guard engine.isComposing || bs > 0 || !out.isEmpty else {
            // Engine didn't process and we're not composing - let OS handle it
            return false
        }

        return tryInject(bs: bs, out: out, element: element)
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

        return tryInject(bs: bs, out: out, element: element)
    }

    /// Try to inject (bs, out) via AX. Returns true if successful.
    /// Used by EventTap as a hybrid fallback: try AX first, then CGEvent.
    /// The engine has already processed the keystroke — this only handles
    /// the visual update.
    ///
    /// SAFETY: AX `setTextValue` replaces the ENTIRE text field content.
    /// On web contenteditable (Facebook, Google Docs, etc.), this can
    /// corrupt the field or silently fail. We only use AX for fields
    /// where we can verify the set succeeded by reading back the value.
    func tryInject(bs: Int, out: String) -> Bool {
        guard let element = getFocusedTextElement() else { return false }
        // Only use AX for native text fields. Web contenteditable (AXWebArea,
        // AXGroup) corrupts on setTextValue — fall back to CGEvent.
        guard isNativeTextField(element) else { return false }
        guard let current = getTextValue(element) else { return false }

        // SAFETY CHECK: only use AX for short text fields (address bar,
        // search fields, Notes). For long text (web forms, editors),
        // setTextValue would overwrite the entire field — dangerous.
        // Fall back to CGEvent for fields longer than 500 chars.
        if current.count > 500 {
            return false
        }

        var newText = current
        for _ in 0..<bs { newText = String(newText.dropLast()) }
        newText += out

        // Set text value and verify it took effect.
        let setOK = setTextValue(element, text: newText)
        if !setOK {
            return false
        }

        // Verify: read back and check the suffix matches.
        // This catches silent AX failures on web contenteditable.
        guard let after = getTextValue(element), after.hasSuffix(newText) else {
            // AX set failed silently — revert if possible and fall back.
            _ = setTextValue(element, text: current)
            return false
        }

        setCursorToEnd(element, length: newText.count)
        return true
    }

    private func tryInject(bs: Int, out: String, element: AXUIElement) -> Bool {
        // Legacy path used by feed()/backspace() — delegates to public tryInject.
        // Kept for AX-mode apps (Spotlight) that use the dedicated AXTextInjector.
        guard let current = getTextValue(element) else { return false }

        var newText = current
        for _ in 0..<bs { newText = String(newText.dropLast()) }
        newText += out

        let setOK = setTextValue(element, text: newText)
        guard setOK else { return false }

        setCursorToEnd(element, length: newText.count)
        return true
    }

    /// Commit on word boundary.
    func commit() {
        // Check for macro expansion first
        if macroManager.isEnabled() {
            // Include V-C-V auto-committed prefix + composing for macro matching.
            let currentText = engine.committedText() + engine.currentOutput()
            if let expansion = macroManager.findExpansion(for: currentText) {
                guard let element = getFocusedTextElement() else { return }
                guard let current = getTextValue(element) else { return }
                
                // Backspace the abbreviation
                let abbreviationLength = currentText.count
                var newText = current
                for _ in 0..<abbreviationLength { newText = String(newText.dropLast()) }
                newText += expansion
                
                _ = setTextValue(element, text: newText)
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

    /// Check if the AX element is a native text field (not web contenteditable).
    /// Web areas (AXWebArea, AXGroup) support kAXValueAttribute but
    /// setTextValue corrupts them — we must skip AX for those.
    private func isNativeTextField(_ element: AXUIElement) -> Bool {
        var role: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role)
        guard let roleString = role as? String else { return false }

        // Only allow AX for native text input roles.
        // AXWebArea / AXGroup = web contenteditable → skip (use CGEvent fallback).
        return roleString == "AXTextField"
            || roleString == "AXTextArea"
            || roleString == "AXComboBox"  // Safari address bar
    }

    private func getTextValue(_ element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value) == .success else {
            return nil
        }
        return value as? String
    }

    private func setTextValue(_ element: AXUIElement, text: String) -> Bool {
        let result = AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, text as CFTypeRef)
        return result == .success
    }

    private func setCursorToEnd(_ element: AXUIElement, length: Int) {
        var range = CFRange(location: length, length: 0)
        guard let axRange = AXValueCreate(.cfRange, &range) else { return }
        AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, axRange)
    }
}
