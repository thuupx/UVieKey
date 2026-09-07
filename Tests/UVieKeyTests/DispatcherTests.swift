import Cocoa
import XCTest
@testable import UVieKey

/// Drives `EventTap.handle()` with simulated CGEvents and asserts the
/// dispatch decisions (consume vs pass-through) plus the injection plan
/// recorded by the sink — without posting anything to the host session.
final class DispatcherTests: XCTestCase {
    private var tap: EventTap!
    private var sink: RecordingSink!
    private var detector: StubAppDetector!
    private var axInjector: StubAXInjector!

    override func setUp() {
        super.setUp()
        tap = makeEventTap()
        sink = RecordingSink()
        detector = StubAppDetector(bundleID: "com.test.editor")
        axInjector = StubAXInjector()
        tap.outputSink = sink
        tap.appDetector = detector
        tap.axInjector = axInjector
    }

    override func tearDown() {
        tap = nil
        sink = nil
        detector = nil
        axInjector = nil
        super.tearDown()
    }

    // MARK: - Character keys

    func test_characterKey_isConsumedAndPosted() {
        let result = send(tap, .keyDown, keyDownEvent(9, unicode: "v"))
        assertConsumed(result)
        XCTAssertEqual(sink.calls, [.text("v")])
    }

    func test_transformKey_backspacesAndReposts() {
        // "vie" then a second 'e' → ê: one backspace + "ê".
        for ch in "vie" {
            assertConsumed(send(tap, .keyDown, keyDownEvent(0, unicode: String(ch))))
        }
        sink.reset()

        let result = send(tap, .keyDown, keyDownEvent(14, unicode: "e"))
        assertConsumed(result)
        XCTAssertEqual(sink.calls, [.backspaces(1), .text("ê")])
    }

    func test_characterKeyUp_isSuppressed() {
        assertConsumed(send(tap, .keyUp, keyUpEvent(9, unicode: "v")))
        XCTAssertTrue(sink.calls.isEmpty)
    }

    func test_shiftCharacter_keepsUppercase() {
        let result = send(tap, .keyDown, keyDownEvent(0, flags: .maskShift, unicode: "A"))
        assertConsumed(result)
        XCTAssertEqual(sink.calls, [.text("A")])
    }

    // MARK: - Backspace

    func test_backspaceWhileComposing_isConsumedAndApplied() {
        for ch in "vie" {
            assertConsumed(send(tap, .keyDown, keyDownEvent(0, unicode: String(ch))))
        }
        sink.reset()

        assertConsumed(send(tap, .keyDown, keyDownEvent(51)))
        XCTAssertEqual(sink.calls, [.backspaces(1), .text("")])
    }

    func test_backspaceWhenNotComposing_passesThrough() {
        assertPassed(send(tap, .keyDown, keyDownEvent(51)))
        XCTAssertTrue(sink.calls.isEmpty)
    }

    func test_optionBackspace_resetsAndPassesThrough() {
        for ch in "vie" {
            assertConsumed(send(tap, .keyDown, keyDownEvent(0, unicode: String(ch))))
        }
        XCTAssertTrue(tap._engine.isComposing)
        sink.reset()

        assertPassed(send(tap, .keyDown, keyDownEvent(51, flags: .maskAlternate)))
        XCTAssertFalse(tap._engine.isComposing)
        XCTAssertTrue(sink.calls.isEmpty)
    }

    // MARK: - Space / break keys

    func test_space_commitsAndPassesThrough() {
        for ch in "vieejt" {
            assertConsumed(send(tap, .keyDown, keyDownEvent(0, unicode: String(ch))))
        }
        XCTAssertTrue(tap._engine.isComposing)

        assertPassed(send(tap, .keyDown, keyDownEvent(49)))
        XCTAssertFalse(tap._engine.isComposing)
    }

