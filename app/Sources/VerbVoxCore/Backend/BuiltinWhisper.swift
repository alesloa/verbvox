import Foundation
import Darwin

/// Runs the whisper.cpp server that ships inside VerbVox.app. It downloads the
/// model on first use, starts `whisper-server` on a free loopback port, restarts it
/// when it crashes, and in automatic mode times a built-in speech clip to pick the
/// largest model this Mac transcribes quickly. Port of VerbVox for Windows'
/// `BuiltinWhisper`; Apple silicon always has Metal, so there is no GPU fallback.
@MainActor
public final class BuiltinWhisper: ObservableObject {
    public enum Phase: Equatable { case idle, downloading, starting, warmingUp, ready, failed }

    public struct Status: Equatable {
        public var phase: Phase = .idle
        public var modelId = ""
        public var modelLabel = ""
        public var received: Int64 = 0
        public var total: Int64 = 0
        public var detail: String?
        public var error: String?
        /// Automatic mode's background work: downloading or testing another model.
        public var background: String?
        public var warmupSeconds: Double?
        public var clipSeconds: Double = 0
        public var downloadedModels: [String] = []

        public var downloadPercent: Int64 { total > 0 ? received * 100 / total : 0 }
    }

    public struct Options: Equatable {
        /// A pinned catalog id, or "" for automatic.
        public var model: String
        /// The model automatic mode settled on earlier.
        public var autoModel: String

        public init(model: String, autoModel: String) {
            self.model = model
            self.autoModel = autoModel
        }
    }

    @Published public private(set) var status = Status()
    /// Saves a config value; automatic mode calls it with the model it settles on.
    public var remember: ((String, String) -> Void)?
    public var url: String? { active?.url }
    var activePid: Int32? { active?.pid }
    public let modelsDir: URL

    private let enginePath: URL?
    private let warmupClip: Data?
    private let logPath: String
    private let isDictating: () -> Bool
    private let downloads = URLSession(configuration: .default)
    private let local: URLSession
    private var options: Options?
    private var runTask: Task<Void, Never>?
    private var adaptTask: Task<Void, Never>?
    private var processes: [ServerProcess] = []
    private var active: ServerProcess?
    /// Bumped by every stop, so late download progress from an old run is dropped.
    private var generation = 0
    private var reaped = false

    public init(enginePath: URL?, modelsDir: URL, warmupClip: Data?, logPath: String,
                isDictating: @escaping () -> Bool) {
        self.enginePath = enginePath
        self.modelsDir = modelsDir
        self.warmupClip = warmupClip
        self.logPath = logPath
        self.isDictating = isDictating
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 300
        local = URLSession(configuration: config)
        status = idleStatus()
    }

    // MARK: Control

    /// Starts the engine, or restarts it when the model choice changed or the last run failed.
    public func ensure(_ options: Options) {
        if runTask != nil, self.options == options, status.phase != .failed { return }
        restart(options)
    }

    public func restart(_ options: Options) {
        // Before `halt`, which rewrites the pid file this reads.
        if !reaped {
            reaped = true
            reapLeftovers()
        }
        halt()
        self.options = options
        status = idleStatus()
        status.phase = .starting
        status.detail = "Starting the speech engine…"
        runTask = Task { [weak self] in await self?.run() }
    }

    public func stop() {
        guard runTask != nil else { return }
        halt()
        status = idleStatus()
    }

    private func halt() {
        generation += 1
        runTask?.cancel()
        runTask = nil
        adaptTask?.cancel()
        adaptTask = nil
        options = nil
        terminateServers()
    }

    private func terminateServers() {
        active = nil
        processes.forEach { $0.terminate() }
        processes = []
        savePids()
    }

    // MARK: Supervision

    private func run() async {
        var failures = 0
        while !Task.isCancelled {
            do {
                try await supervise()
                return
            } catch {
                if Task.isCancelled { return }
                // Nobody has to click anything: a failed download is retried every
                // minute, and an engine that will not run waits 1, 2, 4, 8, then 15 minutes.
                let isDownload = (error as? SpeechEngineError)?.kind == .download
                let minutes = isDownload ? 1 : min(15, 1 << min(failures, 4))
                if !isDownload { failures += 1 }
                fail(message(error) + " VerbVox will try again in "
                     + (minutes == 1 ? "a minute." : "\(minutes) minutes."))
                try? await Task.sleep(nanoseconds: UInt64(minutes) * 60_000_000_000)
            }
        }
    }

