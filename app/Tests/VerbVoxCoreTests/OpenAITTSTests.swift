import XCTest
@testable import VerbVoxCore

final class OpenAITTSTests: XCTestCase {
    override func setUp() { MockURLProtocol.reset() }
    override func tearDown() { MockURLProtocol.reset() }

    func testRequestShape() async throws {
        MockURLProtocol.stub(headers: ["Content-Type": "audio/mpeg"], body: Data("AUDIO".utf8))
        let tts = OpenAITTS(apiKey: "test-key", model: "tts-1", voice: "alloy",
                            session: MockURLProtocol.makeSession())

        let audio = try await tts.synthesize("hello world", voice: nil)

        let request = try XCTUnwrap(MockURLProtocol.lastRequest)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.absoluteString, "https://api.openai.com/v1/audio/speech")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")

        let json = try JSONSerialization.jsonObject(
            with: try XCTUnwrap(MockURLProtocol.lastBody)) as! [String: Any]
        XCTAssertEqual(json["model"] as? String, "tts-1")
        XCTAssertEqual(json["voice"] as? String, "alloy")
        XCTAssertEqual(json["input"] as? String, "hello world")

        XCTAssertEqual(audio, Data("AUDIO".utf8))
    }

    func testVoiceOverride() async throws {
        MockURLProtocol.stub(body: Data("A".utf8))
        let tts = OpenAITTS(apiKey: "test-key", model: "tts-1", voice: "alloy",
                            session: MockURLProtocol.makeSession())
        _ = try await tts.synthesize("hi", voice: "nova")
        let json = try JSONSerialization.jsonObject(
            with: try XCTUnwrap(MockURLProtocol.lastBody)) as! [String: Any]
        XCTAssertEqual(json["voice"] as? String, "nova")
    }
}
