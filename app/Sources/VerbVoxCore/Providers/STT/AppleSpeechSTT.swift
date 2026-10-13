import Foundation
import AVFoundation
import NaturalLanguage
#if canImport(Speech)
import Speech
#endif

/// On-device speech-to-text using Apple's `SpeechTranscriber` (macOS 26+), the
/// same engine behind system Dictation.
///
/// Unlike every other STT provider here there is no network call and no API key:
/// the model lives in the OS, and the first use of a language downloads its
/// assets through `AssetInventory`. The package still targets macOS 14, so the
/// framework work sits behind `@available(macOS 26, *)` and an older system gets
/// a plain error instead of a crash.
public struct AppleSpeechSTT: STTProvider {

    /// Locale identifier from config (`stt.apple_locale`). Empty means "work the
    /// language out from what was said".
    let configuredLocale: String

    /// How sure the language detector has to be before the audio is re-run under
    /// another language. Constraining the recognizer to the installed languages
    /// makes it decisive: over 15 real transcripts, English and Spanish, the
    /// weakest right answer scored 0.873 and the strongest wrong one 0.127.
    /// Nothing landed near the middle, so 0.5 sits in open space.
    static let autoDetectConfidence = 0.5

    public init(locale: String = "") {
        self.configuredLocale = locale
    }