    private func supervise() async throws {
        guard let enginePath, FileManager.default.isExecutableFile(atPath: enginePath.path) else {
            throw SpeechEngineError("The speech engine is missing from VerbVox. Reinstall VerbVox.", kind: .engine)
        }
        var crashes: [Date] = []
        while true {
            try Task.checkCancellation()
            guard let options else { return }
            let pinned = WhisperModelCatalog.find(options.model)
            let model = pinned ?? ModelLadder.startingModel(saved: options.autoModel, isDownloaded: isDownloaded)
            try await download(model, background: false)

            update {
                $0.phase = .starting
                $0.modelId = model.id
                $0.modelLabel = model.label
                $0.detail = "Loading \(model.label)…"
                $0.error = nil
            }
            let server = try await startServer(model, engine: enginePath)
            let warm: Double?
            do { warm = try await warmUp(server) } catch {
                discard(server)
                throw error
            }
            activate(server, warm: warm)
            if pinned == nil, let warm, options.autoModel != model.id {
                adaptTask = Task { [weak self] in await self?.adapt(from: server, seconds: warm) }
            }

            await watchActive()
            adaptTask?.cancel()
            adaptTask = nil
            try Task.checkCancellation()
            guard let crashed = active else { return }
            let reason = crashed.failure()
            log(reason)
            discard(crashed)
            active = nil
            let now = Date()
            crashes = crashes.filter { now.timeIntervalSince($0) < 600 } + [now]
            if crashes.count >= 4 {
                throw SpeechEngineError("The speech engine keeps stopping. \(reason)", kind: .engine)
            }
            update {
                $0.phase = .starting
                $0.detail = "The speech engine stopped. Restarting…"
            }
            try await Task.sleep(nanoseconds: UInt64(min(30, 2 * crashes.count)) * 1_000_000_000)
        }
    }

    /// Returns when the active server exits. Automatic mode swaps in a new server
    /// and stops the old one; only the active server stopping counts as a crash.
    private func watchActive() async {
        while let current = active {
            await current.waitForExit()
            if Task.isCancelled || current === active { return }
        }
    }

    private func activate(_ server: ServerProcess, warm: Double?) {
        guard !Task.isCancelled else { return }
        active = server
        log("Speech engine ready: \(server.model.id) at \(server.url)"
            + (warm.map { String(format: ", warm-up %.2fs.", $0) } ?? "."))
        update {
            $0.phase = .ready
            $0.modelId = server.model.id
            $0.modelLabel = server.model.label
            $0.detail = nil
            $0.error = nil
            $0.received = 0
            $0.total = 0
            $0.warmupSeconds = warm
            // `warm` is nil exactly when there is no clip.
            $0.clipSeconds = warmupClip.map(Self.clipLength) ?? 0
        }
    }

    private func fail(_ text: String) {
        log("ERROR " + text)
        terminateServers()
        update {
            $0.phase = .failed
            $0.error = text
            $0.detail = nil
            $0.background = nil
            $0.received = 0
            $0.total = 0
        }
    }

    // MARK: Automatic model choice

    private func adapt(from server: ServerProcess, seconds: Double) async {
        var tried: Set<String> = [server.model.id]
        var current = server
        var seconds = seconds
        defer { update { $0.background = nil } }
        while !Task.isCancelled {
            guard let next = ModelLadder.next(after: current.model.id, seconds: seconds, tried: tried) else {
                settle(current)
                return
            }
            tried.insert(next.id)
            let upgrade = ModelLadder.isUpgrade(next.id, over: current.model.id)
            log(String(format: "%@ took %.2fs; testing %@.", current.model.id, seconds, next.id))
            do {
                try await download(next, background: true)
            } catch {
                // Keep the working model and try again on the next launch.
                if !Task.isCancelled { log("Background download failed: " + message(error)) }
                return
            }
            update { $0.background = "Testing \(next.label) on this Mac…" }
            var candidate: ServerProcess?
            do {
                await waitForIdle()
                guard let enginePath else { return }
                let started = try await startServer(next, engine: enginePath)
                candidate = started
                guard let warm = try await warmUp(started) else { return }
                let accepted = ModelLadder.accepts(next.id, seconds: warm, over: current.model.id, currentSeconds: seconds)
                log(String(format: "%@ took %.2fs; ", next.id, warm)
                    + (accepted ? "switching to it." : "keeping \(current.model.id)."))
                if !accepted {
                    discard(started)
                    candidate = nil
                    // whisper.cpp reads the model into memory, so a rejected download can go.
                    if upgrade { deleteModel(next) }
                    settle(current)
                    return
                }
                await waitForIdle()
                try Task.checkCancellation()
                let previous = current
                current = started
                candidate = nil
                seconds = warm
                activate(current, warm: warm)
                discard(previous)
            } catch {
                if let candidate { discard(candidate) }
                if Task.isCancelled { return }
                log("\(next.id) could not run here, keeping \(current.model.id): " + message(error))
                if upgrade { deleteModel(next) }
                settle(current)
                return
            }
        }
    }

