import Foundation
import Combine
import ApplicationServices

/// The native dictation engine — the Swift replacement for `transcribe_cli.py`.
///
/// This owns the full hold-to-talk loop: a global `HotkeyMonitor` arms the
/// microphone (`AudioCapture`), release runs the transcription pipeline
/// (`ProviderFactory` STT → `TranscriptCleaner` → `DictionaryCorrector` →
/// `StatsLogger` → `Paster`), and ESC stops any in-progress speech. It publishes
/// the live `state`/`mode`/`lastTranscription`/`wpm` the menu bar + overlay HUD
/// bind to (replacing the old `/tmp/transcribe_status.json` poller).
///
/// It also owns a lightweight health check for the whisper server. While armed, a
/// modest timer pings the built-in engine (`builtinSpeech`, run by `BuiltinWhisper`)
/// or else the user's `whisper_server.url`, and publishes `serverRunning`; the check
/// is only meaningful when the STT provider is the whisper server, so
/// `sttIsWhisperServer` tells the UI when reachability is N/A (a cloud STT
/// provider has no local server to be "down").
@MainActor
public final class DictationEngine: ObservableObject {
    public enum State {
        case idle, recording, processing
    }

    /// Live pipeline state — bound directly by the menu bar and overlay HUD.
    @Published public private(set) var state: State = .idle
    /// Which hotkey started the active session, in the `"no_ai"` / `"with_ai"`
    /// wire form the overlay + status use.
    @Published public private(set) var mode: String = ""
    /// UNIX timestamp of the current recording's start (drives the HUD timer).
    @Published public private(set) var recordingStartedAt: Double = 0
    @Published public private(set) var lastTranscription: String = ""
    @Published public private(set) var wpm: Double = 0
    @Published public var lastError: String?

    /// Whether the hotkey listener + audio pipeline are armed.
    @Published public private(set) var engineRunning: Bool = false
    /// Whether the external whisper server answers a ping. Real health check: a
    /// reachable HTTP response (even an error status) is "up"; connection-refused /
    /// timeout is "down". Only meaningful when `sttIsWhisperServer` is true.
    @Published public private(set) var serverRunning: Bool = false
    /// True when the selected STT provider is the whisper server (so whisper
    /// reachability applies). False for a cloud STT provider (Groq/OpenAI/Deepgram),
    /// where there is no local server and `serverRunning` is N/A.
    @Published public private(set) var sttIsWhisperServer: Bool = true
    /// True while a start/stop transition is in flight.
    @Published public private(set) var busy: Bool = false
    /// Set by `AppState` while the built-in engine is the speech source, including
    /// while it covers for an unreachable whisper server.
    public var builtinSpeech: SpeechEndpoint?

    /// Where the native engine writes its log; the external whisper server (if
    /// run locally) writes its own. Both are read by the Logs tab.
    public let engineLogPath = "/tmp/verbvox-engine.log"
    public let serverLogPath = "/tmp/whisper-server.log"

    // MARK: Collaborators (live only while armed)

    private var db: Database?
    private var paths: BackendPaths?
    private var monitor: HotkeyMonitor?
    private let audio = AudioCapture()
    /// Repeating whisper-server reachability poll, live only while armed.
    private var healthTask: Task<Void, Never>?

    /// The mode that started the current hold-to-talk session (remembered from
    /// `onStart`, since `onStop` carries no mode).
    private var currentMode: RecordingMode = .noAI
    /// The live TTS instance currently able to be speaking, so ESC can stop it
    /// (mirrors Python's `stop_speech` terminating the `say` process).
    private var currentTTS: TTSProvider?

    public init() {}

    // MARK: Lifecycle

    /// Arm the hotkey listener + audio pipeline. Called by `AppState` on launch /
    /// autostart, and after any restart. Idempotent — re-arming tears down first.
    /// Does not block.
    public func start(db: Database, paths: BackendPaths) async {
        stop()

        self.db = db
        self.paths = paths
        busy = true
        lastError = nil

        let noAI = configString(ConfigCatalog.hotkeyNoAIKey) ?? "ctrl+alt"
        let withAI = configString(ConfigCatalog.hotkeyWithAIKey) ?? "ctrl+cmd"

        let monitor = HotkeyMonitor(noAIHotkey: noAI, withAIHotkey: withAI)
        monitor.onStart = { [weak self] mode in
            MainActor.assumeIsolated { self?.handleStart(mode) }
        }
        monitor.onStop = { [weak self] in
            MainActor.assumeIsolated { self?.handleStop() }
        }
        monitor.onEscape = { [weak self] in
            MainActor.assumeIsolated { self?.handleEscape() }
        }
        monitor.start()
        self.monitor = monitor

        engineRunning = true
        busy = false

        startHealthMonitor()
    }