    func test_space_macroExpansion_consumesAndInjects() {
        MacroManager.shared.macros = [MacroManager.Macro(abbreviation: "việt", expansion: "X")]
        MacroManager.shared.enabledCache = true
        defer {
            MacroManager.shared.macros = []
            MacroManager.shared.enabledCache = false
        }

        for ch in "vieejt" {
            assertConsumed(send(tap, .keyDown, keyDownEvent(0, unicode: String(ch))))
        }
        sink.reset()

        assertConsumed(send(tap, .keyDown, keyDownEvent(49)))
        XCTAssertEqual(sink.calls.last, .text("X"))
    }

    func test_enter_passesThroughAndCommits() {
        for ch in "vie" {
            assertConsumed(send(tap, .keyDown, keyDownEvent(0, unicode: String(ch))))
        }

        assertPassed(send(tap, .keyDown, keyDownEvent(36)))
        XCTAssertFalse(tap._engine.isComposing)
        XCTAssertTrue(tap.isAtSentenceStart)
    }

    func test_escape_resetsWithoutCommit() {
        for ch in "vie" {
            assertConsumed(send(tap, .keyDown, keyDownEvent(0, unicode: String(ch))))
        }

        assertPassed(send(tap, .keyDown, keyDownEvent(53)))
        XCTAssertFalse(tap._engine.isComposing)
    }

    func test_arrowKey_resetsAndPassesThrough() {
        for ch in "vie" {
            assertConsumed(send(tap, .keyDown, keyDownEvent(0, unicode: String(ch))))
        }

        assertPassed(send(tap, .keyDown, keyDownEvent(123)))
        XCTAssertFalse(tap._engine.isComposing)
    }

    // MARK: - Post-commit word editing (LabanKey-style)

    /// Types `word`, commits it with space, arrows left onto the word end,
    /// then sends `ch` as the edit key.
    private func typeCommitArrowLeftThenEdit(_ word: String, _ ch: Character) {
        let keyCodes: [Character: Int64] = [
            "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "j": 38, "k": 40,
            "l": 37, "c": 8, "n": 45, "o": 31, "i": 34, "e": 14, "r": 15,
            "t": 17, "u": 32, "w": 13, "g": 5, "b": 11, "v": 9, "p": 35,
        ]
        for c in word {
            assertConsumed(send(tap, .keyDown, keyDownEvent(keyCode(for: c), unicode: String(c))))
        }
        assertPassed(send(tap, .keyDown, keyDownEvent(49)))  // space commits
        assertPassed(send(tap, .keyDown, keyDownEvent(123))) // left arrow
        assertConsumed(send(tap, .keyDown, keyDownEvent(keyCode(for: ch), unicode: String(ch))))
    }

    func test_editCommittedWord_toneKeyReplacesInPlace() {
        // "don" + space commits "don"; arrow-left onto the word end; 's'
        // re-renders it as "dón": 2 backspaces eat "on", then "ón" is typed.
        for ch in "don" {
            assertConsumed(send(tap, .keyDown, keyDownEvent(keyCode(for: ch), unicode: String(ch))))
        }
        assertPassed(send(tap, .keyDown, keyDownEvent(49)))
        assertPassed(send(tap, .keyDown, keyDownEvent(123)))

        sink.reset()
        assertConsumed(send(tap, .keyDown, keyDownEvent(1, unicode: "s")))
        XCTAssertEqual(sink.calls, [.backspaces(2), .text("ón")])
    }

    func test_editCommittedWord_backspaceInsteadOfArrowAlsoArms() {
        // Commit "don", then delete the space with backspace — the caret
        // lands on the word end and the edit arms the same way.
        for ch in "don" {
            assertConsumed(send(tap, .keyDown, keyDownEvent(keyCode(for: ch), unicode: String(ch))))
        }
        assertPassed(send(tap, .keyDown, keyDownEvent(49)))
        assertPassed(send(tap, .keyDown, keyDownEvent(51)))

        sink.reset()
        assertConsumed(send(tap, .keyDown, keyDownEvent(1, unicode: "s")))
        XCTAssertEqual(sink.calls, [.backspaces(2), .text("ón")])
    }

