import XCTest
@testable import VerbVoxCore

final class ProviderFactoryTests: XCTestCase {

    private func factory(_ config: [String: String]) -> ProviderFactory {
        ProviderFactory(config: config)
    }

    // MARK: STT

    func testDefaultSTTIsWhisperServerWithConfiguredURL() throws {
        let f = factory([ConfigCatalog.serverURLKey: "http://192.168.1.5:8080"])
        let stt = try f.stt()
        let whisper = try XCTUnwrap(stt as? WhisperServerSTT)
        XCTAssertEqual(whisper.url, "http://192.168.1.5:8080")
    }

    func testDefaultSTTFallsBackToLocalURLWhenUnset() throws {
        let stt = try factory([:]).stt()
        let whisper = try XCTUnwrap(stt as? WhisperServerSTT)
        XCTAssertEqual(whisper.url, "http://127.0.0.1:8080")
    }

    func testAppleSpeechSTTSelected() throws {
        let f = factory([
            ConfigCatalog.sttProviderKey: "apple",
            ConfigCatalog.sttAppleLocaleKey: "en_US",
        ])
        let apple = try XCTUnwrap(try f.stt() as? AppleSpeechSTT)
        XCTAssertEqual(apple.configuredLocale, "en_US")
    }

    // Apple's on-device transcriber needs no API key, so an unset locale is fine
    // (it falls back to the system language at transcribe time).
    func testAppleSpeechSTTNeedsNoKeyOrLocale() throws {
        let apple = try XCTUnwrap(try factory([ConfigCatalog.sttProviderKey: "apple"]).stt() as? AppleSpeechSTT)
        XCTAssertEqual(apple.configuredLocale, "")
    }

    func testGroqSTTSelected() throws {
        let f = factory([
            ConfigCatalog.sttProviderKey: "groq",
            ConfigCatalog.groqKeyKey: "test-key",
            ConfigCatalog.sttGroqModelKey: "whisper-large-v3",
        ])
        let stt = try f.stt()
        let groq = try XCTUnwrap(stt as? GroqSTT)
        XCTAssertEqual(groq.model, "whisper-large-v3")
        XCTAssertEqual(groq.apiKey, "test-key")
    }

    func testGroqSTTUsesDefaultModel() throws {
        let f = factory([ConfigCatalog.sttProviderKey: "groq", ConfigCatalog.groqKeyKey: "test-key"])
        let groq = try XCTUnwrap(try f.stt() as? GroqSTT)
        XCTAssertEqual(groq.model, "whisper-large-v3-turbo")
    }

    func testOpenAISTTSelected() throws {
        let f = factory([ConfigCatalog.sttProviderKey: "openai", ConfigCatalog.openAIKeyKey: "test-key"])
        let openai = try XCTUnwrap(try f.stt() as? OpenAISTT)
        XCTAssertEqual(openai.model, "whisper-1")
    }

    func testDeepgramSTTSelected() throws {
        let f = factory([ConfigCatalog.sttProviderKey: "deepgram", ConfigCatalog.deepgramKeyKey: "test-key"])
        let dg = try XCTUnwrap(try f.stt() as? DeepgramSTT)
        XCTAssertEqual(dg.model, "nova-3")
    }

    func testCloudSTTMissingKeyThrows() {
        let f = factory([ConfigCatalog.sttProviderKey: "groq"])   // no key
        XCTAssertThrowsError(try f.stt()) { error in
            guard case ProviderError.missingKey("groq") = error else {
                return XCTFail("expected missingKey(groq), got \(error)")
            }
        }
    }

    func testEmptyKeyCountsAsMissing() {
        let f = factory([ConfigCatalog.sttProviderKey: "deepgram", ConfigCatalog.deepgramKeyKey: ""])
        XCTAssertThrowsError(try f.stt()) { error in
            guard case ProviderError.missingKey("deepgram") = error else {
                return XCTFail("expected missingKey(deepgram)")
            }
        }
    }

    // MARK: AI

    func testDefaultAIIsGroq() throws {
        let f = factory([ConfigCatalog.groqKeyKey: "test-key"])
        let groq = try XCTUnwrap(try f.ai() as? GroqAI)
        _ = groq   // default model applied internally
    }

    func testGeminiAISelected() throws {
        let f = factory([ConfigCatalog.providerKey: "gemini", ConfigCatalog.geminiKeyKey: "test-key"])
        XCTAssertNotNil(try f.ai() as? GeminiAI)
    }

    func testOpenAIAISelected() throws {
        let f = factory([ConfigCatalog.providerKey: "openai", ConfigCatalog.openAIKeyKey: "test-key"])
        XCTAssertNotNil(try f.ai() as? OpenAIAI)
    }

    func testDefaultAIMissingGroqKeyThrows() {
        let f = factory([:])
        XCTAssertThrowsError(try f.ai()) { error in
            guard case ProviderError.missingKey("groq") = error else {
                return XCTFail("expected missingKey(groq)")
            }
        }
    }

    // MARK: TTS

    func testDefaultTTSIsSystem() throws {
        XCTAssertNotNil(try factory([:]).tts() as? SystemTTS)
    }

    func testOpenAITTSSelected() throws {
        let f = factory([
            ConfigCatalog.ttsProviderKey: "openai",
            ConfigCatalog.openAIKeyKey: "test-key",
            ConfigCatalog.ttsOpenAIVoiceKey: "nova",
        ])
        let tts = try XCTUnwrap(try f.tts() as? OpenAITTS)
        XCTAssertEqual(tts.voice, "nova")
    }

    func testDeepgramTTSSelected() throws {
        let f = factory([ConfigCatalog.ttsProviderKey: "deepgram", ConfigCatalog.deepgramKeyKey: "test-key"])
        let tts = try XCTUnwrap(try f.tts() as? DeepgramTTS)
        XCTAssertEqual(tts.model, "aura-2-thalia-en")
    }

    func testCloudTTSMissingKeyThrows() {
        let f = factory([ConfigCatalog.ttsProviderKey: "openai"])
        XCTAssertThrowsError(try f.tts()) { error in
            guard case ProviderError.missingKey("openai") = error else {
                return XCTFail("expected missingKey(openai)")
            }
        }
    }

    // MARK: Keyless (no-AI) dictation

    // Part A: with a completely empty-keys config, plain no-AI dictation must still
    // work. The default STT (whisper server) and TTS (system) need NO key, while
    // `ai()` throws `.missingKey` — so `try?` yields nil and the Paster degrades
    // gracefully instead of blocking. This is the exact mechanism DictationEngine
    // relies on to never require a cloud key for raw dictation.
    func testEmptyKeysStillGivesKeylessSTTAndTTSWithNilableAI() throws {
        let f = factory([:])
        XCTAssertNotNil(try f.stt() as? WhisperServerSTT)   // keyless
        XCTAssertNotNil(try f.tts() as? SystemTTS)          // keyless
        XCTAssertNil(try? f.ai())                           // no key → nil, never blocks
    }

    // MARK: Database-backed convenience

    func testInitFromDatabase() throws {
        let db = try Database(path: ":memory:")
        try db.setConfig(ConfigCatalog.sttProviderKey, "deepgram", category: "stt")
        try db.setConfig(ConfigCatalog.deepgramKeyKey, "test-key", category: "api_keys")
        let f = try ProviderFactory(database: db)
        XCTAssertNotNil(try f.stt() as? DeepgramSTT)
    }
}
