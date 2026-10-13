import XCTest
@testable import VerbVoxCore

/// Test-only AI provider: records how it was called and returns a fixed reply
/// (or throws a supplied error). Not production code.
private final class StubAI: AIProvider {
    let reply: String
    let error: Error?
    private(set) var called = false
    private(set) var lastSystem: String?
    private(set) var lastUser: String?
    private(set) var lastTemperature: Double?
    private(set) var lastMaxTokens: Int?

    init(reply: String = "", error: Error? = nil) {
        self.reply = reply
        self.error = error
    }

    func complete(system: String, user: String, temperature: Double, maxTokens: Int) async throws -> String {
        called = true
        lastSystem = system
        lastUser = user
        lastTemperature = temperature
        lastMaxTokens = maxTokens
        if let error { throw error }
        return reply
    }
}

private struct StubError: Error {}

final class AICleanupTests: XCTestCase {

    private func makeCleanup(_ stub: StubAI,
                             template: @escaping (String) -> String? = { _ in "{text}" },
                             minWords: Int = 8) -> AICleanup {
        AICleanup(provider: stub,
                  promptBuilder: PromptBuilder(template),
                  minWords: minWords,
                  contextEnabled: true,
                  translationEnabled: true)
    }

    func testShortTextSkipsAI() async throws {
        let stub = StubAI(reply: "SHOULD NOT RUN")
        let out = try await makeCleanup(stub).run(text: "hi there", app: "Notes")
        XCTAssertEqual(out, "hi there")   // below min words, not a question/translate
        XCTAssertFalse(stub.called)
    }

    func testLongTextCallsAI() async throws {
        let stub = StubAI(reply: "cleaned")
        let out = try await makeCleanup(stub)
            .run(text: "this is a fairly long sentence with many words here", app: "Notes")
        XCTAssertEqual(out, "cleaned")
        XCTAssertTrue(stub.called)
    }

    // Short text is NOT skipped when the context is an AI question.
    func testShortAiQuestionStillCallsAI() async throws {
        let stub = StubAI(reply: "answer")
        let out = try await makeCleanup(stub).run(text: "hey claude hi", app: "Notes")
        XCTAssertEqual(out, "answer")
        XCTAssertTrue(stub.called)
    }

    // Short text is NOT skipped when the context is a translation.
    func testShortTranslateStillCallsAI() async throws {
        let stub = StubAI(reply: "traducido")
        let out = try await makeCleanup(stub).run(text: "translate this to spanish", app: "Notes")
        XCTAssertEqual(out, "traducido")
        XCTAssertTrue(stub.called)
    }

    // On provider error, fall back to the original text (Python behavior).
    func testProviderErrorFallsBackToOriginal() async throws {
        let stub = StubAI(error: StubError())
        let text = "this is a fairly long sentence with many words here"
        let out = try await makeCleanup(stub).run(text: text, app: "Notes")
        XCTAssertEqual(out, text)
        XCTAssertTrue(stub.called)
    }

    // The built prompt is what gets sent as the user message, with Python's
    // fixed system prompt / temperature / max tokens.
    func testPromptAndParamsPassedToProvider() async throws {
        let stub = StubAI(reply: "ok")
        let text = "this is a fairly long sentence with many words here"
        _ = try await makeCleanup(stub, template: { _ in "PROMPT:{text}" }).run(text: text, app: "Notes")
        XCTAssertEqual(stub.lastUser, "PROMPT:\(text)")
        XCTAssertEqual(stub.lastSystem, "You are a helpful AI assistant. Follow instructions exactly.")
        XCTAssertEqual(stub.lastTemperature, 0.3)
        XCTAssertEqual(stub.lastMaxTokens, 2000)
    }
}