    func test_editCommittedWord_midWordCaretPassesThrough() {
        for ch in "don" {
            assertConsumed(send(tap, .keyDown, keyDownEvent(keyCode(for: ch), unicode: String(ch))))
        }
        assertPassed(send(tap, .keyDown, keyDownEvent(49)))
        // Two arrow-lefts put the caret mid-word (editCaretBack > 0).
        assertPassed(send(tap, .keyDown, keyDownEvent(123)))
        assertPassed(send(tap, .keyDown, keyDownEvent(123)))

        // Typing mid-word passes through as a fresh feed; the engine was
        // reset, so the output is just the raw char.
        sink.reset()
        assertConsumed(send(tap, .keyDown, keyDownEvent(1, unicode: "s")))
        XCTAssertEqual(sink.calls, [.text("s")])
    }

    /// Real hardware arrow keyDowns carry function-key flags
    /// (.maskSecondaryFn + .maskNumericPad) even with no modifier held.
    /// The modifier-cursor reset must NOT swallow them, or the committed
    /// word is wiped and post-commit editing never arms.
    func test_editCommittedWord_realArrowFlagsStillArm() {
        for ch in "don" {
            assertConsumed(send(tap, .keyDown, keyDownEvent(keyCode(for: ch), unicode: String(ch))))
        }
        assertPassed(send(tap, .keyDown, keyDownEvent(49)))

        // Arrow-left exactly as a real keyboard delivers it: function-key flags set.
        let realArrow = keyDownEvent(123, flags: [.maskSecondaryFn, .maskNumericPad])
        assertPassed(send(tap, .keyDown, realArrow))
        XCTAssertFalse(tap._engine.isComposing)  // committed, not reset

        sink.reset()
        assertConsumed(send(tap, .keyDown, keyDownEvent(1, unicode: "s")))
        XCTAssertEqual(sink.calls, [.backspaces(2), .text("ón")])
    }

    func test_editCommittedWord_modifierArrowStillResets() {
        for ch in "don" {
            assertConsumed(send(tap, .keyDown, keyDownEvent(keyCode(for: ch), unicode: String(ch))))
        }
        assertPassed(send(tap, .keyDown, keyDownEvent(49)))

        // Cmd+Arrow is a real jump (line start/end): the history must reset.
        assertPassed(send(tap, .keyDown, keyDownEvent(123, flags: .maskCommand)))
        sink.reset()

        assertConsumed(send(tap, .keyDown, keyDownEvent(1, unicode: "s")))
        XCTAssertEqual(sink.calls, [.text("s")])
    }

    func test_editCommittedWord_mouseDownDisarms() {
        for ch in "don" {
            assertConsumed(send(tap, .keyDown, keyDownEvent(keyCode(for: ch), unicode: String(ch))))
        }
        assertPassed(send(tap, .keyDown, keyDownEvent(49)))
        assertPassed(send(tap, .keyDown, keyDownEvent(123))) // edit-armed

        assertPassed(send(tap, .leftMouseDown, keyDownEvent(0)))
        sink.reset()

        // The reset cleared the committed-word history: the edit no longer
        // fires and the key feeds normally.
        assertConsumed(send(tap, .keyDown, keyDownEvent(1, unicode: "s")))
        XCTAssertEqual(sink.calls, [.text("s")])
    }

    func test_editCommittedWord_midSentenceSecondWord() {
        // "ab cd eg " — arrow back onto "cd" (the middle word) and edit it.
        // Boundary for cd's end = len("eg") + 1 = 3 behind the anchor; the
        // post-commit caret starts 1 right of it, so 4 arrow-lefts.
        for word in ["ab", "cd", "eg"] {
            for ch in word {
                assertConsumed(send(tap, .keyDown, keyDownEvent(keyCode(for: ch), unicode: String(ch))))
            }
            assertPassed(send(tap, .keyDown, keyDownEvent(49)))
        }
        for _ in 0..<("eg".count + 1 + 1) {
            assertPassed(send(tap, .keyDown, keyDownEvent(123)))
        }
        // Typing at cd's end re-enters "cd" → "cds": no backspaces needed
        // (common prefix), just the suffix.
        sink.reset()
        assertConsumed(send(tap, .keyDown, keyDownEvent(1, unicode: "s")))
        XCTAssertEqual(sink.calls, [.text("s")])
    }

