import XCTest
@testable import VerbVoxCore

/// Which whisper the app dictates through (built-in engine vs the user's own
/// server), the first-run default, and the 15-second takeover rule.
@MainActor
final class WhisperSourceTests: XCTestCase {

    private let provider = ConfigCatalog.sttProviderKey
    private let mode = ConfigCatalog.serverModeKey
    private let url = ConfigCatalog.serverURLKey

    // MARK: Source

    func testFreshConfigUsesTheBuiltinEngine() {
        XCTAssertTrue(WhisperSource.usesBuiltin([:]))
        XCTAssertFalse(WhisperSource.usesExternal([:]))
    }

    func testLocalServerWithAnAddressIsExternal() {
        let config = [mode: "local", url: "http://127.0.0.1:8080"]
        XCTAssertTrue(WhisperSource.usesExternal(config))
        XCTAssertFalse(WhisperSource.usesBuiltin(config))
    }

    func testServerModeWithoutAnAddressStaysOnTheBuiltinEngine() {
        let config = [mode: "remote", url: "  "]
        XCTAssertFalse(WhisperSource.usesExternal(config))
        XCTAssertTrue(WhisperSource.usesBuiltin(config))
    }

    func testCloudProviderUsesNeither() {
        let config = [provider: "groq", mode: "builtin"]
        XCTAssertFalse(WhisperSource.usesBuiltin(config))
        XCTAssertFalse(WhisperSource.usesExternal(config))
    }

    // MARK: First-run default

    func testNewDatabaseStartsOnTheBuiltinEngine() {
        XCTAssertEqual(WhisperSource.initialMode([:]), "builtin")
    }

    func testDatabaseThatAlreadyPointsAtAServerKeepsIt() {
        XCTAssertEqual(WhisperSource.initialMode([url: "http://127.0.0.1:8080"]), "local")
    }

    func testSavedModeIsNeverRewritten() {
        XCTAssertNil(WhisperSource.initialMode([mode: "remote", url: "http://10.0.0.2:8080"]))
    }

    // MARK: Takeover

    func testServerMustStayDownForTheGracePeriod() {
        var watch = ExternalServerWatch()
        let start = Date(timeIntervalSince1970: 1000)
        XCTAssertFalse(watch.observe(ready: false, at: start))
        XCTAssertFalse(watch.observe(ready: false, at: start.addingTimeInterval(14)))
        XCTAssertFalse(watch.covering)
        XCTAssertTrue(watch.observe(ready: false, at: start.addingTimeInterval(15)))
        XCTAssertTrue(watch.covering)
    }

    func testABriefAnswerRestartsTheGracePeriod() {
        var watch = ExternalServerWatch()
        let start = Date(timeIntervalSince1970: 1000)
        _ = watch.observe(ready: false, at: start)
        _ = watch.observe(ready: true, at: start.addingTimeInterval(10))
        XCTAssertFalse(watch.observe(ready: false, at: start.addingTimeInterval(20)))
        XCTAssertFalse(watch.covering)
    }

    func testDictationGoesBackWhenTheServerAnswers() {
        var watch = ExternalServerWatch()
        let start = Date(timeIntervalSince1970: 1000)
        _ = watch.observe(ready: false, at: start)
        _ = watch.observe(ready: false, at: start.addingTimeInterval(16))
        XCTAssertTrue(watch.observe(ready: true, at: start.addingTimeInterval(21)))
        XCTAssertFalse(watch.covering)
    }

    // MARK: Engine gating

    func testHotkeyIsRefusedWhileTheBuiltinEngineIsNotReady() {
        let engine = DictationEngine()
        engine.builtinSpeech = SpeechEndpoint(url: nil, unavailable: "VerbVox is downloading its speech model (40%).")
        engine.handleStart(.noAI)
        XCTAssertEqual(engine.state, .idle)
        XCTAssertEqual(engine.lastError, "VerbVox is downloading its speech model (40%).")
    }

    func testTranscriptionTargetsTheBuiltinEngine() throws {
        let config = [url: "http://127.0.0.1:8080"]
        let ready = SpeechEndpoint(url: "http://127.0.0.1:51234", unavailable: nil)
        XCTAssertEqual(try DictationEngine.speechConfig(config, builtin: ready)[url], "http://127.0.0.1:51234")
        XCTAssertEqual(try DictationEngine.speechConfig(config, builtin: nil)[url], "http://127.0.0.1:8080")
        XCTAssertThrowsError(try DictationEngine.speechConfig(config, builtin: SpeechEndpoint(url: nil, unavailable: "starting")))
    }
}
