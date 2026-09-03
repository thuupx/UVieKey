import XCTest
@testable import UVieKey

/// Simulated-typing tests: feed character sequences through the real
/// Swift↔Rust engine and assert the reconstructed on-screen text.
/// Expectations are locked to the shipped v2.5.1 engine behavior.
final class EngineTypingTests: XCTestCase {
    func test_toneMarks() {
        XCTAssertEqual(typeString("chaof"), "chào")
        XCTAssertEqual(typeString("naof"), "nào")
        XCTAssertEqual(typeString("toans"), "toán")
        XCTAssertEqual(typeString("hoacs"), "hoác")
        XCTAssertEqual(typeString("ranhr"), "rảnh")
        XCTAssertEqual(typeString("taoj"), "tạo")
        XCTAssertEqual(typeString("tieengs"), "tiếng")
        XCTAssertEqual(typeString("as"), "á")
    }

    func test_hornModifier_w() {
        XCTAssertEqual(typeString("aw"), "ă")
        XCTAssertEqual(typeString("ow"), "ơ")
        XCTAssertEqual(typeString("uw"), "ư")
        XCTAssertEqual(typeString("w"), "ư")
        XCTAssertEqual(typeString("mw"), "mư")
        XCTAssertEqual(typeString("duowc"), "dươc")
        XCTAssertEqual(typeString("dduowc"), "đươc")
        XCTAssertEqual(typeString("duwowc"), "dươc")
        XCTAssertEqual(typeString("guwown"), "gươn")
        XCTAssertEqual(typeString("nguowif"), "người")
    }

    func test_bar_d() {
        XCTAssertEqual(typeString("dd"), "đ")
        XCTAssertEqual(typeString("ddang"), "đang")
    }

    func test_doubleVowel_circumflex() {
        XCTAssertEqual(typeString("aa"), "â")
        XCTAssertEqual(typeString("ee"), "ê")
        XCTAssertEqual(typeString("oo"), "ô")
        XCTAssertEqual(typeString("daya"), "dây")
        XCTAssertEqual(typeString("khoong"), "không")
    }

    func test_doubleToneCancel_restoresLiteral() {
        XCTAssertEqual(typeString("ass"), "as")
        XCTAssertEqual(typeString("aww"), "aw")
    }

    func test_uppercaseHandling() {
        XCTAssertEqual(typeString("AS"), "Á")
        XCTAssertEqual(typeString("As"), "Á")
        XCTAssertEqual(typeString("aS"), "á")
        XCTAssertEqual(typeString("VIEJS"), "VIEJS")
        XCTAssertEqual(typeString("Viets"), "Viets")
    }

    func test_englishDictionaryOverride_typesLiterally() {
        XCTAssertEqual(typeString("ghost"), "ghost")
        XCTAssertEqual(typeString("good"), "good")
        XCTAssertEqual(typeString("book"), "book")
        XCTAssertEqual(typeString("safari"), "safari")
        XCTAssertEqual(typeString("character"), "character")
    }

    func test_englishWithoutDictionary_keepsDocumentedBehavior() {
        // "user"/"banana" are excluded from the dictionary (V-C-V split of
        // valid syllables); "chaos"/"most" transform to real Vietnamese words;
        // "reset" is not in the dictionary and garbles — all documented,
        // intentionally locked so changes are conscious decisions.
        XCTAssertEqual(typeString("user"), "usẻ")
        XCTAssertEqual(typeString("banana"), "banana")
        XCTAssertEqual(typeString("chaos"), "cháo")
        XCTAssertEqual(typeString("most"), "mót")
        XCTAssertEqual(typeString("reset"), "rết")
    }

    func test_literalsAndDigits() {
        XCTAssertEqual(typeString("hello"), "hello")
        XCTAssertEqual(typeString("123"), "123")
        XCTAssertEqual(typeString("hello123"), "hello123")
        XCTAssertEqual(typeString("viet"), "viet")
        XCTAssertEqual(typeString("viets"), "viets")
    }

    func test_viet_encodings() {
        XCTAssertEqual(typeString("vieejt"), "việt")
        XCTAssertEqual(typeString("vieej"), "việ")
    }

    func test_vcvSplit() {
        // V-C-V: "nê" auto-commits when 'b' starts a new syllable.
        XCTAssertEqual(typeString("neebo"), "nêbo")
    }

    func test_secondWordAfterCommit() {
        let engine = EngineBridge()
        engine.setModernOrthography(true)
        var screen = ""
        for ch in "chaof" {
            let (bs, out) = engine.feed(char: ch)
            screen = String(screen.dropLast(bs)) + out
        }
        _ = engine.commit()
        screen += " "
        for ch in "roif" {
            let (bs, out) = engine.feed(char: ch)
            screen = String(screen.dropLast(bs)) + out
        }
        XCTAssertEqual(screen, "chào ròi")
    }

    func test_modernOrthography_tonePlacement() {
        XCTAssertEqual(typeString("hoaf", modern: true), "hoà")
        XCTAssertEqual(typeString("hoaf", modern: false), "hòa")
    }

    func test_vniMode() {
        XCTAssertEqual(typeString("a1", method: .vni), "á")
        XCTAssertEqual(typeString("a2", method: .vni), "à")
        XCTAssertEqual(typeString("aa8", method: .vni), "ă")
        XCTAssertEqual(typeString("dd9", method: .vni), "d")
        XCTAssertEqual(typeString("u7ow1", method: .vni), "u7ow1")
    }

    func test_simpleTelexMode() {
        XCTAssertEqual(typeString("as", method: .simpleTelex), "á")
        XCTAssertEqual(typeString("ass", method: .simpleTelex), "as")
        XCTAssertEqual(typeString("aa", method: .simpleTelex), "â")
        XCTAssertEqual(typeString("aw", method: .simpleTelex), "ă")
        XCTAssertEqual(typeString("vieejt", method: .simpleTelex), "việt")
    }
}