    private func settle(_ server: ServerProcess) {
        guard !Task.isCancelled, var options, options.autoModel != server.model.id else { return }
        options.autoModel = server.model.id
        self.options = options
        remember?(ConfigCatalog.builtinAutoModelKey, server.model.id)
        log("Automatic model settled on \(server.model.id).")
    }

    /// Engines are never swapped in the middle of a dictation.
    private func waitForIdle() async {
        while isDictating(), !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
    }

    // MARK: Models

    private func modelPath(_ model: WhisperModelInfo) -> URL { modelsDir.appendingPathComponent(model.fileName) }

    private func isDownloaded(_ model: WhisperModelInfo) -> Bool {
        VerifiedDownload.fileSize(modelPath(model)) == model.size
    }

    /// Bytes already on disk from an interrupted download.
    private func partialSize(_ model: WhisperModelInfo) -> Int64 {
        VerifiedDownload.fileSize(modelPath(model).appendingPathExtension("partial")) ?? 0
    }

    private func downloadedModels() -> [String] {
        WhisperModelCatalog.models.filter(isDownloaded).map(\.id)
    }

    private func download(_ model: WhisperModelInfo, background: Bool) async throws {
        if isDownloaded(model) { return }
        let megabytes = model.size / 1_000_000
        let gen = generation
        var attempt = 0
        while true {
            attempt += 1
            do {
                try checkDiskSpace(model)
                let partial = partialSize(model)
                log("Downloading \(model.fileName) from \(model.url.host ?? "")"
                    + (partial > 0 ? ", resuming after \(partial / 1_000_000) MB." : "."))
                if !background {
                    update {
                        $0.phase = .downloading
                        $0.modelId = model.id
                        $0.modelLabel = model.label
                        $0.total = model.size
                        $0.detail = "Downloading the \(model.label) speech model (\(megabytes) MB). This happens once."
                    }
                }
                try await VerifiedDownload.download(
                    session: downloads, from: model.url, to: modelPath(model),
                    size: model.size, sha256: model.sha256) { [weak self] progress in
                    Task { @MainActor in self?.report(progress, model: model, background: background, generation: gen) }
                }
                log("Downloaded \(model.fileName).")
                update { $0.downloadedModels = self.downloadedModels() }
                return
            } catch {
                if Task.isCancelled { throw CancellationError() }
                let text = (error as? URLError)?.code == .timedOut ? "The connection timed out." : message(error)
                log("Download attempt \(attempt) of \(model.fileName) failed: \(text)")
                if attempt == 3 { throw SpeechEngineError("Could not download the \(model.label) speech model. \(text)") }
                if !background { update { $0.detail = "The download was interrupted. Retrying in \(attempt * 5) seconds…" } }
                try await Task.sleep(nanoseconds: UInt64(attempt * 5) * 1_000_000_000)
            }
        }
    }

    private func report(_ progress: DownloadProgress, model: WhisperModelInfo, background: Bool, generation gen: Int) {
        guard gen == generation else { return }
        if background {
            guard adaptTask != nil else { return }
            let percent = progress.total > 0 ? progress.received * 100 / progress.total : 0
            status.background = "Downloading \(model.label) (\(model.size / 1_000_000) MB) to test "
                + "whether this Mac runs it well… \(percent)%"
        } else if status.phase == .downloading, status.modelId == model.id {
            status.received = progress.received
            status.total = progress.total
        }
    }

    private func checkDiskSpace(_ model: WhisperModelInfo) throws {
        try FileManager.default.createDirectory(at: modelsDir, withIntermediateDirectories: true)
        let needed = model.size - partialSize(model) + 50_000_000
        let free = try? modelsDir.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            .volumeAvailableCapacityForImportantUsage
        if let free, free < needed {
            throw SpeechEngineError("This Mac needs \(needed / 1_000_000) MB free for the \(model.label) model.")
        }
    }

    private func deleteModel(_ model: WhisperModelInfo) {
        do { try FileManager.default.removeItem(at: modelPath(model)) } catch {
            log("Could not delete \(model.fileName): \(error.localizedDescription)")
        }
        status.downloadedModels = downloadedModels()
    }

    // MARK: Server processes

