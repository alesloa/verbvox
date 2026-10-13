import XCTest
@testable import VerbVoxCore

final class ContextDetectorTests: XCTestCase {

    private func detect(_ text: String, app: String?,
                        translation: Bool = true, context: Bool = true) -> DictationContext {
        ContextDetector.detect(text, app: app, translationEnabled: translation, contextEnabled: context)
    }

    // MARK: Plan fixtures

    func testHeyAiQuestion() {
        XCTAssertEqual(detect("hey claude what is this", app: "Notes"),
                       .aiQuestion(trigger: "hey claude"))
    }

    func testTranslateNoWakeWord() {
        XCTAssertEqual(detect("translate this to spanish", app: nil),
                       .translate(language: "spanish"))
    }

    func testCodeEditor() {
        XCTAssertEqual(detect("some text", app: "Cursor"), .codePrompt)
    }

    func testChatApp() {
        XCTAssertEqual(detect("yo", app: "Slack"), .formalChat)
    }

    func testDisabledReturnsDefault() {
        XCTAssertEqual(detect("hey claude hi", app: "Slack", context: false), .default)
    }

    // MARK: Wake-word triggers

    func testTriggerListIsExhaustive() {
        for t in ["hey gemini", "hey claude", "hey chatgpt", "hey gpt", "hey ai",
                  "hey cloud", "hey flow", "hey flo", "hey flux"] {
            XCTAssertEqual(detect("\(t) tell me something", app: "Notes"),
                           .aiQuestion(trigger: t), "trigger \(t)")
        }
    }

    // Wake-word translate ("to spanish" contains-branch) — NOT gated on translationEnabled.
    func testWakeWordTranslateSpanishIgnoresTranslationFlag() {
        XCTAssertEqual(detect("hey claude, translate this to spanish", app: "Notes", translation: false),
                       .translate(language: "spanish"))
    }

    func testWakeWordTranslateEnglishContainsBranch() {
        XCTAssertEqual(detect("hey gpt translate to english now", app: "Notes"),
                       .translate(language: "english"))
    }

    // Wake-word translate to some other language via the regex branch.
    func testWakeWordTranslateOtherLanguageRegex() {
        XCTAssertEqual(detect("hey claude translate to french", app: "Notes"),
                       .translate(language: "french"))
    }

    // MARK: Translate without wake word

    func testTranslateThatDefaultsToEnglish() {
        // "translate that" with no explicit "to <lang>" → default english.
        XCTAssertEqual(detect("translate that", app: nil), .translate(language: "english"))
    }

    func testSayThisInLanguage() {
        XCTAssertEqual(detect("say this in german please", app: nil),
                       .translate(language: "german"))
    }

    func testTranslateThisToLanguageCaptures() {
        XCTAssertEqual(detect("translate this to italian", app: nil),
                       .translate(language: "italian"))
    }

    // Asymmetry in the Python: the startswith list accepts bare "translate to ",
    // but the capture regex requires "this"/"that", so a bare "translate to X"
    // falls back to english.
    func testBareTranslateToFallsBackToEnglish() {
        XCTAssertEqual(detect("translate to italian", app: nil),
                       .translate(language: "english"))
    }

    // Translation gated off → falls through to app detection.
    func testTranslateDisabledFallsThroughToCodeEditor() {
        XCTAssertEqual(detect("translate this to spanish", app: "Xcode", translation: false),
                       .codePrompt)
    }

    // MARK: App detection precedence

    func testCodeEditorSubstringMatch() {
        XCTAssertEqual(detect("hello world", app: "Visual Studio Code"), .codePrompt)
    }

    func testChatAppMultiWordName() {
        XCTAssertEqual(detect("hey there team", app: "Facebook Messenger"), .formalChat)
    }

    func testDefaultWhenNoAppMatch() {
        XCTAssertEqual(detect("just some normal words here", app: "Notes"), .default)
    }

    func testNilAppNormalTextIsDefault() {
        XCTAssertEqual(detect("normal words", app: nil), .default)
    }
}
