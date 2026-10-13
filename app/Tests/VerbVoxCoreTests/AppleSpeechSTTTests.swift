import XCTest
@testable import VerbVoxCore

/// Apple's on-device `SpeechTranscriber` (macOS 26+). The transcription itself
/// needs the OS and real audio, so only the pure decisions are unit-tested here:
/// which locale gets requested, and how the streamed result chunks become one
/// line of text. A live end-to-end run is exercised manually.
final class AppleSpeechLocaleTests: XCTestCase {

    private let system = Locale(identifier: "en_GB")

    func testExplicitLanguageWins() {
        let locale = AppleSpeechSTT.resolveLocale(requested: "es-ES", configured: "fr_FR", system: system)
        XCTAssertEqual(locale.identifier, "es-ES")
    }

    // The pipeline sends "auto" when no language is pinned (Python parity), which
    // means "let the provider decide", not "transcribe the language named auto".
    func testAutoFallsBackToConfiguredLocale() {
        let locale = AppleSpeechSTT.resolveLocale(requested: "auto", configured: "fr_FR", system: system)
        XCTAssertEqual(locale.identifier, "fr_FR")
    }

    func testNilFallsBackToConfiguredLocale() {
        let locale = AppleSpeechSTT.resolveLocale(requested: nil, configured: "fr_FR", system: system)
        XCTAssertEqual(locale.identifier, "fr_FR")
    }

    func testFallsBackToSystemLocaleWhenNothingConfigured() {
        let locale = AppleSpeechSTT.resolveLocale(requested: "auto", configured: "", system: system)
        XCTAssertEqual(locale.identifier, "en_GB")
    }

    // "auto" saved as the configured language has to read as "nobody picked",
    // the same way the caller's "auto" does. Taken literally it would ask the
    // framework for a locale named "auto" and the dictation would just fail.
    func testConfiguredAutoFallsBackToTheSystemLocale() {
        let locale = AppleSpeechSTT.resolveLocale(requested: nil, configured: "auto", system: system)
        XCTAssertEqual(locale.identifier, "en_GB")
    }

    func testBlankAndWhitespaceAreTreatedAsUnset() {
        let locale = AppleSpeechSTT.resolveLocale(requested: "  ", configured: "  ", system: system)
        XCTAssertEqual(locale.identifier, "en_GB")
    }
}

/// `SpeechTranscriber` streams results in chunks. The pipeline downstream expects
/// one single-line string, matching what `WhisperServerSTT` returns.
final class AppleSpeechTranscriptTests: XCTestCase {

    func testJoinsChunksWithASingleSpace() {
        let text = AppleSpeechSTT.joinChunks(["Hello there", "how are you"])
        XCTAssertEqual(text, "Hello there how are you")
    }

    func testTrimsEachChunkAndDropsEmptyOnes() {
        let text = AppleSpeechSTT.joinChunks(["  Hello  ", "", "   ", " world "])
        XCTAssertEqual(text, "Hello world")
    }

    func testCollapsesNewlinesIntoSpaces() {
        let text = AppleSpeechSTT.joinChunks(["first line\nsecond line"])
        XCTAssertEqual(text, "first line second line")
    }

    func testEmptyInputGivesEmptyString() {
        XCTAssertEqual(AppleSpeechSTT.joinChunks([]), "")
        XCTAssertEqual(AppleSpeechSTT.joinChunks(["", "  "]), "")
    }

    // Two chunks that already carry their own spacing must not double up.
    func testDoesNotProduceDoubleSpaces() {
        let text = AppleSpeechSTT.joinChunks(["one ", " two"])
        XCTAssertEqual(text, "one two")
    }
}

/// Locale identifiers come back from the framework as raw strings ("en_US").
/// The picker shows a readable name instead.
final class AppleSpeechLocaleNameTests: XCTestCase {

    func testNamesARegionalLocaleInEnglish() {
        XCTAssertEqual(AppleSpeechSTT.localeDisplayName("en_US"), "English (United States)")
    }

    func testHandlesHyphenatedIdentifiers() {
        XCTAssertEqual(AppleSpeechSTT.localeDisplayName("es-ES"), "Spanish (Spain)")
    }

    // An identifier the system cannot name should show as itself, not as blank.
    func testUnknownIdentifierFallsBackToItself() {
        XCTAssertEqual(AppleSpeechSTT.localeDisplayName("zz_ZZ"), "zz_ZZ")
    }
}

/// Apple's transcriber listens in exactly one language, so dictating Spanish
/// while it is set to English returns phonetic nonsense ("In talances, orders,
/// si puedo, ablard, in Español."). These decide when to re-run the audio under
/// a different installed language, which is what whisper's model did on its own.
final class AppleSpeechAutoDetectTests: XCTestCase {

    func testCollectsTheDistinctLanguageCodesOfInstalledLocales() {
        let codes = AppleSpeechSTT.languageCodes(of: ["en_US", "en_GB", "es_MX", "es_ES"])
        XCTAssertEqual(codes, ["en", "es"])
    }

