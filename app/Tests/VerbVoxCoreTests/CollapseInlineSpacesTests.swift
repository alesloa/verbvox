import XCTest
@testable import VerbVoxCore

/// Guards the final space pass applied right before the text is pasted/typed.
final class CollapseInlineSpacesTests: XCTestCase {

    func testCollapsesDoubleSpace() {
        XCTAssertEqual(TranscriptCleaner.collapseInlineSpaces("this is  great"), "this is great")
    }

    func testCollapsesTripleSpace() {
        XCTAssertEqual(TranscriptCleaner.collapseInlineSpaces("this is   great"), "this is great")
    }

    func testCollapsesTabRun() {
        XCTAssertEqual(TranscriptCleaner.collapseInlineSpaces("this is \t great"), "this is great")
    }

    func testGapLeftByABlankReplacement() {
        // "damn" → "" leaves "well  that" behind; the pass repairs it.
        let filtered = ProfanityFilter.apply("well damn that", map: ["damn": ""])
        XCTAssertEqual(TranscriptCleaner.collapseInlineSpaces(filtered), "well that")
    }

    func testKeepsNewlines() {
        XCTAssertEqual(TranscriptCleaner.collapseInlineSpaces("one\ntwo"), "one\ntwo")
    }

    func testKeepsLeadingIndentation() {
        // Code indentation starts a line, so it is never collapsed.
        XCTAssertEqual(TranscriptCleaner.collapseInlineSpaces("func f() {\n    return 1\n}"),
                       "func f() {\n    return 1\n}")
    }

    func testLeavesSingleSpacesAlone() {
        XCTAssertEqual(TranscriptCleaner.collapseInlineSpaces("a b c"), "a b c")
    }

    func testEmptyStaysEmpty() {
        XCTAssertEqual(TranscriptCleaner.collapseInlineSpaces(""), "")
    }

    func testCollapsesFourSpaces() {
        XCTAssertEqual(TranscriptCleaner.collapseInlineSpaces("this is    great"), "this is great")
    }

    func testCollapsesLongRuns() {
        for n in 2...12 {
            let run = String(repeating: " ", count: n)
            XCTAssertEqual(TranscriptCleaner.collapseInlineSpaces("a" + run + "b"), "a b",
                           "run of \(n) spaces was not collapsed")
        }
    }

    func testCollapsesEveryGapInOneSentence() {
        XCTAssertEqual(TranscriptCleaner.collapseInlineSpaces("one  two   three    four"),
                       "one two three four")
    }

    func testCollapsesNonBreakingSpaces() {
        // U+00A0 arrives from AI cleanup and some transcripts; it still reads as a gap.
        XCTAssertEqual(TranscriptCleaner.collapseInlineSpaces("this is\u{00A0}\u{00A0}great"),
                       "this is great")
    }

    func testCollapsesMixedSpaceAndTabRun() {
        XCTAssertEqual(TranscriptCleaner.collapseInlineSpaces("this is \t \t great"), "this is great")
    }

    func testCollapsesRunBeforePunctuation() {
        XCTAssertEqual(TranscriptCleaner.collapseInlineSpaces("well   , yes"), "well , yes")
    }

    func testKeepsCarriageReturnLines() {
        XCTAssertEqual(TranscriptCleaner.collapseInlineSpaces("one\r\n    two"), "one\r\n    two")
    }
}
