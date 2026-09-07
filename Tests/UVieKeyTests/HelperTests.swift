import XCTest
@testable import UVieKey

/// Pure helper coverage: key classification tables, selection-shortcut
/// detection, and the auto-capitalize state machine.
final class HelperTests: XCTestCase {
    private var tap: EventTap!

    override func setUp() {
        super.setUp()
        tap = makeEventTap()
    }

    override func tearDown() {
        tap = nil
        super.tearDown()
    }

    func test_breakKeyTable() {
        for keyCode in [36, 48, 53, 116, 121, 123, 124, 125, 126, 115, 119, 114, 117] {
            XCTAssertTrue(tap.isBreakKey(Int64(keyCode)), "keyCode \(keyCode) should be a break key")
        }
        for keyCode in [0, 1, 49, 51] {
            XCTAssertFalse(tap.isBreakKey(Int64(keyCode)), "keyCode \(keyCode) should not be a break key")
        }
    }

    func test_cursorMovementKeyTable() {
        for keyCode in [123, 124, 125, 126, 115, 119, 116, 121] {
            XCTAssertTrue(tap.isCursorMovementKey(Int64(keyCode)), "keyCode \(keyCode) should move the cursor")
        }
        for keyCode in [36, 48, 49, 51, 53] {
            XCTAssertFalse(tap.isCursorMovementKey(Int64(keyCode)), "keyCode \(keyCode) should not move the cursor")
        }
    }

    func test_selectionShortcuts() {
        XCTAssertTrue(isSelectionShortcut(keyCode: 0, flags: .maskCommand)) // Cmd+A
        XCTAssertTrue(isSelectionShortcut(keyCode: 0, flags: .maskControl)) // Ctrl+A
        XCTAssertTrue(isSelectionShortcut(keyCode: 123, flags: .maskShift)) // Shift+Left
        XCTAssertTrue(isSelectionShortcut(keyCode: 126, flags: .maskShift)) // Shift+Up
        XCTAssertTrue(isSelectionShortcut(keyCode: 115, flags: .maskShift)) // Shift+Home
        XCTAssertTrue(isSelectionShortcut(keyCode: 121, flags: .maskShift)) // Shift+PageDown

        XCTAssertFalse(isSelectionShortcut(keyCode: 0, flags: []))
        XCTAssertFalse(isSelectionShortcut(keyCode: 9, flags: .maskShift)) // Shift+V types, not selects
        XCTAssertFalse(isSelectionShortcut(keyCode: 49, flags: .maskShift)) // Shift+Space
    }

    func test_autoCapitalize_uppercasesAtSentenceStart() {
        tap.autoCapitalizeEnabled = true
        tap.isAtSentenceStart = true

        XCTAssertEqual(tap.applyAutoCapitalize(to: "a"), "A")
        XCTAssertFalse(tap.isAtSentenceStart, "first letter consumed the sentence-start state")

        // Subsequent letters are untouched.
        XCTAssertEqual(tap.applyAutoCapitalize(to: "b"), "b")
    }

    func test_autoCapitalize_disabledOrMidSentence_isIdentity() {
        tap.autoCapitalizeEnabled = false
        tap.isAtSentenceStart = true
        XCTAssertEqual(tap.applyAutoCapitalize(to: "a"), "a")

        tap.autoCapitalizeEnabled = true
        tap.isAtSentenceStart = false
        XCTAssertEqual(tap.applyAutoCapitalize(to: "a"), "a")
    }

    func test_autoCapitalize_nonLetters_doNotConsumeSentenceStart() {
        tap.autoCapitalizeEnabled = true
        tap.isAtSentenceStart = true
        XCTAssertEqual(tap.applyAutoCapitalize(to: " "), " ")
        XCTAssertTrue(tap.isAtSentenceStart, "a space should not end the sentence-start window")
    }