    func testHandlesHyphenatedAndBareIdentifiers() {
        XCTAssertEqual(AppleSpeechSTT.languageCodes(of: ["es-ES", "fr"]), ["es", "fr"])
    }

    func testNoInstalledLocalesGivesNoCodes() {
        XCTAssertEqual(AppleSpeechSTT.languageCodes(of: []), [])
    }

    // The real string the English model produced from Spanish speech, taken from
    // the engine log. It has to read as Spanish or the retry never fires.
    func testDetectsSpanishInAMisheardSpanishTranscript() {
        let detected = AppleSpeechSTT.detectLanguage(in: "In talances, orders, si puedo, ablard, in Español.",
                                                     among: ["en", "es"],
                                                     minimumConfidence: 0.5)
        XCTAssertEqual(detected, "es")
    }

    func testDetectsEnglishInAnEnglishTranscript() {
        let detected = AppleSpeechSTT.detectLanguage(in: "All right, so I just disabled the whisper server.",
                                                     among: ["en", "es"],
                                                     minimumConfidence: 0.5)
        XCTAssertEqual(detected, "en")
    }

    func testEmptyTranscriptDetectsNothing() {
        XCTAssertNil(AppleSpeechSTT.detectLanguage(in: "   ", among: ["en", "es"], minimumConfidence: 0.5))
    }

    // One installed language means there is no second model to move to.
    func testASingleCandidateDetectsNothing() {
        XCTAssertNil(AppleSpeechSTT.detectLanguage(in: "Hola, buenos días.",
                                                   among: ["es"],
                                                   minimumConfidence: 0.5))
    }

    // A short word is weak evidence. Raising the bar has to suppress the guess.
    func testAWeakGuessIsRejected() {
        XCTAssertNil(AppleSpeechSTT.detectLanguage(in: "Hola.", among: ["en", "es"], minimumConfidence: 0.99))
    }

    func testRetriesInTheInstalledLocaleForTheDetectedLanguage() {
        let retry = AppleSpeechSTT.retryLocale(detected: "es",
                                               used: "en_US",
                                               installed: ["en_US", "es_ES", "es_MX"],
                                               preferredRegion: "MX")
        XCTAssertEqual(retry, "es_MX")
    }

    // No model for the user's own region, so any installed one beats English.
    func testFallsBackToAnyInstalledLocaleForThatLanguage() {
        let retry = AppleSpeechSTT.retryLocale(detected: "es",
                                               used: "en_US",
                                               installed: ["en_US", "es_CL", "es_ES"],
                                               preferredRegion: "MX")
        XCTAssertEqual(retry, "es_CL")
    }

    func testNoRetryWhenTheFirstPassAlreadyUsedThatLanguage() {
        XCTAssertNil(AppleSpeechSTT.retryLocale(detected: "en",
                                                used: "en_US",
                                                installed: ["en_US", "es_MX"],
                                                preferredRegion: "MX"))
    }

    func testNoRetryWhenNothingWasDetected() {
        XCTAssertNil(AppleSpeechSTT.retryLocale(detected: nil,
                                                used: "en_US",
                                                installed: ["en_US", "es_MX"],
                                                preferredRegion: "MX"))
    }

    func testNoRetryWhenThatLanguageIsNotInstalled() {
        XCTAssertNil(AppleSpeechSTT.retryLocale(detected: "fr",
                                                used: "en_US",
                                                installed: ["en_US", "es_MX"],
                                                preferredRegion: "MX"))
    }
}

/// Auto-detect only runs when the user has not pinned a language. Pinning one
/// has to stay honoured, otherwise the picker does nothing.
final class AppleSpeechAutoModeTests: XCTestCase {

    func testNothingConfiguredMeansDetectTheLanguage() {
        XCTAssertTrue(AppleSpeechSTT.shouldAutoDetect(requested: nil, configured: ""))
    }

    func testTheWordAutoMeansDetectTheLanguage() {
        XCTAssertTrue(AppleSpeechSTT.shouldAutoDetect(requested: "auto", configured: "  "))
    }

    func testAPinnedConfiguredLocaleTurnsDetectionOff() {
        XCTAssertFalse(AppleSpeechSTT.shouldAutoDetect(requested: nil, configured: "es_MX"))
    }

    func testAnExplicitRequestFromTheCallerTurnsDetectionOff() {
        XCTAssertFalse(AppleSpeechSTT.shouldAutoDetect(requested: "es-ES", configured: ""))
    }
}

