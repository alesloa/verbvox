import XCTest
@testable import VerbVoxCore

final class HotkeyTests: XCTestCase {

    func testParseSimpleCombo() {
        XCTAssertEqual(HotkeyCombo.parse("ctrl+alt"), HotkeyCombo([.ctrl, .alt]))
    }

    func testParseIsCaseAndWhitespaceInsensitive() {
        XCTAssertEqual(HotkeyCombo.parse(" CMD + Ctrl "), HotkeyCombo([.ctrl, .cmd]))
    }

    func testParseDropsInvalidTokens() {
        XCTAssertEqual(HotkeyCombo.parse("ctrl+bogus"), HotkeyCombo([.ctrl]))
    }

    func testParseEmptyYieldsEmptyCombo() {
        XCTAssertEqual(HotkeyCombo.parse(""), HotkeyCombo([]))
    }

    func testEngineStringUsesCanonicalOrder() {
        // Insertion order should not affect output.
        XCTAssertEqual(HotkeyCombo([.cmd, .ctrl]).engineString, "ctrl+cmd")
        XCTAssertEqual(HotkeyCombo([.alt, .ctrl]).engineString, "ctrl+alt")
        XCTAssertEqual(HotkeyCombo([.shift, .cmd, .ctrl, .alt]).engineString, "ctrl+alt+cmd+shift")
    }

    func testDisplaySymbolsUseMacOrder() {
        XCTAssertEqual(HotkeyCombo([.ctrl, .cmd]).displaySymbols, "⌃⌘")
        XCTAssertEqual(HotkeyCombo([.ctrl, .alt, .shift]).displaySymbols, "⌃⌥⇧")
    }

    func testRoundTripThroughEngineString() {
        let combo = HotkeyCombo([.ctrl, .shift])
        XCTAssertEqual(HotkeyCombo.parse(combo.engineString), combo)
    }
}