    /// True when this Mac can run the on-device transcriber at all.
    public static var isSupported: Bool {
        if #available(macOS 26.0, *) {
            return SpeechTranscriber.isAvailable
        }
        return false
    }

    public func transcribe(wav: Data, language: String?) async throws -> STTResult {
        guard #available(macOS 26.0, *) else {
            throw ProviderError.decode("Apple on-device speech needs macOS 26 or newer")
        }
        let locale = Self.resolveLocale(requested: language,
                                        configured: configuredLocale,
                                        system: .current)
        let autoDetect = Self.shouldAutoDetect(requested: language, configured: configuredLocale)
        return try await Self.run(wav: wav, locale: locale, autoDetect: autoDetect)
    }

    // MARK: - Pure decisions (unit-tested)

    /// Which locale to ask the transcriber for. An explicit `language` from the
    /// caller wins; `"auto"` (what the pipeline sends when nothing is pinned) and
    /// blanks fall through to the configured locale, then the system one.
    static func resolveLocale(requested: String?, configured: String, system: Locale) -> Locale {
        if let requested = pinnedLanguage(requested) {
            return Locale(identifier: requested)
        }
        if let configured = pinnedLanguage(configured) {
            return Locale(identifier: configured)
        }
        return system
    }

    /// Whether the provider should work the language out for itself. Apple's
    /// transcriber listens in one language at a time, so a Spanish sentence read
    /// by the English model comes back as phonetic nonsense. Detection runs only
    /// when nobody pinned a language: an explicit pick has to stay honoured.
    static func shouldAutoDetect(requested: String?, configured: String) -> Bool {
        pinnedLanguage(requested) == nil && pinnedLanguage(configured) == nil
    }

    /// The distinct languages behind a list of locale identifiers, so "en_US",
    /// "en_GB" and "es_MX" become the two real choices the detector picks from.
    static func languageCodes(of locales: [String]) -> [String] {
        let codes = locales.map { languageCode(of: $0) }.filter { !$0.isEmpty }
        return Set(codes).sorted()
    }

    /// Which language a first-pass transcript reads as. Returns nil when the text
    /// is empty, when there is only one installed language to choose between, or
    /// when the guess is too weak to act on.
    static func detectLanguage(in text: String,
                               among codes: [String],
                               minimumConfidence: Double) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, codes.count > 1 else { return nil }

        let recognizer = NLLanguageRecognizer()
        recognizer.languageConstraints = codes.map { NLLanguage($0) }
        recognizer.processString(trimmed)

        let hypotheses = recognizer.languageHypotheses(withMaximum: codes.count)
        guard let best = hypotheses.max(by: { $0.value < $1.value }),
              best.value >= minimumConfidence else { return nil }
        return best.key.rawValue
    }

    /// Which locale should hear the audio again. Nil leaves the first pass alone,
    /// which is the common case. A model for the user's own region wins; failing
    /// that, any installed model for the detected language still beats the wrong
    /// language entirely.
    static func retryLocale(detected: String?,
                            used: String,
                            installed: [String],
                            preferredRegion: String?) -> String? {
        guard let detected = detected?.lowercased(), !detected.isEmpty else { return nil }
        guard languageCode(of: used) != detected else { return nil }

        let candidates = installed.filter { languageCode(of: $0) == detected }.sorted()
        guard !candidates.isEmpty else { return nil }

        if let region = preferredRegion?.uppercased(),
           let regional = candidates.first(where: { regionCode(of: $0) == region }) {
            return regional
        }
        return candidates.first
    }

    /// A setting that names a language, or nil when it names none. Blanks and
    /// `"auto"` both mean "nobody picked", so every caller reads the same string
    /// the same way.
    private static func pinnedLanguage(_ value: String?) -> String? {
        let trimmed = (value ?? "").trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty || trimmed.lowercased() == "auto" { return nil }
        return trimmed
    }

    /// "es_MX" and "es-ES" both carry the language in front of the separator.
    private static func languageCode(of identifier: String) -> String {
        String(identifier.prefix { $0 != "_" && $0 != "-" }).lowercased()
    }

    /// The region half of "es_MX", or nil for a bare "es".
    private static func regionCode(of identifier: String) -> String? {
        let parts = identifier.split(whereSeparator: { $0 == "_" || $0 == "-" })
        return parts.count > 1 ? parts[1].uppercased() : nil
    }

    /// Results arrive in chunks as the analyzer works through the audio. The rest
    /// of the pipeline wants one single-line string, same as `WhisperServerSTT`.
    static func joinChunks(_ chunks: [String]) -> String {
        chunks
            .map { $0.replacingOccurrences(of: "\n", with: " ") }
            .flatMap { $0.split(separator: " ") }
            .joined(separator: " ")
    }

    /// Readable name for a locale identifier, for the Settings picker. An
    /// identifier the system cannot name shows as itself rather than as blank.
    public static func localeDisplayName(_ identifier: String) -> String {
        let name = Locale(identifier: "en_US").localizedString(forIdentifier: identifier)
        guard let name, !name.isEmpty else { return identifier }
        return name
    }

    /// Languages this Mac's transcriber can handle, sorted by their readable name.
    public static func supportedLocaleIdentifiers() async -> [String] {
        guard #available(macOS 26.0, *) else { return [] }
        return await SpeechTranscriber.supportedLocales
            .map(\.identifier)
            .sorted { localeDisplayName($0) < localeDisplayName($1) }
    }

    // MARK: - Framework work

    @available(macOS 26.0, *)
    private static func run(wav: Data, locale: Locale, autoDetect: Bool) async throws -> STTResult {
        guard SpeechTranscriber.isAvailable else {
            throw ProviderError.decode("Apple on-device speech is unavailable on this Mac")
        }

        // AVAudioFile reads from disk, and the pipeline hands us bytes, so the WAV
        // lands in a temp file for the length of the call. A retry reads it again.
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("verbvox-apple-stt-\(UUID().uuidString).wav")
        try wav.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let first = try await transcribe(fileAt: url, locale: locale)
        guard autoDetect else { return first }

        // The first pass always produces *something*; when the wrong model heard
        // it, that something reads as the language actually spoken. A second pass
        // costs about a tenth of a second and only runs when the language moved.
        let installed = await SpeechTranscriber.installedLocales.map(\.identifier)
        let detected = detectLanguage(in: first.text,
                                      among: languageCodes(of: installed),
                                      minimumConfidence: autoDetectConfidence)
        guard let retry = retryLocale(detected: detected,
                                      used: first.detectedLanguage ?? locale.identifier,
                                      installed: installed,
                                      preferredRegion: Locale.current.region?.identifier) else {
            return first
        }
        return try await transcribe(fileAt: url, locale: Locale(identifier: retry))
    }

    @available(macOS 26.0, *)
    private static func transcribe(fileAt url: URL, locale: Locale) async throws -> STTResult {
        guard let supported = await SpeechTranscriber.supportedLocale(equivalentTo: locale) else {
            throw ProviderError.decode("Apple speech has no model for \(locale.identifier)")
        }

        let transcriber = SpeechTranscriber(locale: supported, preset: .transcription)
        try await installAssetsIfNeeded(for: transcriber, locale: supported)

        let file = try AVAudioFile(forReading: url)
        let analyzer = SpeechAnalyzer(modules: [transcriber])

        // Drain results concurrently: `analyzeSequence` only returns once the
        // audio is consumed, and the chunks arrive while it runs.
        let collector = Task { () -> [String] in
            var chunks: [String] = []
            for try await result in transcriber.results {
                chunks.append(String(result.text.characters))
            }
            return chunks
        }

        do {
            _ = try await analyzer.analyzeSequence(from: file)
            try await analyzer.finalizeAndFinishThroughEndOfInput()
        } catch {
            collector.cancel()
            throw ProviderError.decode("Apple speech failed: \(error.localizedDescription)")
        }

        let chunks = try await collector.value
        return STTResult(text: joinChunks(chunks), detectedLanguage: supported.identifier)
    }

    /// First use of a language pulls its assets down. `reserve` claims one of the
    /// system's limited on-device locale slots; a refusal is not fatal, since an
    /// already-installed locale still transcribes.
    @available(macOS 26.0, *)
    private static func installAssetsIfNeeded(for transcriber: SpeechTranscriber,
                                              locale: Locale) async throws {
        let installed = await SpeechTranscriber.installedLocales
        if !installed.contains(where: { $0.identifier == locale.identifier }) {
            _ = try? await AssetInventory.reserve(locale: locale)
        }
        guard let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) else {
            return // nothing missing
        }
        try await request.downloadAndInstall()
    }
}
