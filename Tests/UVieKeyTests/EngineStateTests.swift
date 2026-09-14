import XCTest
@testable import UVieKey

/// Engine state machine: backspace walk-back, commit, introspection, and the
/// scratch-buffer reuse contract (a stale buffer would leak previous output).
final class EngineStateTests: XCTestCase {
    func test_backspaceWalksBackTransforms() {
        let engine = EngineBridge()
        var screen = ""
        for ch in "vieejt" {
            let (bs, out) = engine.feed(char: ch)
            screen = String(screen.dropLast(bs)) + out
        }
        XCTAssertEqual(screen, "việt")
        XCTAssertTrue(engine.isComposing)

        // Each backspace undoes exactly one transform step.
        let expected: [(String, Int, String)] = [
            ("việ", 1, ""),
            ("viê", 1, "ê"),
            ("vie", 1, "e"),
            ("vi", 1, ""),
            ("v", 1, ""),
            ("", 1, ""),
        ]
        for (wantScreen, wantBs, wantOut) in expected {
            let (bs, out) = engine.backspace()
            screen = String(screen.dropLast(bs)) + out
            XCTAssertEqual(screen, wantScreen)
            XCTAssertEqual(bs, wantBs)
            XCTAssertEqual(out, wantOut)
        }
        XCTAssertFalse(engine.isComposing)
    }

    func test_scratchBuffer_notPollutedByEmptyOutput() {
        // Regression: the FFI scratch buffer is reused across calls. When the
        // engine emits an empty suffix (e.g. a plain backspace), a stale
        // buffer would report the PREVIOUS output instead of "".
        let engine = EngineBridge()
        let feed = engine.feed(char: "a")
        XCTAssertEqual(feed.1, "a")

        let (bs, out) = engine.backspace()
        XCTAssertEqual(bs, 1)
        XCTAssertEqual(out, "", "stale scratch buffer leaked previous output")

        // And the next fresh feed is unaffected too.
        let again = engine.feed(char: "b")
        XCTAssertEqual(again.0, 0)
        XCTAssertEqual(again.1, "b")
    }

    func test_commitFinalizesComposingState() {
        let engine = EngineBridge()
        for ch in "vieejt" { _ = engine.feed(char: ch) }
        XCTAssertTrue(engine.isComposing)
        XCTAssertEqual(engine.currentOutput(), "việt")
        XCTAssertEqual(engine.rawChars(), "vieejt")

        let (bs, out) = engine.commit()
        XCTAssertEqual(bs, 0)
        XCTAssertEqual(out, "")
        XCTAssertFalse(engine.isComposing)
    }

    func test_commitWithNothingComposed() {
        let engine = EngineBridge()
        let (bs, out) = engine.commit()
        XCTAssertEqual(bs, 0)
        XCTAssertEqual(out, "")
        XCTAssertFalse(engine.isComposing)
    }

    func test_resetClearsComposingState() {
        let engine = EngineBridge()
        for ch in "vieej" { _ = engine.feed(char: ch) }
        XCTAssertTrue(engine.isComposing)

        engine.reset()
        XCTAssertFalse(engine.isComposing)

        // After a reset the engine starts fresh — no stale transforms.
        let (bs, out) = engine.feed(char: "a")
        XCTAssertEqual(bs, 0)
        XCTAssertEqual(out, "a")
    }

    func test_introspectionAfterComposition() {
        let engine = EngineBridge()
        for ch in "vieejt" { _ = engine.feed(char: ch) }
        XCTAssertEqual(engine.committedText(), "")
        XCTAssertEqual(engine.currentOutput(), "việt")
        XCTAssertEqual(engine.rawChars(), "vieejt")
        XCTAssertTrue(engine.isComposing)
    }

    func test_editAt_declinesWhenNothingCommitted() {
        let engine = EngineBridge()
        // No committed words yet — any caretBack must decline.
        XCTAssertNil(engine.editAt(caretBack: 0, char: "s"))
        XCTAssertNil(engine.editAt(caretBack: 1, char: "s"))
        // Negative caretBack is invalid by contract.
        XCTAssertNil(engine.editAt(caretBack: -1, char: "s"))
        // Non-ASCII keys are not feedable — declined.
        XCTAssertNil(engine.editAt(caretBack: 0, char: "ế"))
    }

    func test_editAt_offBoundaryDeclines() {
        let engine = EngineBridge()
        for ch in "don" { _ = engine.feed(char: ch) }
        _ = engine.commit() // commits "don"; caret 1 right of the word end

        // caretBack 1 is mid-word ("don" ends at 0) — declined.
        XCTAssertNil(engine.editAt(caretBack: 1, char: "s"))
        // caretBack 0 = the newest word's end → handled.
        XCTAssertNotNil(engine.editAt(caretBack: 0, char: "s"))
    }

    func test_inputMethodSwitch_changesOutput() {
        // VNI maps tone digits, not Telex letters: "viee1" in VNI keeps the
        // raw letters (e is not a Telex key there), proving the method switch
        // reached the engine.
        let telex = EngineBridge()
        telex.setInputMethod(.telex)
        var screen = ""
        for ch in "viees" {
            let (bs, out) = telex.feed(char: ch)
            screen = String(screen.dropLast(bs)) + out
        }
        XCTAssertEqual(screen, "viế")

        let vni = EngineBridge()
        vni.setInputMethod(.vni)
        screen = ""
        for ch in "vie61" {
            let (bs, out) = vni.feed(char: ch)
            screen = String(screen.dropLast(bs)) + out
        }
        XCTAssertEqual(screen, "viế")
    }

    func test_feed_preservesUppercaseRawKey() {
        // The engine tracks case from the raw key byte — an uppercase 'A'
        // must stay uppercase on screen (auto-capitalize composes on top).
        let engine = EngineBridge()
        let (bs, out) = engine.feed(char: "A")
        XCTAssertEqual(bs, 0)
        XCTAssertEqual(out, "A")
    }
}
