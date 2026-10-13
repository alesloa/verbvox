import XCTest
@testable import VerbVoxCore

final class ProfanityFilterTests: XCTestCase {

    func testSingleWordReplacementCaseInsensitive() {
        XCTAssertEqual(ProfanityFilter.apply("this is Damn good", map: ["damn": "darn"]), "this is darn good")
    }

    func testMultiWordReplacement() {
        let map = ["what the hell": "what the heck"]
        XCTAssertEqual(ProfanityFilter.apply("what the hell is this", map: map), "what the heck is this")
    }

    // filter_profanity ends with `.strip()` — the dictionary path does not.
    func testTrimsResult() {
        XCTAssertEqual(ProfanityFilter.apply("  clean text  ", map: [:]), "clean text")
    }

    func testLongestMatchFirst() {
        // Multi-word phrase must win over its single-word sub-key.
        let map = ["hell": "heck", "what the hell": "what the heck"]
        XCTAssertEqual(ProfanityFilter.apply("what the hell", map: map), "what the heck")
    }
}
