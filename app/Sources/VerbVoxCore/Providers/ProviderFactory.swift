import Foundation

/// Builds the live STT / AI / TTS provider selected in config. Reads the provider
/// choice, per-provider model/voice, and API keys from the `config` table (via a
/// snapshot dict) and hands each concrete provider exactly what it needs — the
/// providers never touch the DB themselves. A cloud provider chosen without its
/// key throws `ProviderError.missingKey`.
public struct ProviderFactory {
    let config: [String: String]
    let session: URLSession

    public init(config: [String: String], session: URLSession = .shared) {
        self.config = config
        self.session = session
    }

    /// Convenience: snapshot the whole `config` table from the database.
    public init(database: Database, session: URLSession = .shared) throws {
        self.init(config: try database.allConfig(), session: session)
    }

    // MARK: STT

    public func stt() throws -> STTProvider {
        switch value(ConfigCatalog.sttProviderKey) ?? "whisper_server" {
        case "apple":
            // On-device: no key, no network, no server to be running.
            return AppleSpeechSTT(locale: value(ConfigCatalog.sttAppleLocaleKey) ?? "")
        case "groq":
            return GroqSTT(apiKey: try key(ConfigCatalog.groqKeyKey, "groq"),
                           model: value(ConfigCatalog.sttGroqModelKey) ?? "whisper-large-v3-turbo",
                           session: session)
        case "openai":
            return OpenAISTT(apiKey: try key(ConfigCatalog.openAIKeyKey, "openai"),
                             model: value(ConfigCatalog.sttOpenAIModelKey) ?? "whisper-1",
                             session: session)
        case "deepgram":
            return DeepgramSTT(apiKey: try key(ConfigCatalog.deepgramKeyKey, "deepgram"),
                               model: value(ConfigCatalog.sttDeepgramModelKey) ?? "nova-3",
                               session: session)
        default: // whisper_server (default)
            let url = value(ConfigCatalog.serverURLKey) ?? "http://127.0.0.1:8080"
            return WhisperServerSTT(url: url, session: session)
        }
    }

    // MARK: AI cleanup

    public func ai() throws -> AIProvider {
        switch value(ConfigCatalog.providerKey) ?? "groq" {
        case "gemini":
            return GeminiAI(apiKey: try key(ConfigCatalog.geminiKeyKey, "gemini"),
                            model: value(ConfigCatalog.geminiModelKey) ?? "gemini-2.5-flash",
                            session: session)
        case "openai":
            return OpenAIAI(apiKey: try key(ConfigCatalog.openAIKeyKey, "openai"),
                            model: value(ConfigCatalog.openAIModelKey) ?? "gpt-4o-mini",
                            session: session)
        default: // groq (default)
            return GroqAI(apiKey: try key(ConfigCatalog.groqKeyKey, "groq"),
                          model: value(ConfigCatalog.groqModelKey) ?? "llama-3.3-70b-versatile",
                          session: session)
        }
    }

    // MARK: TTS

    public func tts() throws -> TTSProvider {
        switch value(ConfigCatalog.ttsProviderKey) ?? "system" {
        case "openai":
            return OpenAITTS(apiKey: try key(ConfigCatalog.openAIKeyKey, "openai"),
                             model: "tts-1",
                             voice: value(ConfigCatalog.ttsOpenAIVoiceKey) ?? "alloy",
                             session: session)
        case "deepgram":
            return DeepgramTTS(apiKey: try key(ConfigCatalog.deepgramKeyKey, "deepgram"),
                               model: value(ConfigCatalog.ttsDeepgramModelKey) ?? "aura-2-thalia-en",
                               session: session)
        default: // system (default)
            return SystemTTS()
        }
    }

    // MARK: Helpers

    /// Non-empty config value for `key`, or `nil`.
    private func value(_ key: String) -> String? {
        guard let value = config[key], !value.isEmpty else { return nil }
        return value
    }

    /// Required API key, throwing `.missingKey(name)` when absent/empty.
    private func key(_ configKey: String, _ name: String) throws -> String {
        guard let value = value(configKey) else { throw ProviderError.missingKey(name) }
        return value
    }
}
