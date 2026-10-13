import XCTest
@testable import VerbVoxCore

final class ActionTypeDetectorTests: XCTestCase {

    func testEditingKeywordIsReplace() {
        XCTAssertEqual(ActionTypeDetector.detect("fix this"), .replace)
    }

    func testInformationalKeywordIsSpeak() {
        XCTAssertEqual(ActionTypeDetector.detect("what is this"), .speak)
    }

    func testUnknownDefaultsToSpeak() {
        XCTAssertEqual(ActionTypeDetector.detect("random"), .speak)
    }

    func testCaseInsensitive() {
        XCTAssertEqual(ActionTypeDetector.detect("Please REFACTOR the code"), .replace)
    }

    // Replace keywords are checked before speak keywords: a command containing
    // both resolves to replace.
    func testReplacePrecedesSpeak() {
        // "explain" (speak) + "improve" (replace) present → replace wins.
        XCTAssertEqual(ActionTypeDetector.detect("explain how to improve this"), .replace)
    }

    // Substring matching (Python uses `keyword in text`, not word boundaries).
    func testSubstringMatch() {
        // "exchange" contains the replace keyword "change".
        XCTAssertEqual(ActionTypeDetector.detect("exchange rates today"), .replace)
    }

    func testSpeakKeywordHowDoes() {
        XCTAssertEqual(ActionTypeDetector.detect("how does this function"), .speak)
    }
}
