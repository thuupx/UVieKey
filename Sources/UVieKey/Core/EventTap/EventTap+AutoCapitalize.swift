import Cocoa

// MARK: - EventTap - Auto Capitalize Helpers

extension EventTap {
    /// Check if character is a sentence delimiter (. ! ?)
    func isSentenceDelimiter(_ char: Character) -> Bool {
        return char == "." || char == "!" || char == "?"
    }

    /// Transform a character to uppercase if auto-capitalize is enabled and at sentence start
    func applyAutoCapitalize(to char: Character) -> Character {
        // `autoCapitalizeEnabled` is cached in `applyEngineSettings()` — this
        // runs on every character keystroke, so no UserDefaults read here.
        guard autoCapitalizeEnabled && isAtSentenceStart else { return char }

        // Only capitalize alphabetic characters
        guard char.isLetter else { return char }

        // Mark that we've processed the first character of sentence
        isAtSentenceStart = false
        return char.uppercased().first ?? char
    }

    /// Update sentence start state based on the key that was just typed
    func updateSentenceStartState(after char: Character) {
        if isSentenceDelimiter(char) {
            isAtSentenceStart = true
        } else if char.isLetter || char.isNumber {
            // After typing a letter/number, we're no longer at sentence start
            isAtSentenceStart = false
        }
        // Space and other chars don't change state
    }

    /// Update sentence start state for break keys (Enter, etc.)
    func updateSentenceStartStateForBreakKey(_ keyCode: Int64) {
        // Enter/Return starts a new sentence
        if keyCode == 36 || keyCode == 76 {  // 36 = Return, 76 = Enter (numpad)
            isAtSentenceStart = true
        }
    }
}
