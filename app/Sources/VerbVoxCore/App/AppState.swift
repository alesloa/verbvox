import Foundation
import SwiftUI
import AppKit
import Combine

/// Central app state. Owns the database, engine controller, status poller, and
/// the overlay HUD; exposes typed config access and CRUD that republish to views.
@MainActor
public final class AppState: ObservableObject {
    @Published public var status: EngineStatus = .stopped
    @Published public var config: [String: String] = [:]
    @Published public var dictionary: [DictionaryEntry] = []
    @Published public var profanity: [ProfanityEntry] = []
    @Published public var prompts: [Prompt] = []
    @Published public var summary: StatsSummary = .empty
    @Published public var dailyCounts: [DayCount] = []
    @Published public var recentLogs: [LogEntry] = []
    @Published public var paths: BackendPaths
    @Published public var loadError: String?
    /// Which Settings panel is shown. Drives the sidebar so menu shortcuts can
    /// open the window already focused on History / Dictionary / etc.
    @Published public var settingsSelection: SettingsTab = .home

    public let engine: DictationEngine
    private let overlay = OverlayController()
    private let settingsWindow = SettingsWindowController()
    private var db: Database?
    private var cancellables = Set<AnyCancellable>()

    /// Last engine phase seen by `syncEngineStatus`, used to detect the
    /// `.processing → .idle` edge that means a dictation just finished (so the
    /// open History tab can reload live instead of only on tab switch).
    private var previousPhase: EngineStatus.Phase?

    /// The whisper.cpp engine that ships inside VerbVox.
    public let builtin: BuiltinWhisper
    /// The first open of a new database. It starts on the built-in engine, so
    /// Settings opens to show the model download instead of a silent menu bar icon.
    public private(set) var isFirstRun = false
    /// The built-in engine only runs after launch, so tests never start a download.
    private var builtinRunning = false
    private var externalWatch = ExternalServerWatch()
    /// The server address `externalWatch` is timing.
    private var externalTarget = ""
    private var lastBuiltinURL: String?

    public func showSettings() {
        // Skip real window creation under the test runner.
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        settingsWindow.show(app: self)
    }

    /// Open Settings focused on a specific panel (used by the menu-bar shortcuts).
    public func showSettings(_ tab: SettingsTab) {
        settingsSelection = tab
        showSettings()
    }

    public var dbAvailable: Bool { db != nil }

    public init() {
        let p = BackendPaths.load()
        paths = p
        let engine = DictationEngine()
        self.engine = engine
        builtin = BuiltinWhisper(
            enginePath: Bundle.main.url(forAuxiliaryExecutable: "whisper-server"),
            modelsDir: BackendPaths.modelsDir(),
            warmupClip: Bundle.main.url(forResource: "warmup", withExtension: "wav")
                .flatMap { try? Data(contentsOf: $0) },
            logPath: engine.serverLogPath,
            isDictating: { engine.state != .idle })

        openDatabase()
        loadConfig()
        loadCollections()
        adoptInitialServerMode()

        builtin.remember = { [weak self] key, value in
            self?.setStr(key, value, category: "whisper_builtin")
        }
        builtin.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        builtin.$status
            .sink { [weak self] status in self?.updateBuiltinSpeech(status) }
            .store(in: &cancellables)

        applyEngineConfig()
        engine.refresh()

        // The native engine publishes its own live state (`engine.state`); mirror
        // it into `status` (the view-facing `EngineStatus`) and drive the overlay
        // HUD off it, replacing the old `/tmp/transcribe_status.json` poller.
        engine.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.syncEngineStatus() }
            .store(in: &cancellables)
        syncEngineStatus()

        // Auto-start the engine on app open. Skipped under the
        // test runner so view/decision tests never spawn a real server process.
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil {
            autostartIfEnabled()
            startBuiltin()
            if isFirstRun {
                DispatchQueue.main.async { [weak self] in self?.showSettings(.home) }
            }
        }

