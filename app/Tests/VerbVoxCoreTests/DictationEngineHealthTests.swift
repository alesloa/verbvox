import XCTest
@testable import VerbVoxCore

/// Part B — the whisper-server reachability classifier. Pure (no network): given a
/// `URLSession` transport error, decide up/down exactly like v1's `checkServer`.
/// A live ping is exercised manually; only the classification is unit-tested.
@MainActor
final class DictationEngineHealthTests: XCTestCase {

    private func urlError(_ code: Int) -> NSError {
        NSError(domain: NSURLErrorDomain, code: code)
    }

    func testConnectionRefusedIsDown() {
        XCTAssertFalse(DictationEngine.serverReachable(afterError: urlError(NSURLErrorCannotConnectToHost)))
    }

    func testTimeoutIsDown() {
        XCTAssertFalse(DictationEngine.serverReachable(afterError: urlError(NSURLErrorTimedOut)))
    }

    func testNetworkConnectionLostIsDown() {
        XCTAssertFalse(DictationEngine.serverReachable(afterError: urlError(NSURLErrorNetworkConnectionLost)))
    }

    // A non-URL transport error (e.g. POSIX) is not a "server answered" case.
    func testNonURLErrorIsDown() {
        XCTAssertFalse(DictationEngine.serverReachable(afterError: NSError(domain: NSPOSIXErrorDomain, code: 61)))
    }

    // Any other resolved URL error (the server answered, even if oddly) is "up",
    // matching v1's semantics — only refused/timeout/dropped count as down.
    func testOtherURLErrorIsUp() {
        XCTAssertTrue(DictationEngine.serverReachable(afterError: urlError(NSURLErrorBadServerResponse)))
    }
}