    func test_sentenceStartStateTransitions() {
        tap.isAtSentenceStart = false
        tap.updateSentenceStartState(after: ".")
        XCTAssertTrue(tap.isAtSentenceStart)

        tap.isAtSentenceStart = false
        tap.updateSentenceStartState(after: "!")
        XCTAssertTrue(tap.isAtSentenceStart)

        tap.isAtSentenceStart = false
        tap.updateSentenceStartState(after: "?")
        XCTAssertTrue(tap.isAtSentenceStart)

        tap.isAtSentenceStart = false
        tap.updateSentenceStartState(after: "a")
        XCTAssertFalse(tap.isAtSentenceStart)

        tap.isAtSentenceStart = true
        tap.updateSentenceStartState(after: " ")
        XCTAssertTrue(tap.isAtSentenceStart, "space keeps the state")
    }

    func test_enterStartsNewSentence() {
        tap.isAtSentenceStart = false
        tap.updateSentenceStartStateForBreakKey(36) // Return
        XCTAssertTrue(tap.isAtSentenceStart)

        tap.isAtSentenceStart = false
        tap.updateSentenceStartStateForBreakKey(76) // Numpad Enter
        XCTAssertTrue(tap.isAtSentenceStart)

        tap.isAtSentenceStart = false
        tap.updateSentenceStartStateForBreakKey(48) // Tab
        XCTAssertFalse(tap.isAtSentenceStart)
    }

    func test_macroLookup() {
        let manager = MacroManager.shared
        let original = manager.macros
        defer { manager.macros = original }

        manager.macros = [
            MacroManager.Macro(abbreviation: "vnm", expansion: "Việt Nam"),
            MacroManager.Macro(abbreviation: "thx", expansion: "cảm ơn"),
        ]

        XCTAssertEqual(manager.findExpansion(for: "vnm"), "Việt Nam")
        XCTAssertEqual(manager.findExpansion(for: "thx"), "cảm ơn")
        XCTAssertNil(manager.findExpansion(for: "unknown"))
        XCTAssertNil(manager.findExpansion(for: ""))
    }

    // MARK: - Auto-capitalize app-switch save/restore

    func test_mouseDown_savesSentenceStartAndResets() {
        tap.isAtSentenceStart = false
        tap.savedIsAtSentenceStart = nil

        // Simulate a mouse down — should save the current state and reset to true.
        _ = send(tap, .leftMouseDown, keyDownEvent(0))

        XCTAssertEqual(tap.savedIsAtSentenceStart, false,
                       "mouse down should save the pre-click sentence-start state")
        XCTAssertTrue(tap.isAtSentenceStart,
                      "mouse down should reset isAtSentenceStart to true")
    }

    func test_appSwitch_restoresSavedSentenceStart() {
        tap.isAtSentenceStart = false
        tap.savedIsAtSentenceStart = nil

        // Mouse down saves and resets.
        _ = send(tap, .leftMouseDown, keyDownEvent(0))
        XCTAssertEqual(tap.savedIsAtSentenceStart, false)
        XCTAssertTrue(tap.isAtSentenceStart)

        // App switch fires → restore the saved value.
        tap.restoreSentenceStartAfterAppSwitch()
        XCTAssertFalse(tap.isAtSentenceStart,
                       "app switch should restore the pre-mouse-down state")
        XCTAssertNil(tap.savedIsAtSentenceStart,
                     "saved state should be cleared after restore")
    }

    func test_keyDown_clearsSavedSentenceStart_noAppSwitch() {
        tap.isAtSentenceStart = false
        tap.savedIsAtSentenceStart = nil

        // Mouse down saves and resets (click within same app = cursor reposition).
        _ = send(tap, .leftMouseDown, keyDownEvent(0))
        XCTAssertEqual(tap.savedIsAtSentenceStart, false)
        XCTAssertTrue(tap.isAtSentenceStart)

        // No app switch follows — next keyDown clears the saved value.
        // Use space (not a letter) so isAtSentenceStart stays true from the
        // mouse-down reset — verifying the saved value was NOT restored.
        _ = send(tap, .keyDown, keyDownEvent(49))
        XCTAssertNil(tap.savedIsAtSentenceStart,
                     "keyDown should clear saved state when no app switch followed")
        XCTAssertTrue(tap.isAtSentenceStart,
                      "isAtSentenceStart should stay true (cursor reposition, not app switch)")
    }