    /// Disarm and release the microphone / hotkey tap.
    public func stop() {
        monitor?.stop()
        monitor = nil
        healthTask?.cancel()
        healthTask = nil
        _ = audio.stop() // safe: returns nil / no-op when not recording
        currentTTS?.stop()
        currentTTS = nil
        engineRunning = false
        serverRunning = false
        busy = false
        state = .idle
        mode = ""
        recordingStartedAt = 0
    }

    /// Re-check live status on demand (e.g. the Logs tab appearing, or a settings
    /// change). Fires a single whisper-server reachability probe.
    public func refresh() {
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        Task { await checkServer() }
    }

    // MARK: - Whisper server health (built-in engine or the user's own server)

    /// Classify a `URLSession` transport error as reachable/unreachable, mirroring
    /// v1's `EngineController.checkServer`: a connection-refused / timeout / dropped
    /// connection means nothing is listening; any other resolved response (incl. an
    /// HTTP error status, which does not throw) means the server answered.
    static func serverReachable(afterError error: Error) -> Bool {
        let ns = error as NSError
        return ns.domain == NSURLErrorDomain
            && ns.code != NSURLErrorCannotConnectToHost
            && ns.code != NSURLErrorTimedOut
            && ns.code != NSURLErrorNetworkConnectionLost
    }

    /// Ping the EFFECTIVE whisper URL the `ProviderFactory` targets
    /// (`whisper_server.url`, default `http://127.0.0.1:8080`). Publishes
    /// `serverRunning`. When a cloud STT provider is selected there is no local
    /// server, so this reports `false` and flags it N/A via `sttIsWhisperServer`.
    @discardableResult
    public func checkServer() async -> Bool {
        let isWhisper = (configString(ConfigCatalog.sttProviderKey) ?? "whisper_server") == "whisper_server"
        sttIsWhisperServer = isWhisper
        guard isWhisper else {
            serverRunning = false
            return false
        }
        let urlString = builtinSpeech.map { $0.url ?? "" }
            ?? configString(ConfigCatalog.serverURLKey) ?? "http://127.0.0.1:8080"
        serverRunning = await Self.ping(urlString)
        return serverRunning
    }

    /// Whether a whisper server answers at `urlString` within 1.5 s.
    static func ping(_ urlString: String) async -> Bool {
        guard let url = URL(string: urlString), url.host != nil else { return false }
        var request = URLRequest(url: url)
        request.timeoutInterval = 1.5
        do {
            _ = try await URLSession.shared.data(for: request)
            return true
        } catch {
            return serverReachable(afterError: error)
        }
    }

