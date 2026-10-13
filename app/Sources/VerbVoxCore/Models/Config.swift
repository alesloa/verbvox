import Foundation

/// Declarative description of the engine's feature toggles, so the Recording tab
/// can render them without hard-coding each row. Keys/categories match the
/// `config` table written by `db_helpers` / `init_database.py`.
public struct FeatureToggle: Identifiable {
    public let key: String
    public let category: String
    public let title: String
    public let subtitle: String
    public var id: String { key }
}

public enum ConfigCatalog {
    public static let features: [FeatureToggle] = [
        .init(key: "features.use_cleanup", category: "features",
              title: "Filler-word cleanup", subtitle: "Strip “uh, um, er, ah, mm” from results."),
        .init(key: "features.use_custom_dictionary", category: "features",
              title: "Custom dictionary", subtitle: "Apply your word corrections."),
        .init(key: "features.use_ai_cleanup", category: "features",
              title: "AI cleanup", subtitle: "Context-aware rewrite via Groq/Gemini (With-AI mode)."),
        .init(key: "features.enable_context_detection", category: "features",
              title: "Context detection", subtitle: "Detect the active app (code, chat, email…)."),
        .init(key: "features.enable_translation", category: "features",
              title: "Translation", subtitle: "Handle “translate this” commands."),
        .init(key: "features.enable_tts", category: "features",
              title: "Text-to-speech", subtitle: "Speak translations / AI answers aloud."),
        .init(key: "features.enable_clipboard_stashing", category: "features",
              title: "Clipboard stashing", subtitle: "Preserve and restore your clipboard."),
        .init(key: "features.show_wpm_stats", category: "features",
              title: "Show WPM stats", subtitle: "Report words-per-minute after each result."),
        .init(key: "features.enable_hotkey_sounds", category: "features",
              title: "Hotkey sounds", subtitle: "Play a start/stop sound."),
    ]

    public static let logging: [FeatureToggle] = [
        .init(key: "logging.enable_logging", category: "logging",
              title: "Enable logging", subtitle: "Write transcriptions to per-app log files."),
        .init(key: "logging.log_original_text", category: "logging",
              title: "Log original text", subtitle: "Log raw text instead of the cleaned version."),
    ]

    // Single-value keys
    /// Effective/derived URL the Python engine (`transcribe_cli.py`) actually
    /// reads. AppState keeps it in sync with the selected mode below, so the CLI
    /// and the Swift controller always agree on where transcription goes.
    public static let serverURLKey = "whisper_server.url"
    /// "builtin" | "local" | "remote" — the engine inside VerbVox, or your own
    /// whisper server on this Mac or the LAN.
    public static let serverModeKey = "whisper_server.mode"
    /// Built-in engine model id from `WhisperModelCatalog`; blank = automatic.
    public static let builtinModelKey = "whisper_builtin.model"
    /// The model automatic mode settled on after timing this Mac.
    public static let builtinAutoModelKey = "whisper_builtin.auto_model"
    /// Address of the locally-launched whisper-server (default 127.0.0.1:8080).
    public static let localURLKey = "whisper_server.local_url"
    /// Address of the remote LAN whisper server used in remote mode.
    public static let remoteURLKey = "whisper_server.remote_url"
    public static let serverThreadsKey = "whisper_server.threads"
    /// Address of the external `whisperctl` supervisor panel that owns the
    /// whisper-server process (default 127.0.0.1:8722). Used only to ask it to
    /// start/stop its own child; the built-in engine (`BuiltinWhisper`) doesn't use it.
    public static let controlURLKey = "whisper_server.control_url"
    public static let modelKey = "whisper.model"
    public static let providerKey = "ai_settings.provider"
    public static let groqModelKey = "ai_settings.groq_model"
    public static let geminiModelKey = "ai_settings.gemini_model"
    public static let groqKeyKey = "api_keys.groq"
    public static let geminiKeyKey = "api_keys.gemini"
    public static let ttsSpeedKey = "ai_response.tts_speed"
    public static let ttsModeKey = "ai_response.mode"
    public static let minWordsForAIKey = "features.min_words_for_ai"
    public static let profanityEnabledKey = "features.enable_profanity_filter"
    public static let logFormatKey = "logging.log_format"
    public static let hotkeyNoAIKey = "hotkeys.no_ai"
    public static let hotkeyWithAIKey = "hotkeys.with_ai"
    // GUI-only (the Python engine never reads it): launch the engine on app open.
    public static let autostartKey = "engine.autostart"

    // MARK: Provider keys (native engine)

    // STT
    public static let sttProviderKey = "stt.provider"           // whisper_server|apple|groq|openai|deepgram
    public static let sttGroqModelKey = "stt.groq_model"        // default "whisper-large-v3-turbo"
    public static let sttOpenAIModelKey = "stt.openai_model"    // default "whisper-1"
    public static let sttDeepgramModelKey = "stt.deepgram_model" // default "nova-3"
    /// Locale for Apple's on-device transcriber, e.g. "en_US". Blank detects the
    /// spoken language from the first pass instead.
    public static let sttAppleLocaleKey = "stt.apple_locale"
    // AI (provider/groqModel/geminiModel already exist above)
    public static let openAIModelKey = "ai_settings.openai_model" // default "gpt-4o-mini"
    // TTS
    public static let ttsProviderKey = "tts.provider"          // system|openai|deepgram
    public static let ttsVoiceKey = "tts.voice"
    public static let ttsOpenAIVoiceKey = "tts.openai_voice"    // default "alloy"
    public static let ttsDeepgramModelKey = "tts.deepgram_model" // default "aura-2-thalia-en"
    // API keys (groq/gemini already exist above)
    public static let openAIKeyKey = "api_keys.openai"
    public static let deepgramKeyKey = "api_keys.deepgram"
}
