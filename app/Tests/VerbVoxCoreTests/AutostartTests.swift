import XCTest
@testable import VerbVoxCore

/// The decision of whether to launch the engine on app open. Defaults to ON so a
/// fresh install "just works"; the Home toggle writes `engine.autostart=False` to
/// opt out.
@MainActor
final class AutostartTests: XCTestCase {

    func testDefaultsToTrueWhenUnset() {
        let app = AppState()
        app.config["engine.autostart"] = nil
        XCTAssertTrue(app.shouldAutostart)
    }

    func testFalseWhenDisabled() {
        let app = AppState()
        app.config["engine.autostart"] = "False"
        XCTAssertFalse(app.shouldAutostart)
    }

    func testTrueWhenEnabled() {
        let app = AppState()
        app.config["engine.autostart"] = "True"
        XCTAssertTrue(app.shouldAutostart)
    }
}