        // Stop the engine we launched when the app quits, so it isn't orphaned
        // (an orphaned engine keeps the lock and hides the logged one).
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.engine.stop()
                self?.builtin.stop()
            }
        }
    }

    // MARK: Database lifecycle

    private func openDatabase() {
        do {
            paths.ensureRootExists()
            db = try Database(path: paths.dbPath)
            loadError = nil
        } catch {
            db = nil
            loadError = "Cannot open database at \(paths.dbPath): \(error)"
        }
    }

    public func updateBackendRoot(_ url: URL) {
        paths.root = url
        paths.save()
        openDatabase()
        loadConfig()
        loadCollections()
        adoptInitialServerMode()
        syncBuiltin()
    }

    /// A new database starts on the built-in engine; one that already points at a
    /// whisper server keeps it. Saved once, then the user's choice wins.
    private func adoptInitialServerMode() {
        guard let mode = WhisperSource.initialMode(config) else { return }
        isFirstRun = mode == "builtin"
        setStr(ConfigCatalog.serverModeKey, mode, category: "whisper_server")
    }

    /// Prompt for a new backend folder and switch to it.
    public func chooseBackendFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = paths.root
        if panel.runModal() == .OK, let url = panel.url {
            updateBackendRoot(url)
        }
    }

    // MARK: Loading

    public func loadConfig() {
        guard let db else { return }
        config = (try? db.allConfig()) ?? [:]
    }

    public func loadCollections() {
        loadDictionary()
        loadProfanity()
        loadPrompts()
        loadStats()
    }

    public func loadDictionary() { dictionary = (try? db?.dictionaryEntries()) ?? [] }
    public func loadProfanity() { profanity = (try? db?.profanityFilters()) ?? [] }
    public func loadPrompts() { prompts = (try? db?.prompts()) ?? [] }

    public func loadStats() {
        summary = (try? db?.statsSummary()) ?? .empty
        dailyCounts = (try? db?.dailyWordCounts()) ?? []
        recentLogs = LogReader.recentEntries(in: paths.logsDir, limit: 40)
    }

    // MARK: Typed config access

    public func str(_ key: String, default def: String = "") -> String {
        config[key] ?? def
    }
    public func bool(_ key: String) -> Bool {
        (config[key] ?? "").lowercased() == "true"
    }
    public func intVal(_ key: String, default def: Int = 0) -> Int {
        Int(config[key] ?? "") ?? def
    }

    public func setStr(_ key: String, _ value: String, category: String) {
        config[key] = value
        try? db?.setConfig(key, value, category: category)
        if key == ConfigCatalog.sttProviderKey || key == ConfigCatalog.builtinModelKey {
            syncBuiltin()
        }
    }
    public func setBool(_ key: String, _ value: Bool, category: String) {
        setStr(key, value ? "True" : "False", category: category)
    }
    public func setInt(_ key: String, _ value: Int, category: String) {
        setStr(key, String(value), category: category)
    }

    public func bindingBool(_ key: String, category: String) -> Binding<Bool> {
        Binding(get: { self.bool(key) }, set: { self.setBool(key, $0, category: category) })
    }
    public func bindingString(_ key: String, category: String) -> Binding<String> {
        Binding(get: { self.str(key) }, set: { self.setStr(key, $0, category: category) })
    }

    // MARK: Dictionary CRUD

    public func addDictionary(category: String, from: String, to: String) {
        _ = try? db?.addDictionaryEntry(category: category, from: from, to: to)
        loadDictionary()
    }
    public func updateDictionary(_ e: DictionaryEntry) {
        try? db?.updateDictionaryEntry(id: e.id, category: e.category, from: e.from, to: e.to)
        loadDictionary()
    }
    public func deleteDictionary(_ e: DictionaryEntry) {
        try? db?.deleteDictionaryEntry(id: e.id)
        loadDictionary()
    }

    // MARK: Profanity CRUD

    public func addProfanity(word: String, replacement: String) {
        _ = try? db?.addProfanity(word: word, replacement: replacement)
        loadProfanity()
    }
    public func updateProfanity(_ e: ProfanityEntry) {
        try? db?.updateProfanity(id: e.id, word: e.word, replacement: e.replacement)
        loadProfanity()
    }
    public func deleteProfanity(_ e: ProfanityEntry) {
        try? db?.deleteProfanity(id: e.id)
        loadProfanity()
    }

    // MARK: Prompts

    public func savePrompt(name: String, text: String) {
        try? db?.setPrompt(name: name, text: text)
        loadPrompts()
    }
    public func deletePrompt(name: String) {
        try? db?.deletePrompt(name: name)
        loadPrompts()
    }

    // MARK: Hotkeys

    public var noAIHotkey: HotkeyCombo { HotkeyCombo.parse(str(ConfigCatalog.hotkeyNoAIKey, default: "ctrl+alt")) }
    public var withAIHotkey: HotkeyCombo { HotkeyCombo.parse(str(ConfigCatalog.hotkeyWithAIKey, default: "ctrl+cmd")) }

    public func setNoAIHotkey(_ combo: HotkeyCombo) {
        setStr(ConfigCatalog.hotkeyNoAIKey, combo.engineString, category: "hotkeys")
    }
    public func setWithAIHotkey(_ combo: HotkeyCombo) {
        setStr(ConfigCatalog.hotkeyWithAIKey, combo.engineString, category: "hotkeys")
    }

    // MARK: Engine control

    // MARK: Whisper source (built-in engine, local server, or remote LAN server)

    /// "builtin" | "local" | "remote".
    public var serverMode: String { WhisperSource.mode(config) }

    /// True when configured to use a remote LAN whisper server.
    public var isRemoteMode: Bool { serverMode == "remote" }

    /// Address of the locally-launched whisper-server. Falls back to the legacy
    /// single `whisper_server.url` so a customized local port is preserved.
    public var localServerURL: String {
        str(ConfigCatalog.localURLKey,
            default: str(ConfigCatalog.serverURLKey, default: "http://127.0.0.1:8080"))
    }
    /// Address of the remote LAN whisper server used in remote mode.
    public var remoteServerURL: String {
        str(ConfigCatalog.remoteURLKey)
    }
    /// The URL that transcription actually targets, derived from the mode.
    public func effectiveServerURL() -> String {
        isRemoteMode ? remoteServerURL : localServerURL
    }

    // MARK: Whisper server power (via the external whisperctl supervisor)

    /// Address of the external `whisperctl` supervisor panel. Blank/unset falls
    /// back to its installed default.
    public var whisperControlURL: String {
        let raw = str(ConfigCatalog.controlURLKey).trimmingCharacters(in: .whitespaces)
        return raw.isEmpty ? "http://127.0.0.1:8722" : raw
    }

    /// True while a start/stop request to the supervisor is in flight.
    @Published public private(set) var serverControlBusy = false
    /// Why the last start/stop failed, shown next to the control.
    @Published public var serverControlError: String?

    // MARK: Apple on-device speech

    /// Whether this Mac can run Apple's on-device transcriber (macOS 26+).
    public let appleSpeechAvailable = AppleSpeechSTT.isSupported
    /// Locale identifiers the transcriber supports, for the Settings picker.
    @Published public private(set) var appleSpeechLocales: [String] = []

    /// Fetch the supported language list once, on demand.
    public func loadAppleSpeechLocales() {
        guard appleSpeechLocales.isEmpty, appleSpeechAvailable else { return }
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        Task { [weak self] in
            let locales = await AppleSpeechSTT.supportedLocaleIdentifiers()
            self?.appleSpeechLocales = locales
        }
    }

    /// Last status the supervisor reported (pid, uptime, loaded model).
    @Published public private(set) var whisperPanel: WhisperServerControl.Status = .unknown
    /// Whether the supervisor itself answered the last poll. Distinct from
    /// `whisperPanel.running`: the panel can be up while whisper-server is off.
    @Published public private(set) var whisperPanelReachable = false
    /// Models sitting in whisper.cpp's `models/` directory.
    @Published public private(set) var whisperModels: [WhisperServerControl.Model] = []
    /// True while a model switch is in flight.
    @Published public private(set) var whisperModelSwitching = false

    /// Ask the supervisor to start whisper-server, then re-check reachability.
    public func startWhisperServer() {
        runServerControl(expectRunning: true) {
            try await WhisperServerControl(baseURL: $0).start()
        }
    }

    /// Ask the supervisor to stop whisper-server, then re-check reachability.
    public func stopWhisperServer() {
        runServerControl(expectRunning: false) {
            try await WhisperServerControl(baseURL: $0).stop()
        }
    }

    /// Restart whisper-server (needed after a host/port/thread change, which the
    /// supervisor cannot hot-swap).
    public func restartWhisperServer() {
        runServerControl(expectRunning: true) {
            try await WhisperServerControl(baseURL: $0).restart()
        }
    }

    /// Pull the supervisor's status and model list. Safe to call on tab appear;
    /// a failure just marks the panel unreachable rather than raising.
    public func refreshWhisperPanel() {
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        let control = WhisperServerControl(baseURL: whisperControlURL)
        Task { [weak self] in
            do {
                let status = try await control.status()
                let models = try await control.models()
                guard let self else { return }
                self.whisperPanel = status
                self.whisperModels = models
                self.whisperPanelReachable = true
            } catch {
                self?.whisperPanelReachable = false
                self?.whisperPanel = .unknown
            }
        }
    }

    /// Switch the loaded whisper model. The supervisor hot-swaps a running
    /// server, so this does not interrupt dictation.
    public func setWhisperModel(_ file: String) {
        guard !whisperModelSwitching, file != whisperPanel.model else { return }
        whisperModelSwitching = true
        serverControlError = nil
        let url = whisperControlURL
        Task { [weak self] in
            do {
                try await WhisperServerControl(baseURL: url).setModel(file)
            } catch {
                self?.serverControlError = Self.controlErrorText(error, url: url)
            }
            self?.whisperModelSwitching = false
            self?.refreshWhisperPanel()
            await self?.engine.checkServer()
        }
    }

    /// Shared plumbing: flip `serverControlBusy`, call the supervisor, then poll
    /// reachability until it matches `expectRunning` (a big model takes seconds to
    /// load, so a single immediate check would report a false "off").
    private func runServerControl(expectRunning: Bool,
                                  _ action: @escaping (String) async throws -> Void) {
        guard !serverControlBusy else { return }
        serverControlBusy = true
        serverControlError = nil
        let url = whisperControlURL
        Task { [weak self] in
            do {
                try await action(url)
            } catch {
                self?.serverControlError = Self.controlErrorText(error, url: url)
            }
            for _ in 0..<15 {
                guard let self else { return }
                await self.engine.checkServer()
                if self.engine.serverRunning == expectRunning { break }
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
            self?.serverControlBusy = false
            self?.refreshWhisperPanel()
        }
    }

    /// Plain-English failure text. The common case by far is the supervisor not
    /// running at all, which as a raw `URLError` says nothing useful.
    private static func controlErrorText(_ error: Error, url: String) -> String {
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain {
            return "Can't reach the whisper control panel at \(url)."
        }
        if case ProviderError.http(let code, _) = error {
            return "Whisper control panel refused the request (HTTP \(code))."
        }
        return String(describing: error)
    }

    /// Switch between the built-in engine and a local/remote server, effective now.
    public func setServerMode(_ mode: String) {
        setStr(ConfigCatalog.serverModeKey, mode, category: "whisper_server")
        applyServerSettingsAndRestart()
    }

    // MARK: Built-in speech engine

    /// The built-in engine is the chosen source (or no server address is set yet).
    public var builtinChosen: Bool { WhisperSource.usesBuiltin(config) }

    /// The user's own server stopped answering and the built-in engine stands in.
    public var builtinCovering: Bool {
        externalWatch.covering && WhisperSource.usesExternal(config)
            && externalTarget == str(ConfigCatalog.serverURLKey)
    }

    /// Dictation goes through the built-in engine right now.
    public var speechOnBuiltin: Bool { builtinChosen || builtinCovering }

    private var builtinOptions: BuiltinWhisper.Options {
        .init(model: str(ConfigCatalog.builtinModelKey), autoModel: str(ConfigCatalog.builtinAutoModelKey))
    }

    private func startBuiltin() {
        builtinRunning = true
        syncBuiltin()
        Task { [weak self] in
            while !Task.isCancelled {
                await self?.watchExternal()
                try? await Task.sleep(nanoseconds: 5_000_000_000)
            }
        }
    }

    private func syncBuiltin() {
        guard builtinRunning else { return }
        if !WhisperSource.usesExternal(config) { externalWatch.reset() }
        if speechOnBuiltin { builtin.ensure(builtinOptions) } else { builtin.stop() }
        updateBuiltinSpeech(builtin.status)
    }

    /// Try again now instead of waiting for the next automatic attempt.
    public func retryBuiltin() {
        guard builtinRunning, speechOnBuiltin else { return }
        builtin.restart(builtinOptions)
    }

    public func openModelsFolder() {
        try? FileManager.default.createDirectory(at: builtin.modelsDir, withIntermediateDirectories: true)
        NSWorkspace.shared.open(builtin.modelsDir)
    }

    private func updateBuiltinSpeech(_ status: BuiltinWhisper.Status) {
        let url = builtin.url
        engine.builtinSpeech = speechOnBuiltin
            ? SpeechEndpoint(url: url, unavailable: url == nil ? Self.builtinUnavailable(status) : nil)
            : nil
        if url != lastBuiltinURL {
            lastBuiltinURL = url
            engine.refresh()
        }
    }

    /// What the hotkey says while the built-in engine can't take dictation.
    static func builtinUnavailable(_ status: BuiltinWhisper.Status) -> String {
        switch status.phase {
        case .downloading:
            return "VerbVox is downloading its speech model (\(status.downloadPercent)%). "
                + "Dictation works as soon as it finishes."
        case .failed:
            return "The speech engine is not running. " + (status.error ?? "")
        default:
            return "The speech engine is still starting. Try again in a few seconds."
        }
    }

    /// Probe the user's own server every few seconds. When it stays unreachable the
    /// built-in engine takes over, and when it answers again dictation goes back to
    /// it. Never swaps in the middle of a dictation.
    private func watchExternal() async {
        guard WhisperSource.usesExternal(config) else { return }
        let url = str(ConfigCatalog.serverURLKey)
        if url != externalTarget {
            externalWatch.reset()
            externalTarget = url
        }
        // A server that is starting, stopping or swapping models is busy, not gone.
        guard !serverControlBusy, !whisperModelSwitching else { return }
        let ready = await DictationEngine.ping(url)
        guard WhisperSource.usesExternal(config), url == str(ConfigCatalog.serverURLKey),
              engine.state == .idle, externalWatch.observe(ready: ready, at: Date()) else { return }
        BuiltinWhisper.appendLog(externalWatch.covering
            ? "The whisper server at \(url) is not responding, so the built-in engine is handling dictation until it is back."
            : "The whisper server at \(url) is responding again, so dictation uses it again.",
            to: engine.engineLogPath)
        syncBuiltin()
        await engine.checkServer()
    }
    /// Apply edited server settings (mode / URLs / model / threads) and restart.
    public func applyServerSettingsAndRestart() { applySelectedModelAndRestart() }

    /// Push current config (server URL, model, threads) onto the engine before a
    /// (re)start, so launches always reflect what's saved in the DB. Also keeps
    /// the single URL the Python CLI reads (`whisper_server.url`) in sync with the
    /// selected mode, so the engine and the Swift controller agree.
    private func applyEngineConfig() {
        // Keep the single URL the STT layer reads (`whisper_server.url`) in sync
        // with the selected local/remote mode. The native engine reads this from
        // config at transcription time (Phase 3/6); no per-launch push needed.
        // The built-in engine's port changes every launch, so it never goes in
        // `whisper_server.url`; the engine points the STT at it per dictation.
        if serverMode != "builtin" {
            let effective = effectiveServerURL()
            if config[ConfigCatalog.serverURLKey] != effective {
                setStr(ConfigCatalog.serverURLKey, effective, category: "whisper_server")
            }
        }
        syncBuiltin()
    }

    public func startEngine() {
        applyEngineConfig()
        guard let db else { return }
        let paths = self.paths
        Task { await engine.start(db: db, paths: paths) }
    }
    public func stopEngine() { engine.stop() }

    /// Rebuild `status` from the engine's live published state and update the HUD.
    private func syncEngineStatus() {
        let phase: EngineStatus.Phase
        switch engine.state {
        case .recording: phase = .recording
        case .processing: phase = .processing
        case .idle: phase = engine.engineRunning ? .idle : .stopped
        }
        let newStatus = EngineStatus(
            phase: phase,
            mode: engine.mode,
            lastTranscription: engine.lastTranscription,
            wpm: engine.wpm,
            timestamp: engine.recordingStartedAt)
        status = newStatus
        overlay.update(newStatus)

        // A dictation just finished (processing → idle): stats + history are now
        // written to disk, so reload them. This makes the open History tab update
        // live instead of only when you leave and re-enter it.
        if previousPhase == .processing, phase == .idle {
            loadStats()
        }
        previousPhase = phase
    }

    /// Launch on open unless explicitly opted out. Default ON so a fresh install
    /// starts the whisper server + engine without a manual click.
    public var shouldAutostart: Bool {
        guard let raw = config[ConfigCatalog.autostartKey] else { return true }
        return raw.lowercased() == "true"
    }

    public func autostartIfEnabled() {
        if shouldAutostart { startEngine() }
    }

    public func restartEngine() {
        engine.stop()
        startEngine()
    }

    /// Re-arm the engine so an edited whisper-server URL / mode takes effect and
    /// reachability is re-checked. (The "model" of the v1 name is gone; this
    /// restarts the native listener + health monitor and re-syncs the built-in engine.)
    public func applySelectedModelAndRestart() {
        engine.stop()
        startEngine()
    }
}
