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
}