    /// Maps a character to a plausible keycode for the synthetic event
    /// (only the unicode payload matters to `characterFromCGEvent`).
    private func keyCode(for ch: Character) -> Int64 {
        Int64(ch.asciiValue ?? 0)
    }

    // MARK: - Modifiers & mouse

    func test_commandCharacter_passesThrough() {
        assertPassed(send(tap, .keyDown, keyDownEvent(9, flags: .maskCommand, unicode: "v")))
        XCTAssertTrue(sink.calls.isEmpty)
    }

    func test_commandA_selectionShortcut_resetsEngine() {
        for ch in "vie" {
            assertConsumed(send(tap, .keyDown, keyDownEvent(0, unicode: String(ch))))
        }

        assertPassed(send(tap, .keyDown, keyDownEvent(0, flags: .maskCommand, unicode: "a")))
        XCTAssertFalse(tap._engine.isComposing)
    }

    func test_flagsChanged_passesThroughAndArmsRefreshBudget() {
        assertPassed(send(tap, .flagsChanged, keyDownEvent(54, flags: .maskCommand)))
        XCTAssertEqual(tap.axRefreshAttempts, EventTap.axRefreshMaxAttempts)
    }

    func test_mouseDown_resetsEngineAndPassesThrough() {
        for ch in "vie" {
            assertConsumed(send(tap, .keyDown, keyDownEvent(0, unicode: String(ch))))
        }

        assertPassed(send(tap, .leftMouseDown, keyDownEvent(0)))
        XCTAssertFalse(tap._engine.isComposing)
        XCTAssertTrue(tap.isAtSentenceStart)
    }

    // MARK: - English mode

    func test_englishMode_repostsCharactersSynthetically() {
        tap.inputMethodManager.isVietnamese = false

        let result = send(tap, .keyDown, keyDownEvent(9, unicode: "v"))
        assertConsumed(result)
        XCTAssertEqual(sink.calls, [.text("v")])
    }

    func test_englishMode_backspacePassesThrough() {
        tap.inputMethodManager.isVietnamese = false
        assertPassed(send(tap, .keyDown, keyDownEvent(51)))
    }

    // MARK: - App classification

    func test_excludedApp_passesEverythingThrough() {
        detector.bundleID = "com.test.excluded"
        tap.cachedExcludedApps = ["com.test.excluded"]

        assertPassed(send(tap, .keyDown, keyDownEvent(9, unicode: "v")))
        XCTAssertTrue(sink.calls.isEmpty)
    }

    func test_bypassApp_passesThrough() {
        detector.bundleID = "com.apple.loginwindow"
        assertPassed(send(tap, .keyDown, keyDownEvent(9, unicode: "v")))
        XCTAssertTrue(sink.calls.isEmpty)
    }

    func test_simulator_bypassesIME_entirely() {
        // The iOS Simulator does not forward synthetic CGEvents to the guest
        // OS — it uses its own keyboard routing. Without bypass, UVieKey
        // consumes the original keyDown and posts a synthetic replacement
        // that the Simulator never delivers, making typing impossible.
        detector.bundleID = "com.apple.iphonesimulator"
        assertPassed(send(tap, .keyDown, keyDownEvent(9, unicode: "v")))
        XCTAssertTrue(sink.calls.isEmpty, "Simulator should bypass IME — no synthetic events")
    }

    // MARK: - AX mode (Spotlight)

    func test_axApp_characterGoesThroughAXInjector() {
        detector.bundleID = "com.apple.Spotlight"

        assertConsumed(send(tap, .keyDown, keyDownEvent(9, unicode: "v")))
        XCTAssertEqual(axInjector.fedChars, ["v"])
        XCTAssertTrue(sink.calls.isEmpty)
    }

