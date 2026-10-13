import Foundation

/// Port of `paste_via_clipboard` (transcribe_cli.py) — the output stage that turns
/// a cleaned transcription into keystrokes, clipboard pastes, or spoken audio.
///
/// It composes the Output + Pipeline pieces and reaches its collaborators only
/// through injected dependencies, so Phase 6's `DictationEngine` can wire it
/// without this file knowing about `AppState`, the DB, or the concrete providers:
///
///  - `ai`     — the selected `AIProvider` (Groq/OpenAI/Gemini), or `nil` when no
///    AI key is configured. No-AI dictation never touches it; the AI-requiring
///    flows degrade gracefully (fall back to the raw/selected text, matching
///    Python's fallback-on-AI-failure) instead of requiring a key.
///  - `tts`    — the selected `TTSProvider` (System/OpenAI/Deepgram).
///  - `promptBuilder` — a `PromptBuilder` whose template lookup is DB-backed.
///  - `profanityMap`  — `word → replacement` from the DB (empty ⇒ no-op filter).
///  - `flags`  — resolved feature flags/values (see `Flags`).
///  - `logger` — the `TranscriptionLogger` (history log files).
///  - `activeApp` — frontmost-app resolver (defaults to `ActiveApp.name`).
///  - `onLastTranscription` — callback to publish the final text (updates
///    `DictationEngine.lastTranscription`, matching Python's `write_status`).
///
/// Text passed in is already filler-cleaned + dictionary-corrected (Python does
/// those in `convert_speech_to_text`, before `paste_via_clipboard`).
public struct Paster {

    /// Resolved feature flags + tunables the paste flow reads (from `config`).
    public struct Flags {
        public let enableClipboardStashing: Bool // features.enable_clipboard_stashing
        public let enableTTS: Bool               // features.enable_tts
        public let ttsSpeed: Int                 // ai_response.tts_speed
        public let enableProfanityFilter: Bool   // features.enable_profanity_filter
        public let enableContextDetection: Bool  // features.enable_context_detection
        public let enableTranslation: Bool       // features.enable_translation
        public let useAICleanup: Bool            // features.use_ai_cleanup
        public let minWordsForAI: Int            // features.min_words_for_ai

        public init(enableClipboardStashing: Bool,
                    enableTTS: Bool,
                    ttsSpeed: Int,
                    enableProfanityFilter: Bool,
                    enableContextDetection: Bool,
                    enableTranslation: Bool,
                    useAICleanup: Bool,
                    minWordsForAI: Int) {
            self.enableClipboardStashing = enableClipboardStashing
            self.enableTTS = enableTTS
            self.ttsSpeed = ttsSpeed
            self.enableProfanityFilter = enableProfanityFilter
            self.enableContextDetection = enableContextDetection
            self.enableTranslation = enableTranslation
            self.useAICleanup = useAICleanup
            self.minWordsForAI = minWordsForAI
        }
    }

    // Shared AI request parameters, matching `call_groq()` in transcribe_cli.py
    // (system message + temperature; max_tokens = the Groq default the app ships).
    private static let aiSystemPrompt = "You are a helpful AI assistant. Follow instructions exactly."
    private static let aiTemperature = 0.3
    private static let aiMaxTokens = 2000

    // Python `get_spanish_system_voice`: the first `es-*` system voice. Passed to
    // `SystemTTS.speak(voice:)`, which resolves it via `AVSpeechSynthesisVoice`.
    // "es-ES" is SystemTTS's own canonical Spanish fallback code (not invented).
    // Only SystemTTS honors this; cloud TTS providers ignore/​don't map it.
    private static let spanishVoiceHint = "es-ES"

    // Same list Python uses in the non-AI branch to still tag code editors for
    // logging (mirrors `ContextDetector.codeEditors`).
    private static let codeEditors = [
        "Visual Studio Code", "Cursor", "Zed", "Sublime Text", "Code", "Xcode", "Terminal",
    ]

