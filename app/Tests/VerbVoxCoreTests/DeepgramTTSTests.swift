import XCTest
@testable import VerbVoxCore

final class DeepgramTTSTests: XCTestCase {
    override func setUp() { MockURLProtocol.reset() }
    override func tearDown() { MockURLProtocol.reset() }

    func testRequestShape() async throws {
        MockURLProtocol.stub(headers: ["Content-Type": "audio/mpeg"], body: Data("AUDIO".utf8))
        let tts = DeepgramTTS(apiKey: "test-key", model: "aura-2-thalia-en",
                              session: MockURLProtocol.makeSession())

        let audio = try await tts.synthesize("speak this")

        let request = try XCTUnwrap(MockURLProtocol.lastRequest)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.absoluteString,
                       "https://api.deepgram.com/v1/speak?model=aura-2-thalia-en")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Token test-key")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")

        let json = try JSONSerialization.jsonObject(
            with: try XCTUnwrap(MockURLProtocol.lastBody)) as! [String: Any]
        XCTAssertEqual(json["text"] as? String, "speak this")

        XCTAssertEqual(audio, Data("AUDIO".utf8))
    }
}
