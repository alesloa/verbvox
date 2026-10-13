import XCTest
import AVFoundation
@testable import VerbVoxCore

final class SystemTTSTests: XCTestCase {

    private func assertSegments(_ actual: [(TTSLang, String)],
                               _ expected: [(TTSLang, String)],
                               file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(actual.count, expected.count, "segment count", file: file, line: line)
        for (a, e) in zip(actual, expected) {
            XCTAssertEqual(a.0, e.0, "lang", file: file, line: line)
            XCTAssertEqual(a.1, e.1, "text", file: file, line: line)
        }
    }

    func testMixedEnglishSpanishEnglish() {
        assertSegments(
            SystemTTS.parseSegments("a [ES]hola[/ES] b"),
            [(.english, "a"), (.spanish, "hola"), (.english, "b")])
    }

    func testNoTagsIsAllEnglish() {
        assertSegments(
            SystemTTS.parseSegments("just plain english"),
            [(.english, "just plain english")])
    }

    func testLeadingSpanish() {
        assertSegments(
            SystemTTS.parseSegments("[ES]hola[/ES] world"),
            [(.spanish, "hola"), (.english, "world")])
    }

    func testEmptyEnglishBetweenTagsDropped() {
        assertSegments(
            SystemTTS.parseSegments("[ES]uno[/ES][ES]dos[/ES]"),
            [(.spanish, "uno"), (.spanish, "dos")])
    }

    func testMultilineSpanishCapture() {
        assertSegments(
            SystemTTS.parseSegments("start [ES]línea uno\nlínea dos[/ES] end"),
            [(.english, "start"), (.spanish, "línea uno\nlínea dos"), (.english, "end")])
    }

    func testWPMRateWithinBounds() {
        let slow = SystemTTS.rate(forWPM: 90)
        let fast = SystemTTS.rate(forWPM: 500)
        XCTAssertGreaterThanOrEqual(slow, AVSpeechUtteranceMinimumSpeechRate)
        XCTAssertLessThanOrEqual(fast, AVSpeechUtteranceMaximumSpeechRate)
        XCTAssertGreaterThan(SystemTTS.rate(forWPM: 300), SystemTTS.rate(forWPM: 150))
    }
}