    // Surfaced via `onError` when a With-AI flow is reached without a configured
    // AI provider, so the user learns why the AI step was skipped.
    static let noAINote = "No AI provider configured — add an API key in Settings to use AI features."

    private let ai: AIProvider?
    private let tts: TTSProvider
    private let promptBuilder: PromptBuilder
    private let profanityMap: [String: String]
    private let flags: Flags
    private let logger: TranscriptionLogger
    private let activeApp: () -> String?
    private let onLastTranscription: (String) -> Void
    private let onError: ((String) -> Void)?

    public init(ai: AIProvider?,
                tts: TTSProvider,
                promptBuilder: PromptBuilder,
                profanityMap: [String: String],
                flags: Flags,
                logger: TranscriptionLogger,
                activeApp: @escaping () -> String? = { ActiveApp.name() },
                onLastTranscription: @escaping (String) -> Void,
                onError: ((String) -> Void)? = nil) {
        self.ai = ai
        self.tts = tts
        self.promptBuilder = promptBuilder
        self.profanityMap = profanityMap
        self.flags = flags
        self.logger = logger
        self.activeApp = activeApp
        self.onLastTranscription = onLastTranscription
        self.onError = onError
    }

    /// Entry point, mirroring `paste_via_clipboard(text, use_ai=…)`.
    public func paste(text: String, mode: RecordingMode) async {
        let useAI = (mode == .withAI)
        let app = activeApp()

        // "read this / read that" command (no-AI mode only). If a highlighted
        // selection is spoken, we're done; otherwise fall through to normal flow.
        if !useAI, Self.isReadCommand(text) {
            if await handleReadCommand() { return }
        }

        // Context detection — only when AI is on. In no-AI mode we still tag code
        // editors so logging records the right context (Python parity).
        var context: DictationContext = .default
        if useAI {
            context = ContextDetector.detect(text, app: app,
                                             translationEnabled: flags.enableTranslation,
                                             contextEnabled: flags.enableContextDetection)
        } else if let app, Self.codeEditors.contains(where: { app.contains($0) }) {
            context = .codePrompt
        }

        // AI question over a highlighted selection ("hey <ai>, …").
        if useAI, case let .aiQuestion(trigger) = context {
            if await handleAIQuestion(text: text, trigger: trigger, app: app) { return }
        }

        // Translate a highlighted selection ("translate this to spanish").
        if useAI, case let .translate(language) = context {
            await handleTranslate(text: text, language: language, app: app)
            return
        }

        // Normal path: optional AI cleanup → profanity filter → type/paste → log.
        await handleNormal(text: text, useAI: useAI, app: app, context: context)
    }

    // MARK: - Read command (no-AI)

    /// Python: strip `.,!?;:`, lowercase, and require exactly `read this` / `read that`.
    static func isReadCommand(_ text: String) -> Bool {
        let stripped = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = stripped
            .components(separatedBy: CharacterSet(charactersIn: ".,!?;:")).joined()
            .lowercased()
        let words = normalized.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        return words.count == 2 && words[0] == "read" && (words[1] == "this" || words[1] == "that")
    }

    /// Copy the selection, and if it differs from the stashed clipboard, speak it.
    /// Returns true when handled (spoken), false to continue with the normal flow.
    private func handleReadCommand() async -> Bool {
        let stash = flags.enableClipboardStashing
        let snapshot = stash ? Clipboard.snapshot() : []
        let stashed = stash ? (Clipboard.readString() ?? "") : ""

        Clipboard.copySelection()
        await Self.sleep(0.2)
        let selected = Clipboard.readString() ?? ""

        if hasSelection(selected, stashed: stashed) {
            if flags.enableTTS {
                try? await tts.speak(selected, wpm: flags.ttsSpeed, voice: nil)
            }
            if stash { Clipboard.restore(snapshot) }
            return true
        }
        if stash { Clipboard.restore(snapshot) }
        return false
    }

