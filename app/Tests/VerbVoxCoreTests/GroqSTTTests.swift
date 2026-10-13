import XCTest
@testable import VerbVoxCore

final class GroqSTTTests: XCTestCase {
    override func setUp() { MockURLProtocol.reset() }
    override func tearDown() { MockURLProtocol.reset() }

    func testRequestShape() async throws {
        MockURLProtocol.stub(json: #"{"text":"transcribed"}"#)
        let stt = GroqSTT(apiKey: "test-key", model: "whisper-large-v3-turbo",
                          session: MockURLProtocol.makeSession())

        let result = try await stt.transcribe(wav: Data("WAV".utf8), language: nil)

        let request = try XCTUnwrap(MockURLProtocol.lastRequest)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.absoluteString,
                       "https://api.groq.com/openai/v1/audio/transcriptions")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")
        XCTAssertTrue(request.value(forHTTPHeaderField: "Content-Type")?
            .hasPrefix("multipart/form-data; boundary=") ?? false)

        let body = String(data: try XCTUnwrap(MockURLProtocol.lastBody), encoding: .utf8) ?? ""
        XCTAssertTrue(body.contains(#"name="file"; filename="audio.wav""#))
        XCTAssertTrue(body.contains(#"name="model""#))
        XCTAssertTrue(body.contains("\r\n\r\nwhisper-large-v3-turbo\r\n"))
        XCTAssertEqual(result.text, "transcribed")
    }
}