/// Live end-to-end run against Apple's on-device transcriber. Skipped by default
/// because it needs the OS, a downloaded language model, and real audio. Run it
/// with:
///
///     VERBVOX_LIVE_APPLE_STT=1 swift test --filter AppleSpeechLiveTests
///
/// Defaults to the English JFK sample in the whisper.cpp checkout that
/// `scripts/whisper-engine.sh` makes (run `./build.sh` once). Override any of `VERBVOX_LIVE_APPLE_WAV`,
/// `VERBVOX_LIVE_APPLE_LOCALE` and `VERBVOX_LIVE_APPLE_EXPECT` to check another
/// language, e.g. a Spanish clip:
///
///     VERBVOX_LIVE_APPLE_STT=1 \
///     VERBVOX_LIVE_APPLE_WAV=/tmp/es-sample.wav \
///     VERBVOX_LIVE_APPLE_LOCALE=es_MX \
///     VERBVOX_LIVE_APPLE_EXPECT=servidor \
///     swift test --filter AppleSpeechLiveTests
final class AppleSpeechLiveTests: XCTestCase {

    /// `app/.cache/whisper.cpp/<pinned commit>/samples/jfk.wav`.
    private static let jfkSample = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent(".cache/whisper.cpp/d1be6fde11ac6e0407606b4e42fe72d34add8037/samples/jfk.wav")
        .path

    func testTranscribesASpokenSample() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["VERBVOX_LIVE_APPLE_STT"] == "1",
                          "live test; set VERBVOX_LIVE_APPLE_STT=1 to run")
        guard #available(macOS 26.0, *) else {
            throw XCTSkip("needs macOS 26")
        }

        let env = ProcessInfo.processInfo.environment
        let path = env["VERBVOX_LIVE_APPLE_WAV"] ?? Self.jfkSample
        let locale = env["VERBVOX_LIVE_APPLE_LOCALE"] ?? "en_US"
        let expected = env["VERBVOX_LIVE_APPLE_EXPECT"] ?? "country"
        let wav = try Data(contentsOf: URL(fileURLWithPath: path))

        let started = Date()
        let result = try await AppleSpeechSTT(locale: locale).transcribe(wav: wav, language: nil)
        let elapsed = Date().timeIntervalSince(started)
        print(String(format: "APPLE TRANSCRIPT [%@] (%.2fs): %@", locale, elapsed, result.text))

        XCTAssertTrue(result.text.lowercased().contains(expected.lowercased()),
                      "expected \"\(expected)\" in the transcript, got: \(result.text)")
    }

    /// The whole point of the retry: a provider with no language pinned hears
    /// Spanish and comes back with Spanish, not with the English model's phonetic
    /// guess. "transcripción" separates them — the English model writes
    /// "transcription". Needs a Spanish clip on disk:
    ///
    ///     say -v "Angélica" --data-format=LEI16@16000 -o /tmp/es2.wav \
    ///       "Necesito revisar el servidor de transcripción porque no está funcionando bien."
    func testDetectsSpanishWithNoLanguagePinned() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["VERBVOX_LIVE_APPLE_STT"] == "1",
                          "live test; set VERBVOX_LIVE_APPLE_STT=1 to run")
        guard #available(macOS 26.0, *) else {
            throw XCTSkip("needs macOS 26")
        }

        let path = ProcessInfo.processInfo.environment["VERBVOX_LIVE_APPLE_ES_WAV"] ?? "/tmp/es2.wav"
        let wav = try Data(contentsOf: URL(fileURLWithPath: path))

        let started = Date()
        let result = try await AppleSpeechSTT(locale: "").transcribe(wav: wav, language: nil)
        let elapsed = Date().timeIntervalSince(started)
        print(String(format: "APPLE AUTO [%@] (%.2fs): %@",
                     result.detectedLanguage ?? "?", elapsed, result.text))

        XCTAssertTrue(result.text.lowercased().contains("transcripción"),
                      "auto-detect should have switched to Spanish, got: \(result.text)")
        XCTAssertEqual(AppleSpeechSTT.languageCodes(of: [result.detectedLanguage ?? ""]), ["es"])
    }

    /// The other half of the guard: English with no language pinned must not get
    /// dragged over to Spanish, and must not pay for a second pass.
    func testStaysInEnglishWithNoLanguagePinned() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["VERBVOX_LIVE_APPLE_STT"] == "1",
                          "live test; set VERBVOX_LIVE_APPLE_STT=1 to run")
        guard #available(macOS 26.0, *) else {
            throw XCTSkip("needs macOS 26")
        }

        let path = ProcessInfo.processInfo.environment["VERBVOX_LIVE_APPLE_WAV"] ?? Self.jfkSample
        let wav = try Data(contentsOf: URL(fileURLWithPath: path))

        let result = try await AppleSpeechSTT(locale: "").transcribe(wav: wav, language: nil)
        print("APPLE AUTO [\(result.detectedLanguage ?? "?")]: \(result.text)")

        XCTAssertTrue(result.text.lowercased().contains("country"),
                      "expected the English transcript, got: \(result.text)")
        XCTAssertEqual(AppleSpeechSTT.languageCodes(of: [result.detectedLanguage ?? ""]), ["en"])
    }
}