    /// Poll reachability on a modest timer while armed (skipped under the test
    /// runner so unit tests never make live network calls).
    private func startHealthMonitor() {
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        healthTask?.cancel()
        healthTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.checkServer()
                try? await Task.sleep(nanoseconds: 5_000_000_000) // every 5s
            }
        }
    }

    // MARK: - Hotkey callbacks (all delivered on the main thread)

    func handleStart(_ mode: RecordingMode) {
        if let builtin = builtinSpeech, builtin.url == nil {
            lastError = builtin.notReadyMessage
            appendLog("START REFUSED — \(builtin.notReadyMessage)")
            return
        }
        Sounds.play("Tink", enabled: hotkeySoundsEnabled)
        currentMode = mode
        self.mode = wireMode(mode)
        recordingStartedAt = Date().timeIntervalSince1970
        lastError = nil
        do {
            try audio.start()
            state = .recording
            appendLog("START mode=\(wireMode(mode)) — mic armed")
        } catch {
            lastError = "Microphone unavailable: \(error.localizedDescription)"
            state = .idle
            appendLog("START FAILED — mic error: \(error.localizedDescription)")
        }
    }

    private func handleStop() {
        guard state == .recording else { return }
        Sounds.play("Pop", enabled: hotkeySoundsEnabled)
        state = .processing

        let mode = currentMode
        let startedAt = recordingStartedAt

        guard let wav = audio.stop() else {
            // Released too quickly / no frames — mirror Python's empty-buffer guard.
            appendLog("STOP — NO AUDIO captured (audio.stop() returned nil); back to idle")
            state = .idle
            return
        }
        appendLog("STOP — captured wav=\(wav.count) bytes; starting pipeline")

        Task { await self.process(wav: wav, mode: mode, startedAt: startedAt) }
    }

    private func handleEscape() {
        // Mirror Python `stop_speech`: cut off any in-progress TTS.
        currentTTS?.stop()
    }

    // MARK: - Transcription pipeline

    private func process(wav: Data, mode: RecordingMode, startedAt: Double) async {
        guard let db, let paths else {
            state = .idle
            return
        }

        do {
            // Snapshot everything the (off-main) Paster needs while on the main
            // actor, so no `Database` access ever happens off the main thread.
            let config = try Self.speechConfig(db.allConfig(), builtin: builtinSpeech)
            let dictionaryMap = (try? db.dictionaryMap()) ?? [:]
            let profanityMap = (try? db.profanityMap()) ?? [:]
            let prompts = (try? db.prompts()) ?? []
            let promptMap = Dictionary(prompts.map { ($0.name, $0.text) }, uniquingKeysWith: { a, _ in a })

            let factory = ProviderFactory(config: config)

            let sttProvider = config[ConfigCatalog.sttProviderKey] ?? "whisper_server"
            let whisperURL = config[ConfigCatalog.serverURLKey] ?? "http://127.0.0.1:8080"
            appendLog("PROCESS stt=\(sttProvider) url=\(whisperURL)")

            // 1. Speech-to-text. `language: nil` reproduces Python's `"auto"` for the
            //    whisper server (which maps nil→"auto") and auto-detect for the cloud
            //    providers (which omit the field when nil).
            let result = try await factory.stt().transcribe(wav: wav, language: nil)
            appendLog("STT ok — text.len=\(result.text.count) lang=\(result.detectedLanguage ?? "nil") text=\"\(result.text.prefix(120))\"")

            // 2. Filler cleanup + dictionary correction (gated by the same feature
            //    flags Python honors in `convert_speech_to_text`).
            var text = result.text
            if boolFlag(config, "features.use_cleanup", default: true) {
                text = TranscriptCleaner.clean(text)
            }
            if boolFlag(config, "features.use_custom_dictionary", default: true) {
                text = DictionaryCorrector.apply(text, map: dictionaryMap)
            }
            appendLog("PIPELINE final.len=\(text.count) text=\"\(text.prefix(120))\"")

            // 3. WPM stats — recorded only when the flag is on (Python parity).
            if boolFlag(config, "features.show_wpm_stats", default: true) {
                let words = text.split(whereSeparator: { $0.isWhitespace }).count
                let seconds = max(0, Date().timeIntervalSince1970 - startedAt)
                // A stats-write failure must not block the paste (Python's
                // `save_stats` swallows its own errors).
                if let computed = try? StatsLogger(db: db)
                    .record(words: words, seconds: seconds, mode: wireMode(mode)) {
                    wpm = computed
                }
            }

            // 4. Output stage (AI cleanup / profanity / paste / TTS / logging).
            let tts = try factory.tts()
            currentTTS = tts

            // AI is OPTIONAL: `try?` yields nil when no groq/openai/gemini key is
            // configured (the factory throws `.missingKey`). A missing AI key must
            // never block plain no-AI dictation, so we pass nil through and let the
            // Paster degrade gracefully. STT/TTS keep throwing — they're required
            // for their selected provider.
            let ai = try? factory.ai()
            appendLog("PASTE begin mode=\(wireMode(mode)) app=\(ActiveApp.name() ?? "nil") aiConfigured=\(ai != nil) axTrusted=\(AXIsProcessTrusted())")
            let paster = Paster(
                ai: ai,
                tts: tts,
                promptBuilder: PromptBuilder { promptMap[$0] },
                profanityMap: profanityMap,
                flags: makeFlags(config),
                logger: TranscriptionLogger(logsDir: paths.logsDir, options: makeLogOptions(config)),
                onLastTranscription: { [weak self] value in
                    Task { @MainActor in self?.lastTranscription = value }
                },
                onError: { [weak self] message in
                    Task { @MainActor in
                        self?.lastError = message
                        self?.appendLog("PASTER ERROR: \(message)")
                    }
                })
            await paster.paste(text: text, mode: mode)
            appendLog("PASTE returned — done")

            state = .idle
        } catch {
            appendLog("ERROR: \(error)")
            lastError = "\(error)"
            state = .idle
        }
    }

    // MARK: - Config helpers

    /// The config snapshot the providers read, pointed at the built-in engine when
    /// it is the speech source.
    static func speechConfig(_ config: [String: String], builtin: SpeechEndpoint?) throws -> [String: String] {
        guard let builtin else { return config }
        guard let url = builtin.url else {
            throw SpeechEngineError(builtin.notReadyMessage, kind: .engine)
        }
        var config = config
        config[ConfigCatalog.serverURLKey] = url
        return config
    }

    /// The `"no_ai"` / `"with_ai"` wire string for a mode (matches the DB stats
    /// `mode` column and the overlay's `status.mode` check).
    private func wireMode(_ mode: RecordingMode) -> String {
        mode == .withAI ? "with_ai" : "no_ai"
    }

    private var hotkeySoundsEnabled: Bool {
        boolConfig("features.enable_hotkey_sounds", default: true)
    }

    /// Single non-empty config value read live from the DB, or nil.
    private func configString(_ key: String) -> String? {
        guard let db, let raw = ((try? db.configValue(key)) ?? nil), !raw.isEmpty else { return nil }
        return raw
    }

    /// Single boolean config value read live from the DB, with a default.
    private func boolConfig(_ key: String, default def: Bool) -> Bool {
        guard let raw = configString(key) else { return def }
        return raw.lowercased() == "true"
    }

    private func boolFlag(_ c: [String: String], _ key: String, default def: Bool) -> Bool {
        guard let raw = c[key], !raw.isEmpty else { return def }
        return raw.lowercased() == "true"
    }

    private func intFlag(_ c: [String: String], _ key: String, default def: Int) -> Int {
        guard let raw = c[key], let v = Int(raw) else { return def }
        return v
    }

    private func makeFlags(_ c: [String: String]) -> Paster.Flags {
        Paster.Flags(
            enableClipboardStashing: boolFlag(c, "features.enable_clipboard_stashing", default: true),
            enableTTS: boolFlag(c, "features.enable_tts", default: true),
            ttsSpeed: intFlag(c, ConfigCatalog.ttsSpeedKey, default: 220),
            enableProfanityFilter: boolFlag(c, ConfigCatalog.profanityEnabledKey, default: true),
            enableContextDetection: boolFlag(c, "features.enable_context_detection", default: true),
            enableTranslation: boolFlag(c, "features.enable_translation", default: true),
            useAICleanup: boolFlag(c, "features.use_ai_cleanup", default: true),
            minWordsForAI: intFlag(c, ConfigCatalog.minWordsForAIKey, default: 8))
    }

    private func makeLogOptions(_ c: [String: String]) -> TranscriptionLogger.Options {
        let format = c[ConfigCatalog.logFormatKey].flatMap { $0.isEmpty ? nil : $0 } ?? "simple"
        return TranscriptionLogger.Options(
            enabled: boolFlag(c, "logging.enable_logging", default: true),
            logOriginalText: boolFlag(c, "logging.log_original_text", default: true),
            format: format)
    }

    // MARK: - Diagnostics

    /// Append one line to `engineLogPath` (the file the Logs tab reads). Best-effort
    /// per-stage tracing so a failed dictation shows WHERE it died — hotkey, mic,
    /// STT, pipeline, or paste. Never throws.
    private func appendLog(_ message: String) {
        let stamp = ISO8601DateFormatter().string(from: Date())
        let line = "\(stamp) \(message)\n"
        let fm = FileManager.default
        if !fm.fileExists(atPath: engineLogPath) {
            fm.createFile(atPath: engineLogPath, contents: nil)
        }
        guard let handle = FileHandle(forWritingAtPath: engineLogPath) else { return }
        handle.seekToEndOfFile()
        handle.write(Data(line.utf8))
        try? handle.close()
    }
}