    func test_appSwitchRestore_noSavedState_isNoOp() {
        tap.isAtSentenceStart = true
        tap.savedIsAtSentenceStart = nil

        tap.restoreSentenceStartAfterAppSwitch()
        XCTAssertTrue(tap.isAtSentenceStart,
                      "restore with no saved state should be a no-op")
        XCTAssertNil(tap.savedIsAtSentenceStart)
    }

    func test_mouseDragged_doesNotOverwriteSavedState() {
        tap.isAtSentenceStart = false
        tap.savedIsAtSentenceStart = nil

        // Initial down saves the pre-click state.
        _ = send(tap, .leftMouseDown, keyDownEvent(0))
        XCTAssertEqual(tap.savedIsAtSentenceStart, false)

        // Dragged events must NOT overwrite the saved value with the
        // already-reset `true`.
        _ = send(tap, .leftMouseDragged, keyDownEvent(0))
        XCTAssertEqual(tap.savedIsAtSentenceStart, false,
                       "dragged events should not overwrite the pre-click state")
        XCTAssertTrue(tap.isAtSentenceStart)
    }

    func test_appSwitch_perAppMemoryRoundTrip() {
        tap.sentenceStartMemory = [:]
        tap.sentenceStartMemoryApp = "com.test.A"
        tap.isAtSentenceStart = false // A is mid-sentence

        // Switch to B (never visited): A's state is filed, B keeps current.
        tap.handleSentenceStartAcrossAppSwitch(to: "com.test.B")
        XCTAssertEqual(tap.sentenceStartMemory["com.test.A"], false)
        XCTAssertFalse(tap.isAtSentenceStart,
                       "first visit to B keeps the current state (no behavior change)")
        XCTAssertEqual(tap.sentenceStartMemoryApp, "com.test.B")

        // Type a sentence ending in "." in B → state becomes true.
        tap.updateSentenceStartState(after: "o")
        tap.updateSentenceStartState(after: "k")
        tap.updateSentenceStartState(after: ".")
        XCTAssertTrue(tap.isAtSentenceStart)

        // Back to A: B's state is filed, A's own mid-sentence state returns.
        tap.handleSentenceStartAcrossAppSwitch(to: "com.test.A")
        XCTAssertEqual(tap.sentenceStartMemory["com.test.B"], true)
        XCTAssertFalse(tap.isAtSentenceStart,
                       "A must restore its own mid-sentence state, not B's")
        XCTAssertTrue(tap.sentenceStartMemory["com.test.A"] == false)

        // Back to B: B's post-delimiter state returns.
        tap.handleSentenceStartAcrossAppSwitch(to: "com.test.B")
        XCTAssertTrue(tap.isAtSentenceStart, "B ended with a delimiter")
    }

    func test_clickSwitchRoundTrip_midSentenceNotRecapitalized() {
        // Full repro of the reported bug: mid-sentence in A, click to B,
        // click back to A — the next letter must NOT be capitalized.
        tap.sentenceStartMemory = [:]
        tap.sentenceStartMemoryApp = "com.test.A"
        tap.autoCapitalizeEnabled = true
        tap.isAtSentenceStart = false

        // Click B's window (mouse down) → app switch to B.
        _ = send(tap, .leftMouseDown, keyDownEvent(0))
        tap.handleSentenceStartAcrossAppSwitch(to: "com.test.B")

        // Click back into A's window → app switch to A.
        _ = send(tap, .leftMouseDown, keyDownEvent(0))
        tap.handleSentenceStartAcrossAppSwitch(to: "com.test.A")

        // Typing mid-sentence must not capitalize.
        XCTAssertEqual(tap.applyAutoCapitalize(to: "w"), "w",
                       "returning mid-sentence must not capitalize")
    }
}