    // MARK: - AI question over a selection

    /// Returns true when handled (answered), false to continue with the normal flow.
    private func handleAIQuestion(text: String, trigger: String, app: String?) async -> Bool {
        let stash = flags.enableClipboardStashing
        let snapshot = stash ? Clipboard.snapshot() : []
        let stashed = stash ? (Clipboard.readString() ?? "") : ""

        Clipboard.copySelection()
        await Self.sleep(0.2)
        let selected = Clipboard.readString() ?? ""

        guard hasSelection(selected, stashed: stashed) else {
            if stash { Clipboard.restore(snapshot) }
            return false
        }

        // Strip the wake-word trigger from the spoken question.
        var question = text
            .replacingOccurrences(of: trigger, with: "", options: [.caseInsensitive])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        question = Self.stripLeadingCommasAndSpaces(question)

        let combinedPrompt = """
        The user selected this text:
        "\(selected)"

        And asked: "\(question)"

        Please answer their question about the selected text. Be concise and direct.
        """

        // On any provider error, Python's call_* returns the original text. With no
        // AI provider configured, degrade the same way (echo the selection back)
        // rather than blocking — the user still keeps their selection intact.
        let aiResponse: String
        if let ai {
            aiResponse = (try? await ai.complete(system: Self.aiSystemPrompt,
                                                 user: combinedPrompt,
                                                 temperature: Self.aiTemperature,
                                                 maxTokens: Self.aiMaxTokens)) ?? selected
        } else {
            onError?(Self.noAINote)
            aiResponse = selected
        }

        let action = ActionTypeDetector.detect(text)
        switch action {
        case .speak:
            if flags.enableTTS {
                try? await tts.speak(aiResponse, wpm: flags.ttsSpeed, voice: nil)
            }
            if stash { Clipboard.restore(snapshot) }
        case .replace:
            Clipboard.setString(aiResponse)
            await Self.sleep(0.1)
            Clipboard.paste(modifier: .command)
            await Self.sleep(0.1)
            if stash { Clipboard.restore(snapshot) }
        }

        let actionName = (action == .speak) ? "speak" : "replace"
        logger.log(original: "\(text) | Selected: \(selected)",
                   cleaned: aiResponse,
                   app: app,
                   context: "ai_question_\(actionName)")
        return true
    }

    // MARK: - Translate a selection

    private func handleTranslate(text: String, language: String, app: String?) async {
        let stash = flags.enableClipboardStashing
        let snapshot = stash ? Clipboard.snapshot() : []

        Clipboard.copySelection()
        await Self.sleep(0.2)
        let selected = Clipboard.readString() ?? ""

        let prompt = promptBuilder.build(text: selected, context: .translate(language: language))
        // No AI provider → nothing to translate with; fall back to the selection
        // (Python's fallback-to-original on an AI failure), noting why.
        let translation: String
        if let ai {
            translation = (try? await ai.complete(system: Self.aiSystemPrompt,
                                                  user: prompt,
                                                  temperature: Self.aiTemperature,
                                                  maxTokens: Self.aiMaxTokens)) ?? selected
        } else {
            onError?(Self.noAINote)
            translation = selected
        }

        logger.log(original: selected, cleaned: translation, app: app,
                   context: "translate_to_\(language)")

        if flags.enableTTS {
            await speakTranslation(translation, language: language)
        }
        if stash { Clipboard.restore(snapshot) }
    }

    /// Speak a translation, mirroring the Python Spanish-voice branch:
    /// - contains `[ES]…[/ES]` → per-segment voices (SystemTTS handles it, `voice:nil`);
    /// - Spanish target, no tags → whole text in a Spanish voice;
    /// - otherwise → the default/system voice.
    private func speakTranslation(_ translation: String, language: String) async {
        let isSpanish = language.lowercased() == "spanish"
        let voiceHint = (isSpanish && !translation.contains("[ES]")) ? Self.spanishVoiceHint : nil
        try? await tts.speak(translation, wpm: flags.ttsSpeed, voice: voiceHint)
    }

