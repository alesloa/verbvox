import XCTest
@testable import VerbVoxCore

final class GroqAITests: XCTestCase {
    override func setUp() { MockURLProtocol.reset() }
    override func tearDown() { MockURLProtocol.reset() }

    func testRequestShapeAndParse() async throws {
        MockURLProtocol.stub(json: #"{"choices":[{"message":{"content":"cleaned text"}}]}"#)
        let ai = GroqAI(apiKey: "test-key", model: "llama-3.3-70b-versatile",
                        session: MockURLProtocol.makeSession())

        let out = try await ai.complete(system: "SYS", user: "USER",
                                        temperature: 0.3, maxTokens: 2000)

        let request = try XCTUnwrap(MockURLProtocol.lastRequest)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.absoluteString,
                       "https://api.groq.com/openai/v1/chat/completions")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")

        let json = try JSONSerialization.jsonObject(
            with: try XCTUnwrap(MockURLProtocol.lastBody)) as! [String: Any]
        XCTAssertEqual(json["model"] as? String, "llama-3.3-70b-versatile")
        XCTAssertEqual(json["temperature"] as? Double, 0.3)
        XCTAssertEqual(json["max_tokens"] as? Int, 2000)
        let messages = json["messages"] as! [[String: String]]
        XCTAssertEqual(messages[0]["role"], "system")
        XCTAssertEqual(messages[0]["content"], "SYS")
        XCTAssertEqual(messages[1]["role"], "user")
        XCTAssertEqual(messages[1]["content"], "USER")

        XCTAssertEqual(out, "cleaned text")
    }

    func testStripsWrappingQuotes() async throws {
        MockURLProtocol.stub(json: #"{"choices":[{"message":{"content":"\"quoted\""}}]}"#)
        let ai = GroqAI(apiKey: "test-key", model: "m", session: MockURLProtocol.makeSession())
        let out = try await ai.complete(system: "s", user: "u", temperature: 0.3, maxTokens: 2000)
        XCTAssertEqual(out, "quoted")
    }

    func testHTTPErrorThrows() async throws {
        MockURLProtocol.stub(status: 401, json: #"{"error":"unauthorized"}"#)
        let ai = GroqAI(apiKey: "test-key", model: "m", session: MockURLProtocol.makeSession())
        do {
            _ = try await ai.complete(system: "s", user: "u", temperature: 0.3, maxTokens: 2000)
            XCTFail("expected throw")
        } catch let ProviderError.http(code, _) {
            XCTAssertEqual(code, 401)
        }
    }
}
