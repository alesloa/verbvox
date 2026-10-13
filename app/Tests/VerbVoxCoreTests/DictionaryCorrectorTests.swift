import XCTest
@testable import VerbVoxCore

final class DictionaryCorrectorTests: XCTestCase {

    func testLongestMatchFirstCaseInsensitive() {
        let map = ["new york": "NYC", "york": "Yorkshire"]
        XCTAssertEqual(DictionaryCorrector.apply("i love New York", map: map), "i love NYC")
    }

    func testWordBoundary() {
        XCTAssertEqual(DictionaryCorrector.apply("teh theater", map: ["teh": "the"]), "the theater")
    }

    // Replacement text is inserted verbatim regardless of matched casing.
    func testReplacementCasingIsVerbatim() {
        XCTAssertEqual(DictionaryCorrector.apply("TEH cat", map: ["teh": "the"]), "the cat")
    }

    // Multi-word keys match across arbitrary whitespace (Python: \s+).
    // Only the matched phrase is rewritten; surrounding spacing is untouched.
    func testMultiWordMatchesAcrossWhitespace() {
        XCTAssertEqual(DictionaryCorrector.apply("hello  new   york", map: ["new york": "NYC"]), "hello  NYC")
    }

    // Empty map leaves text untouched (Python does not trim in dictionary path).
    func testEmptyMapPreservesText() {
        XCTAssertEqual(DictionaryCorrector.apply("  spaced  ", map: [:]), "  spaced  ")
    }

    // Regex-special characters in the key are escaped, not interpreted:
    // "a.b" must NOT match "axb" (the dot is literal, not "any char").
    func testSpecialCharsInKeyAreLiteral() {
        XCTAssertEqual(DictionaryCorrector.apply("axb stays", map: ["a.b": "REPL"]), "axb stays")
        XCTAssertEqual(DictionaryCorrector.apply("a.b goes", map: ["a.b": "REPL"]), "REPL goes")
    }
}
