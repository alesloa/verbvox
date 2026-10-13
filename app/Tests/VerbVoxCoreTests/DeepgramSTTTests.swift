import XCTest
@testable import VerbVoxCore

final class DeepgramSTTTests: XCTestCase {
    override func setUp() { MockURLProtocol.reset() }
    override func tearDown() { MockURLProtocol.reset() }

    func testRequestShapeAndRawBody() async throws {
        MockURLProtocol.stub(json: #"""
        {"results":{"channels":[{"detected_language":"en",
        "alternatives":[{"transcript":"raw audio words"}]}]}}
        """#)
        let stt = DeepgramSTT(apiKey: "test-key", model: "nova-3",
                              session: MockURLProtocol.makeSession())

        let result = try await stt.transcribe(wav: Data("RAWWAV".utf8), language: nil)

        let request = try XCTUnwrap(MockURLProtocol.lastRequest)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.absoluteString,
                       "https://api.deepgram.com/v1/listen?model=nova-3&detect_language=true")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Token test-key")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "audio/wav")

        // Raw WAV bytes as the body — not multipart.
        let body = try XCTUnwrap(MockURLProtocol.lastBody)
        XCTAssertEqual(body, Data("RAWWAV".utf8))

        XCTAssertEqual(result.text, "raw audio words")
        XCTAssertEqual(result.detectedLanguage, "en")
    }
}
