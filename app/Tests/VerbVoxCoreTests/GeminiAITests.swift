import XCTest
@testable import VerbVoxCore

final class GeminiAITests: XCTestCase {
    override func setUp() { MockURLProtocol.reset() }
    override func tearDown() { MockURLProtocol.reset() }

    func testRequestShapeAndParse() async throws {
        MockURLProtocol.stub(json: #"""
        {"candidates":[{"content":{"parts":[{"text":"cleaned"}]}}]}
        """#)
        let ai = GeminiAI(apiKey: "test-key", model: "gemini-2.5-flash",
                          session: MockURLProtocol.makeSession())

        let out = try await ai.complete(system: "SYS", user: "USER",
                                        temperature: 0.3, maxTokens: 6500)

        let request = try XCTUnwrap(MockURLProtocol.lastRequest)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.absoluteString,
                       "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=test-key")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")

        let json = try JSONSerialization.jsonObject(
            with: try XCTUnwrap(MockURLProtocol.lastBody)) as! [String: Any]
        let contents = json["contents"] as! [[String: Any]]
        let parts = contents[0]["parts"] as! [[String: String]]
        XCTAssertEqual(parts[0]["text"], "USER")
        let genConfig = json["generationConfig"] as! [String: Any]
        XCTAssertEqual(genConfig["maxOutputTokens"] as? Int, 6500)
        XCTAssertEqual(genConfig["temperature"] as? Double, 0.3)
        // System carried via systemInstruction so it is not lost.
        let sys = json["systemInstruction"] as! [String: Any]
        let sysParts = sys["parts"] as! [[String: String]]
        XCTAssertEqual(sysParts[0]["text"], "SYS")

        XCTAssertEqual(out, "cleaned")
    }

    func testStripsWrappingQuotes() async throws {
        MockURLProtocol.stub(json: #"""
        {"candidates":[{"content":{"parts":[{"text":"\"hola\""}]}}]}
        """#)
        let ai = GeminiAI(apiKey: "test-key", model: "gemini-2.5-flash",
                          session: MockURLProtocol.makeSession())
        let out = try await ai.complete(system: "", user: "u", temperature: 0.3, maxTokens: 6500)
        XCTAssertEqual(out, "hola")
    }

    func testEmptySystemOmitsSystemInstruction() async throws {
        MockURLProtocol.stub(json: #"""
        {"candidates":[{"content":{"parts":[{"text":"x"}]}}]}
        """#)
        let ai = GeminiAI(apiKey: "test-key", model: "gemini-2.5-flash",
                          session: MockURLProtocol.makeSession())
        _ = try await ai.complete(system: "", user: "u", temperature: 0.3, maxTokens: 6500)
        let json = try JSONSerialization.jsonObject(
            with: try XCTUnwrap(MockURLProtocol.lastBody)) as! [String: Any]
        XCTAssertNil(json["systemInstruction"])
    }
}