    func test_axApp_backspaceAndSpaceRouteToInjector() {
        detector.bundleID = "com.apple.Spotlight"

        assertConsumed(send(tap, .keyDown, keyDownEvent(51)))
        XCTAssertEqual(axInjector.backspaceCount, 1)

        assertPassed(send(tap, .keyDown, keyDownEvent(49)))
        XCTAssertEqual(axInjector.commitCount, 1)
    }

    func test_axApp_injectionFailure_passesThrough() {
        detector.bundleID = "com.apple.Spotlight"
        axInjector.feedSuccess = false

        assertPassed(send(tap, .keyDown, keyDownEvent(9, unicode: "v")))
        XCTAssertEqual(axInjector.fedChars, ["v"])
    }

    // MARK: - AX refresh budget (Cmd+Space → Spotlight regression)

    func test_refreshBudget_retriesUntilFocusedAppChanges() {
        // Simulates Cmd+Space: the Space keyDown spends an attempt while
        // Spotlight is still opening (AX still reports the previous app);
        // the remaining attempts must keep retrying until the lookup returns
        // a different app — only then is detection consumed and AX mode used.
        detector = StubAppDetector(
            bundleID: "com.test.terminal",
            refreshResults: ["com.test.terminal", "com.test.terminal", "com.apple.Spotlight"]
        )
        tap.appDetector = detector

        // Cmd keyDown arms the budget.
        assertPassed(send(tap, .flagsChanged, keyDownEvent(54, flags: .maskCommand)))
        XCTAssertEqual(tap.axRefreshAttempts, EventTap.axRefreshMaxAttempts)

        // Space keyDown (Cmd held): spends an attempt, Spotlight not open yet.
        assertPassed(send(tap, .keyDown, keyDownEvent(49, flags: .maskCommand)))
        XCTAssertEqual(tap.axRefreshAttempts, EventTap.axRefreshMaxAttempts - 1)
        XCTAssertEqual(detector.refreshCallCount, 1)

        // 'v': second attempt, still the old app.
        assertConsumed(send(tap, .keyDown, keyDownEvent(9, unicode: "v")))
        XCTAssertEqual(tap.axRefreshAttempts, EventTap.axRefreshMaxAttempts - 2)
        XCTAssertEqual(detector.refreshCallCount, 2)

        // 'i': third attempt finds Spotlight — budget consumed, app updated.
        assertConsumed(send(tap, .keyDown, keyDownEvent(34, unicode: "i")))
        XCTAssertEqual(tap.axRefreshAttempts, 0)
        XCTAssertEqual(detector.bundleID, "com.apple.Spotlight")
        XCTAssertEqual(detector.refreshCallCount, 3)

        // 'e': no more refreshes, and the keystroke routes into AX mode.
        // ('i' already routed there too — the refresh that detected Spotlight
        // runs before dispatch within the same event, so AX mode applies
        // immediately from that keystroke on.)
        assertConsumed(send(tap, .keyDown, keyDownEvent(14, unicode: "e")))
        XCTAssertEqual(detector.refreshCallCount, 3)
        XCTAssertEqual(axInjector.fedChars, ["i", "e"])
    }

    func test_refreshBudget_exhaustsOnUnchangedApp() {
        // A Cmd press followed by normal typing in the same unclassified app
        // must stop paying the AX cost after the budget runs out.
        detector = StubAppDetector(bundleID: "com.test.terminal")
        tap.appDetector = detector

        assertPassed(send(tap, .flagsChanged, keyDownEvent(54, flags: .maskCommand)))

        for i in 0..<EventTap.axRefreshMaxAttempts {
            assertConsumed(send(tap, .keyDown, keyDownEvent(9, unicode: "v")))
            XCTAssertEqual(tap.axRefreshAttempts, EventTap.axRefreshMaxAttempts - i - 1)
        }
        XCTAssertEqual(detector.refreshCallCount, EventTap.axRefreshMaxAttempts)

        // Budget exhausted — no further lookups.
        assertConsumed(send(tap, .keyDown, keyDownEvent(9, unicode: "v")))
        XCTAssertEqual(detector.refreshCallCount, EventTap.axRefreshMaxAttempts)
    }
}
