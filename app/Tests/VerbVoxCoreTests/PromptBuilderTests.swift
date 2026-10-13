import XCTest
@testable import VerbVoxCore

final class PromptBuilderTests: XCTestCase {

    // MARK: Plan fixtures

    func testSubstitutesText() {
        let b = PromptBuilder { name in name == "default" ? "Clean: {text}" : nil }
        XCTAssertEqual(b.build(text: "hi", context: .default), "Clean: hi")
    }

    func testStripsTriggerForAiQuestion() {
        let b = PromptBuilder { _ in "Q: {text}" }
        XCTAssertEqual(b.build(text: "hey claude, what is X", context: .aiQuestion(trigger: "hey claude")),
                       "Q: what is X")
    }

    func testTranslateSubstitutesLanguage() {
        let b = PromptBuilder { _ in "To {target_language}: {text}" }
        XCTAssertEqual(b.build(text: "hola", context: .translate(language: "english")),
                       "To english: hola")
    }

    // MARK: Prompt-name mapping

    func testContextPromptNames() {
        let b = PromptBuilder { name in "name=\(name) {text}" }
        XCTAssertEqual(b.build(text: "body", context: .default), "name=default body")
        XCTAssertEqual(b.build(text: "body", context: .codePrompt), "name=code_prompt body")
        XCTAssertEqual(b.build(text: "body", context: .formalChat), "name=formal_chat body")
    }

    func testSpanishRoutesToDedicatedPromptAndKeepsLanguageCase() {
        // language "Spanish" (any case) → prompt_name "translate_to_spanish";
        // {target_language} is substituted with the original-case language.
        let b = PromptBuilder { name in name == "translate_to_spanish" ? "ES {target_language}: {text}" : nil }
        XCTAssertEqual(b.build(text: "hi", context: .translate(language: "Spanish")),
                       "ES Spanish: hi")
    }

    // MARK: Fallback

    func testFallbackWhenTemplateMissing() {
        let b = PromptBuilder { _ in nil }
        let expected = """
        Clean up this text. Remove filler words and pauses, fix grammar:

        "some text here"

        Return only the cleaned text, no explanations.
        """
        XCTAssertEqual(b.build(text: "some text here", context: .default), expected)
    }

    func testFallbackUsesStrippedAiQuestionText() {
        let b = PromptBuilder { _ in "" }  // empty string is treated as missing too
        let result = b.build(text: "hey ai, summarize this", context: .aiQuestion(trigger: "hey ai"))
        XCTAssertTrue(result.contains("\"summarize this\""), result)
        XCTAssertFalse(result.contains("hey ai"), result)
    }
}
