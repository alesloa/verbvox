import XCTest
@testable import VerbVoxCore

/// The supervisor client that starts/stops the user's EXTERNAL whisper-server by
/// asking the already-running `whisperctl` panel over HTTP. Only the request shape
/// and the status decoding are tested.
final class WhisperServerControlTests: XCTestCase {

    private var session: URLSession!

    override func setUp() {
        super.setUp()
        MockURLProtocol.reset()
        session = MockURLProtocol.makeSession()
    }

    override func tearDown() {
        MockURLProtocol.reset()
        super.tearDown()
    }

    private func control(_ base: String = "http://127.0.0.1:8722") -> WhisperServerControl {
        WhisperServerControl(baseURL: base, session: session)
    }

    func testStartPostsToApiStart() async throws {
        MockURLProtocol.stub(json: #"{"ok":true}"#)
        try await control().start()

        let request = try XCTUnwrap(MockURLProtocol.lastRequest)
        XCTAssertEqual(request.url?.absoluteString, "http://127.0.0.1:8722/api/start")
        XCTAssertEqual(request.httpMethod, "POST")
    }

    func testStopPostsToApiStop() async throws {
        MockURLProtocol.stub(json: #"{"ok":true}"#)
        try await control().stop()

        let request = try XCTUnwrap(MockURLProtocol.lastRequest)
        XCTAssertEqual(request.url?.absoluteString, "http://127.0.0.1:8722/api/stop")
        XCTAssertEqual(request.httpMethod, "POST")
    }

    func testTrailingSlashInBaseURLIsNormalized() async throws {
        MockURLProtocol.stub(json: #"{"ok":true}"#)
        try await control("http://127.0.0.1:8722/").start()

        let request = try XCTUnwrap(MockURLProtocol.lastRequest)
        XCTAssertEqual(request.url?.absoluteString, "http://127.0.0.1:8722/api/start")
    }

    func testStatusGetsApiStatusAndDecodesRunning() async throws {
        MockURLProtocol.stub(json: #"{"running":true,"healthy":true,"pid":123}"#)
        let status = try await control().status()

        let request = try XCTUnwrap(MockURLProtocol.lastRequest)
        XCTAssertEqual(request.url?.absoluteString, "http://127.0.0.1:8722/api/status")
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertTrue(status.running)
        XCTAssertTrue(status.healthy)
    }

    func testStatusDecodesStoppedServer() async throws {
        MockURLProtocol.stub(json: #"{"running":false,"healthy":false,"pid":null}"#)
        let status = try await control().status()
        XCTAssertFalse(status.running)
        XCTAssertFalse(status.healthy)
    }

    func testStatusDecodesPidUptimeAndLoadedModel() async throws {
        MockURLProtocol.stub(json: #"""
        {"running":true,"healthy":true,"pid":71127,"uptimeSec":842,
         "whisperUrl":"http://0.0.0.0:8080",
         "config":{"whisper":{"model":"ggml-large-v3-turbo.bin"}}}
        """#)
        let status = try await control().status()
        XCTAssertEqual(status.pid, 71127)
        XCTAssertEqual(status.uptimeSec, 842)
        XCTAssertEqual(status.model, "ggml-large-v3-turbo.bin")
        XCTAssertEqual(status.whisperURL, "http://0.0.0.0:8080")
    }

    func testModelsGetsApiModelsAndDecodesInstalled() async throws {
        MockURLProtocol.stub(json: #"""
        {"installed":[{"file":"ggml-base.en.bin","name":"base.en","sizeMB":141},
                      {"file":"ggml-large-v3-turbo.bin","name":"large-v3-turbo","sizeMB":1549}],
         "available":["tiny","base"]}
        """#)
        let models = try await control().models()

        let request = try XCTUnwrap(MockURLProtocol.lastRequest)
        XCTAssertEqual(request.url?.absoluteString, "http://127.0.0.1:8722/api/models")
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(models.map(\.file), ["ggml-base.en.bin", "ggml-large-v3-turbo.bin"])
        XCTAssertEqual(models.map(\.name), ["base.en", "large-v3-turbo"])
        XCTAssertEqual(models.map(\.sizeMB), [141, 1549])
    }

    func testModelsIsEmptyWhenNoneInstalled() async throws {
        MockURLProtocol.stub(json: #"{"installed":[],"available":["tiny"]}"#)
        let models = try await control().models()
        XCTAssertTrue(models.isEmpty)
    }

    func testSetModelPostsTheModelFileToConfig() async throws {
        MockURLProtocol.stub(json: #"{"ok":true,"applied":"hot-swapped"}"#)
        try await control().setModel("ggml-large-v3-turbo.bin")

        let request = try XCTUnwrap(MockURLProtocol.lastRequest)
        XCTAssertEqual(request.url?.absoluteString, "http://127.0.0.1:8722/api/config")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")

        let body = try XCTUnwrap(MockURLProtocol.lastBody)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: body) as? [String: Any])
        let whisper = try XCTUnwrap(object["whisper"] as? [String: Any])
        XCTAssertEqual(whisper["model"] as? String, "ggml-large-v3-turbo.bin")
        // Only the model is sent, so host/port/threads keep their saved values.
        XCTAssertEqual(whisper.count, 1)
        XCTAssertEqual(object.count, 1)
    }

    func testNonSuccessStatusThrows() async {
        MockURLProtocol.stub(status: 500, json: #"{"ok":false,"msg":"boom"}"#)
        do {
            try await control().start()
            XCTFail("expected an HTTP error")
        } catch {
            guard case ProviderError.http(let code, _) = error else {
                return XCTFail("expected ProviderError.http, got \(error)")
            }
            XCTAssertEqual(code, 500)
        }
    }

    func testInvalidBaseURLThrows() async {
        do {
            try await control("not a url").start()
            XCTFail("expected a decode error")
        } catch {
            guard case ProviderError.decode = error else {
                return XCTFail("expected ProviderError.decode, got \(error)")
            }
        }
    }
}

/// How the Whisper tab labels a model. whisper.cpp marks English-only weights
/// with a `.en` suffix on the model name; everything else is multilingual.
final class WhisperModelTests: XCTestCase {

    private func model(_ name: String) -> WhisperServerControl.Model {
        WhisperServerControl.Model(file: "ggml-\(name).bin", name: name, sizeMB: 0)
    }

    func testDotEnSuffixIsEnglishOnly() {
        XCTAssertTrue(model("medium.en").isEnglishOnly)
        XCTAssertTrue(model("base.en").isEnglishOnly)
    }

    func testPlainNameIsMultilingual() {
        XCTAssertFalse(model("medium").isEnglishOnly)
        XCTAssertFalse(model("large-v3-turbo").isEnglishOnly)
    }

    // "large-v3" ends in a digit, not ".en" — the check must not match on a dot
    // anywhere in the name.
    func testDottedButNotEnglishNameIsMultilingual() {
        XCTAssertFalse(model("large-v3.5").isEnglishOnly)
    }
}

/// The panel address the control client targets, read from config with the
/// whisperctl default (`http://127.0.0.1:8722`).
@MainActor
final class WhisperControlURLTests: XCTestCase {

    func testDefaultsToLocalPanelPort() {
        let app = AppState()
        app.config[ConfigCatalog.controlURLKey] = nil
        XCTAssertEqual(app.whisperControlURL, "http://127.0.0.1:8722")
    }

    func testUsesConfiguredPanelURL() {
        let app = AppState()
        app.config[ConfigCatalog.controlURLKey] = "http://192.168.1.5:8722"
        XCTAssertEqual(app.whisperControlURL, "http://192.168.1.5:8722")
    }

    func testBlankConfigFallsBackToDefault() {
        let app = AppState()
        app.config[ConfigCatalog.controlURLKey] = ""
        XCTAssertEqual(app.whisperControlURL, "http://127.0.0.1:8722")
    }
}
