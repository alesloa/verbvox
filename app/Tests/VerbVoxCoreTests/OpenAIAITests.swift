import XCTest
@testable import VerbVoxCore

final class OpenAIAITests: XCTestCase {
    override func setUp() { MockURLProtocol.reset() }
    override func tearDown() { MockURLProtocol.reset() }

    func testRequestShapeAndParse() async throws {
        MockURLProtocol.stub(json: #"{"choices":[{"message":{"content":"done"}}]}"#)
        let ai = OpenAIAI(apiKey: "test-key", model: "gpt-4o-mini",
                          session: MockURLProtocol.makeSession())

        let out = try await ai.complete(system: "SYS", user: "USER",
                                        temperature: 0.3, maxTokens: 2000)

        let request = try XCTUnwrap(MockURLProtocol.lastRequest)
        XCTAssertEqual(request.url?.absoluteString,
                       "https://api.openai.com/v1/chat/completions")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")

        let json = try JSONSerialization.jsonObject(
            with: try XCTUnwrap(MockURLProtocol.lastBody)) as! [String: Any]
        XCTAssertEqual(json["model"] as? String, "gpt-4o-mini")
        XCTAssertEqual(out, "done")
    }
}
