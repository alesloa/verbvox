import XCTest
@testable import VerbVoxCore

final class TranscriptCleanerTests: XCTestCase {

    // Fixtures from Python `clean_transcription`.

    func testCollapsesSpacesAndFillers() {
        XCTAssertEqual(TranscriptCleaner.clean("so  um  I  uh think"), "so I think")
    }

    func testDotBeforeCapitalBecomesComma() {
        XCTAssertEqual(TranscriptCleaner.clean("hello . World"), "hello, world")
    }

    func testKeepsEllipsis() {
        XCTAssertEqual(TranscriptCleaner.clean("wait... really"), "wait... really")
    }

    // Additional branches surfaced by reading the Python.

    func testRemovesEveryFillerInList() {
        XCTAssertEqual(TranscriptCleaner.clean("er ah mm hmm uhh umm uhm done"), "done")
    }

    func testFillerRemovalIsCaseInsensitive() {
        XCTAssertEqual(TranscriptCleaner.clean("Um HELLO Uh there"), "HELLO there")
    }

    func testDoesNotStripFillerInsideWord() {
        // \b word boundaries: "um" inside "summer"/"umbrella" must survive.
        XCTAssertEqual(TranscriptCleaner.clean("summer umbrella"), "summer umbrella")
    }

    func testTrimsAndCollapsesWhitespace() {
        XCTAssertEqual(TranscriptCleaner.clean("   padded   text   "), "padded text")
    }

    func testEmptyStaysEmpty() {
        XCTAssertEqual(TranscriptCleaner.clean(""), "")
    }
}