    private func startServer(_ model: WhisperModelInfo, engine: URL) async throws -> ServerProcess {
        var attempt = 0
        while true {
            attempt += 1
            let server = try launch(model, engine: engine, port: Self.freePort())
            do {
                try await waitForHealth(server)
                return server
            } catch {
                discard(server)
                if server.bindFailed, attempt < 3 {
                    log("Port \(server.port) was taken; choosing another.")
                    continue
                }
                throw error
            }
        }
    }

    private func launch(_ model: WhisperModelInfo, engine: URL, port: Int) throws -> ServerProcess {
        let threads = max(1, min(16, ProcessInfo.processInfo.activeProcessorCount / 2))
        let server: ServerProcess
        do {
            server = try ServerProcess(engine: engine, modelPath: modelPath(model), model: model,
                                       port: port, threads: threads, logPath: logPath)
        } catch {
            throw SpeechEngineError("The speech engine could not start. \(error.localizedDescription)", kind: .engine)
        }
        processes.append(server)
        savePids()
        log("Started whisper-server for \(model.id) on port \(port), \(threads) threads.")
        return server
    }

    private func waitForHealth(_ server: ServerProcess) async throws {
        let deadline = Date().addingTimeInterval(180)
        var request = URLRequest(url: URL(string: server.url + "/health")!)
        request.timeoutInterval = 2
        while true {
            try Task.checkCancellation()
            if server.hasExited { throw SpeechEngineError(server.failure(), kind: .engine) }
            if Date() > deadline {
                throw SpeechEngineError("The speech engine did not start within three minutes.", kind: .engine)
            }
            if let (_, response) = try? await local.data(for: request),
               (response as? HTTPURLResponse)?.statusCode == 200 { return }
            try await Task.sleep(nanoseconds: 250_000_000)
        }
    }

    /// Transcribes the bundled clip twice and returns the second pass's time (the
    /// first pass pages the model in). Nil when the clip is missing.
    private func warmUp(_ server: ServerProcess) async throws -> Double? {
        guard let clip = warmupClip else { return nil }
        if active == nil {
            update {
                $0.phase = .warmingUp
                $0.detail = "Checking speed on this Mac…"
            }
        }
        let stt = WhisperServerSTT(url: server.url, session: local)
        var seconds = 0.0
        for _ in 0..<2 {
            let start = Date()
            let text: String
            do {
                text = try await stt.transcribe(wav: clip, language: nil).text
            } catch {
                try Task.checkCancellation()
                // A crash drops the connection a moment before the exit is observed.
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                throw SpeechEngineError(server.hasExited ? server.failure()
                                        : "The warm-up transcription failed. " + message(error), kind: .engine)
            }
            seconds = Date().timeIntervalSince(start)
            if !ModelLadder.recognizesWarmup(text) { log("Warm-up transcript did not match the clip: \"\(text)\"") }
        }
        log(String(format: "Warm-up with %@: %.2fs.", server.model.id, seconds))
        return seconds
    }

    private func discard(_ server: ServerProcess) {
        server.terminate()
        processes.removeAll { $0 === server }
        savePids()
    }

    // MARK: Leftover servers

    /// Servers that are running, so a VerbVox that crashed can stop them on its next launch.
    static func pidFile(_ modelsDir: URL) -> URL { modelsDir.appendingPathComponent(".whisper-server.pids") }

    static func savePids(_ pids: [Int32], modelsDir: URL) {
        try? FileManager.default.createDirectory(at: modelsDir, withIntermediateDirectories: true)
        try? pids.map(String.init).joined(separator: "\n")
            .write(to: pidFile(modelsDir), atomically: true, encoding: .utf8)
    }

    private func savePids() { Self.savePids(processes.map(\.pid), modelsDir: modelsDir) }

    /// Stops a server an earlier VerbVox left behind, but only when that pid still
    /// runs this exact engine binary.
    private func reapLeftovers() {
        guard let enginePath,
              let text = try? String(contentsOf: Self.pidFile(modelsDir), encoding: .utf8) else { return }
        let ours = enginePath.resolvingSymlinksInPath().path
        for pid in text.split(separator: "\n").compactMap({ Int32($0) }) where Self.executablePath(pid) == ours {
            kill(pid, SIGTERM)
            log("Stopped a speech engine left running by an earlier VerbVox (pid \(pid)).")
        }
        Self.savePids([], modelsDir: modelsDir)
    }

    static func executablePath(_ pid: Int32) -> String? {
        var buffer = [CChar](repeating: 0, count: 4096)
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
        return String(cString: buffer)
    }

    // MARK: Helpers

    private func idleStatus() -> Status {
        var status = Status()
        status.downloadedModels = downloadedModels()
        return status
    }

