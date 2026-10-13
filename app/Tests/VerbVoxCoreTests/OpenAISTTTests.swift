import XCTest
@testable import VerbVoxCore

final class OpenAISTTTests: XCTestCase {
    override func setUp() { MockURLProtocol.reset() }
    override func tearDown() { MockURLProtocol.reset() }

    func testRequestShape() async throws {
        MockURLProtocol.stub(json: #"{"text":"hi there"}"#)
        let stt = OpenAISTT(apiKey: "test-key", model: "whisper-1",
                            session: MockURLProtocol.makeSession())

        let result = try await stt.transcribe(wav: Data("WAV".utf8), language: nil)

        let request = try XCTUnwrap(MockURLProtocol.lastRequest)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.absoluteString,
                       "https://api.openai.com/v1/audio/transcriptions")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")

        let body = String(data: try XCTUnwrap(MockURLProtocol.lastBody), encoding: .utf8) ?? ""
        XCTAssertTrue(body.contains(#"name="file"; filename="audio.wav""#))
        XCTAssertTrue(body.contains("\r\n\r\nwhisper-1\r\n"))
        XCTAssertEqual(result.text, "hi there")
    }
}
