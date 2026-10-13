import XCTest
@testable import VerbVoxCore

/// The menu-bar "History" / "Dictionary" shortcuts open Settings already focused
/// on the matching panel. The selected tab lives on AppState so the menu can set
/// it before the window appears.
@MainActor
final class SettingsNavigationTests: XCTestCase {

    func testDefaultsToHome() {
        let app = AppState()
        XCTAssertEqual(app.settingsSelection, .home)
    }

    func testShowSettingsSelectsHistory() {
        let app = AppState()
        app.showSettings(.history)
        XCTAssertEqual(app.settingsSelection, .history)
    }

    func testShowSettingsSelectsDictionary() {
        let app = AppState()
        app.showSettings(.dictionary)
        XCTAssertEqual(app.settingsSelection, .dictionary)
    }
}