    private func update(_ change: (inout Status) -> Void) {
        guard !Task.isCancelled else { return }
        change(&status)
    }

    private func message(_ error: Error) -> String {
        (error as? SpeechEngineError)?.description ?? error.localizedDescription
    }

    private func log(_ text: String) { Self.appendLog(text, to: logPath) }

    nonisolated static func appendLog(_ text: String, to path: String) {
        let stamp = ISO8601DateFormatter().string(from: Date())
        let lines = text.split(separator: "\n", omittingEmptySubsequences: true)
            .map { "\(stamp) \($0)\n" }.joined()
        if !FileManager.default.fileExists(atPath: path) {
            FileManager.default.createFile(atPath: path, contents: nil)
        }
        guard let handle = FileHandle(forWritingAtPath: path) else { return }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: Data(lines.utf8))
    }

    /// Seconds of audio in a canonical 44-byte-header WAV: data length / byte rate.
    static func clipLength(_ wav: Data) -> Double {
        guard wav.count > 44 else { return 0 }
        let byteRate = wav.subdata(in: 28..<32).withUnsafeBytes { UInt32(littleEndian: $0.loadUnaligned(as: UInt32.self)) }
        return byteRate > 0 ? Double(wav.count - 44) / Double(byteRate) : 0
    }

    /// A loopback port the OS just handed out. whisper-server binds it a moment
    /// later; a lost race shows up as a bind failure and `startServer` retries.
    static func freePort() -> Int {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        defer { close(fd) }
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let bound = withUnsafeMutablePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, length) == 0 && getsockname(fd, $0, &length) == 0
            }
        }
        return bound ? Int(UInt16(bigEndian: address.sin_port)) : Int.random(in: 49152...65535)
    }
}

/// One running whisper-server. Output goes to the server log, and the last lines
/// are kept to explain a crash.
final class ServerProcess: @unchecked Sendable {
    let model: WhisperModelInfo
    let port: Int
    var url: String { "http://127.0.0.1:\(port)" }
    var pid: Int32 { process.processIdentifier }

    private let process = Process()
    private let logPath: String
    private let lock = NSLock()
    private var tail: [String] = []
    private var pending = Data()
    private var exited = false
    private var sawBindFailure = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(engine: URL, modelPath: URL, model: WhisperModelInfo, port: Int, threads: Int, logPath: String) throws {
        self.model = model
        self.port = port
        self.logPath = logPath
        process.executableURL = engine
        process.arguments = ["-m", modelPath.path, "-t", String(threads),
                             "--host", "127.0.0.1", "--port", String(port)]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty { handle.readabilityHandler = nil } else { self?.consume(data) }
        }
        process.terminationHandler = { [weak self] _ in self?.markExited() }
        try process.run()
    }

    var hasExited: Bool { lock.withLock { exited } }
    var bindFailed: Bool { lock.withLock { sawBindFailure } }

    func waitForExit() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let done = lock.withLock { () -> Bool in
                if exited { return true }
                waiters.append(continuation)
                return false
            }
            if done { continuation.resume() }
        }
    }

    func terminate() {
        if process.isRunning { process.terminate() }
        markExited()
    }

    func failure() -> String {
        let lines = lock.withLock { Array(tail.suffix(3)) }
        let code = process.isRunning ? "" : " (exit code \(process.terminationStatus))"
        return "The speech engine stopped\(code)."
            + (lines.isEmpty ? "" : " Last output: " + lines.joined(separator: " | "))
    }

    private func markExited() {
        let waiting = lock.withLock { () -> [CheckedContinuation<Void, Never>] in
            exited = true
            defer { waiters = [] }
            return waiters
        }
        waiting.forEach { $0.resume() }
    }

    private func consume(_ data: Data) {
        let lines: [String] = lock.withLock {
            pending.append(data)
            var complete: [String] = []
            while let newline = pending.firstIndex(of: 0x0A) {
                let line = String(decoding: pending[pending.startIndex..<newline], as: UTF8.self)
                pending.removeSubrange(pending.startIndex...newline)
                guard !line.trimmingCharacters(in: .whitespaces).isEmpty else { continue }
                complete.append(line)
                tail.append(line)
                if line.contains("couldn't bind to server socket") { sawBindFailure = true }
            }
            if tail.count > 30 { tail.removeFirst(tail.count - 30) }
            return complete
        }
        if !lines.isEmpty {
            BuiltinWhisper.appendLog(lines.map { "[whisper] " + $0 }.joined(separator: "\n"), to: logPath)
        }
    }
}