    // MARK: - Normal path

    private func handleNormal(text: String, useAI: Bool, app: String?, context: DictationContext) async {
        // AI cleanup (only With-AI, and only when the cleanup flag is on — Python's
        // ai_cleanup_text returns the input immediately if use_ai_cleanup is False).
        // With no AI provider configured, skip cleanup and paste the raw (already
        // filler-cleaned + dictionary-corrected) text — Python falls back to the
        // original text when the AI call fails, so keyless no-AI-key paste still works.
        var cleaned = text
        if useAI && flags.useAICleanup {
            if let ai {
                let cleanup = AICleanup(provider: ai,
                                        promptBuilder: promptBuilder,
                                        minWords: flags.minWordsForAI,
                                        contextEnabled: flags.enableContextDetection,
                                        translationEnabled: flags.enableTranslation)
                cleaned = (try? await cleanup.run(text: text, app: app)) ?? text
            } else {
                onError?(Self.noAINote)
            }
        }

        // Profanity filter globally when enabled. Python filters BOTH the original
        // (for logging) and the cleaned text (for output).
        var loggedOriginal = text
        if flags.enableProfanityFilter {
            loggedOriginal = ProfanityFilter.apply(text, map: profanityMap)
            cleaned = ProfanityFilter.apply(cleaned, map: profanityMap)
        }

        // Last pass before the text leaves the app: a blank dictionary/profanity
        // replacement deletes its word and leaves a gap, so squeeze double and
        // triple spaces back to one.
        cleaned = TranscriptCleaner.collapseInlineSpaces(cleaned)

        logger.log(original: loggedOriginal, cleaned: cleaned, app: app,
                   context: Self.contextName(context))

        // App family: Windows App types; Remote Desktop / VMware / Windows App paste with ⌃V.
        let appName = app ?? ""
        let isWindowsApp = appName.contains("Windows App")
        let useCtrl = appName.contains("Remote Desktop")
            || appName.contains("VMware")
            || appName.contains("Windows App")

        if isWindowsApp {
            Typer.typeForWindows(cleaned)
        } else {
            let stash = flags.enableClipboardStashing
            let snapshot = stash ? Clipboard.snapshot() : []

            Clipboard.setString(cleaned)
            await Self.sleep(0.15)
            // Verify + one retry, matching Python's clipboard verification.
            if Clipboard.readString() != cleaned {
                Clipboard.setString(cleaned)
                await Self.sleep(0.15)
            }

            Clipboard.paste(modifier: useCtrl ? .control : .command)
            await Self.sleep(0.15)

            if stash { Clipboard.restore(snapshot) }
        }

        // Only the normal path updates last_transcription (the command sub-flows
        // return before Python's `write_status(..., last_transcription=…)`).
        onLastTranscription(cleaned)
    }

    // MARK: - Helpers

    /// Python: `selected_text and selected_text.strip() and selected_text != stashed`.
    private func hasSelection(_ selected: String, stashed: String) -> Bool {
        !selected.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && selected != stashed
    }

    /// The Python context string used for logging.
    private static func contextName(_ context: DictationContext) -> String {
        switch context {
        case .default: return "default"
        case .codePrompt: return "code_prompt"
        case .formalChat: return "formal_chat"
        case .aiQuestion: return "ai_question"
        case .translate: return "translate"
        }
    }

    /// Python: `re.sub(r'^[,\s]+', '', text)`.
    private static func stripLeadingCommasAndSpaces(_ s: String) -> String {
        var r = Substring(s)
        while let f = r.first, f == "," || f.isWhitespace { r = r.dropFirst() }
        return String(r)
    }

    private static func sleep(_ seconds: Double) async {
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }
}
