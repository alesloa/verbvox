import XCTest
@testable import VerbVoxCore

final class WhisperServerSTTTests: XCTestCase {
    override func setUp() { MockURLProtocol.reset() }
    override func tearDown() { MockURLProtocol.reset() }

    func testRequestShape() async throws {
        MockURLProtocol.stub(json: #"{"text":"hello world","language":"en"}"#)
        let stt = WhisperServerSTT(url: "http://test.local", session: MockURLProtocol.makeSession())

        _ = try await stt.transcribe(wav: Data("WAVBYTES".utf8), language: nil)

        let request = try XCTUnwrap(MockURLProtocol.lastRequest)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.absoluteString, "http://test.local/inference")
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
        XCTAssertTrue(request.value(forHTTPHeaderField: "Content-Type")?
            .hasPrefix("multipart/form-data; boundary=") ?? false)

        let body = String(data: try XCTUnwrap(MockURLProtocol.lastBody), encoding: .utf8) ?? ""
        XCTAssertTrue(body.contains(#"name="file"; filename="audio.wav""#))
        XCTAssertTrue(body.contains("WAVBYTES"))
        XCTAssertTrue(body.contains(#"name="response_format""#))
        XCTAssertTrue(body.contains("\r\n\r\njson\r\n"))
        XCTAssertTrue(body.contains(#"name="language""#))
        XCTAssertTrue(body.contains("\r\n\r\nauto\r\n"))
    }

    func testProvidedLanguageOverridesAuto() async throws {
        MockURLProtocol.stub(json: #"{"text":"hola","language":"es"}"#)
        let stt = WhisperServerSTT(url: "http://test.local", session: MockURLProtocol.makeSession())

        _ = try await stt.transcribe(wav: Data(), language: "es")

        let body = String(data: try XCTUnwrap(MockURLProtocol.lastBody), encoding: .utf8) ?? ""
        XCTAssertTrue(body.contains("\r\n\r\nes\r\n"))
        XCTAssertFalse(body.contains("\r\n\r\nauto\r\n"))
    }

    func testParsesResponse() async throws {
        MockURLProtocol.stub(json: #"{"text":"  hello\nworld  ","language":"en"}"#)
        let stt = WhisperServerSTT(url: "http://test.local", session: MockURLProtocol.makeSession())

        let result = try await stt.transcribe(wav: Data(), language: nil)
        XCTAssertEqual(result.text, "hello world")   // trimmed + newline collapsed
        XCTAssertEqual(result.detectedLanguage, "en")
    }

    func testHTTPErrorThrows() async throws {
        MockURLProtocol.stub(status: 500, json: #"{"error":"boom"}"#)
        let stt = WhisperServerSTT(url: "http://test.local", session: MockURLProtocol.makeSession())
        do {
            _ = try await stt.transcribe(wav: Data(), language: nil)
            XCTFail("expected throw")
        } catch let ProviderError.http(code, _) {
            XCTAssertEqual(code, 500)
        }
    }
}
