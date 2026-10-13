import XCTest
@testable import VerbVoxCore

/// The built-in engine supervisor. The first tests always run; the live ones need
/// the engine built by `scripts/whisper-engine.sh` and download real models from
/// Hugging Face into /tmp/verbvox-live-models, so they only run with
/// `VERBVOX_LIVE_ENGINE=1 swift test --filter BuiltinWhisperTests`.
@MainActor
final class BuiltinWhisperTests: XCTestCase {

    private static let appDir = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    private static let enginePath = appDir.appendingPathComponent(".cache/whisper-engine/macos-arm64/whisper-server")
    private static let warmupClip = try? Data(contentsOf: appDir.appendingPathComponent("Resources/warmup.wav"))
    private static let liveModels = URL(fileURLWithPath: "/tmp/verbvox-live-models", isDirectory: true)

    private var engines: [BuiltinWhisper] = []

    override func tearDown() async throws {
        engines.forEach { $0.stop() }
        engines = []
        try await super.tearDown()
    }

    private func make(enginePath: URL?, modelsDir: URL) -> BuiltinWhisper {
        let engine = BuiltinWhisper(enginePath: enginePath, modelsDir: modelsDir, warmupClip: Self.warmupClip,
                                    logPath: NSTemporaryDirectory() + "verbvox-builtin-test.log",
                                    isDictating: { false })
        engines.append(engine)
        return engine
    }

    private func until(_ timeout: TimeInterval, _ what: String, _ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline { XCTFail("Timed out: \(what)"); throw CancellationError() }
            try await Task.sleep(nanoseconds: 200_000_000)
        }
    }

    private func requireLive() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["VERBVOX_LIVE_ENGINE"] == "1",
                          "Set VERBVOX_LIVE_ENGINE=1 to run the live engine tests.")
        try XCTSkipUnless(FileManager.default.isExecutableFile(atPath: Self.enginePath.path),
                          "Run scripts/whisper-engine.sh first.")
    }

    // MARK: Always

    func testMissingEngineFailsWithAReinstallMessage() async throws {
        let models = FileManager.default.temporaryDirectory.appendingPathComponent("vv-\(UUID().uuidString)")
        let engine = make(enginePath: nil, modelsDir: models)
        engine.restart(.init(model: "", autoModel: ""))
        try await until(5, "failed phase") { engine.status.phase == .failed }
        XCTAssertTrue(engine.status.error?.contains("Reinstall VerbVox") == true, engine.status.error ?? "")
        XCTAssertNil(engine.url)
    }

    func testWarmupClipLength() throws {
        let clip = try XCTUnwrap(Self.warmupClip)
        XCTAssertEqual(BuiltinWhisper.clipLength(clip), 8.5, accuracy: 0.01)
    }

    // MARK: Live

    func testFirstRunDownloadsStartsTranscribesAndSettles() async throws {
        try requireLive()
        let engine = make(enginePath: Self.enginePath, modelsDir: Self.liveModels)
        var remembered: [String: String] = [:]
        engine.remember = { remembered[$0] = $1 }
        engine.restart(.init(model: "", autoModel: ""))

        try await until(600, "ready") { engine.status.phase == .ready }
        XCTAssertEqual(engine.status.modelId, ModelLadder.smallId)
        XCTAssertNotNil(engine.status.warmupSeconds)
        let url = try XCTUnwrap(engine.url)
        let clip = try XCTUnwrap(Self.warmupClip)
        let text = try await WhisperServerSTT(url: url).transcribe(wav: clip, language: nil).text
        XCTAssertTrue(ModelLadder.recognizesWarmup(text), text)

        // Automatic mode keeps measuring in the background until it settles on a model.
        try await until(900, "automatic choice saved") { remembered[ConfigCatalog.builtinAutoModelKey] != nil }
        XCTAssertEqual(engine.status.phase, .ready)
        XCTAssertEqual(engine.status.modelId, remembered[ConfigCatalog.builtinAutoModelKey])
        XCTAssertNil(engine.status.background)
        print("LIVE: settled on \(engine.status.modelId) — warm-up \(engine.status.warmupSeconds ?? -1)s")
    }

    func testCrashedEngineRestarts() async throws {
        try requireLive()
        let engine = make(enginePath: Self.enginePath, modelsDir: Self.liveModels)
        engine.restart(.init(model: ModelLadder.baseId, autoModel: ""))
        try await until(300, "ready") { engine.status.phase == .ready }
        let first = try XCTUnwrap(engine.activePid)
        kill(first, SIGKILL)
        try await until(5, "crash noticed") { engine.status.phase != .ready }
        try await until(120, "ready again") { engine.status.phase == .ready && engine.activePid != first }
        XCTAssertNotNil(engine.url)
    }

    func testStopEndsTheServer() async throws {
        try requireLive()
        let engine = make(enginePath: Self.enginePath, modelsDir: Self.liveModels)
        engine.restart(.init(model: ModelLadder.baseId, autoModel: ""))
        try await until(300, "ready") { engine.status.phase == .ready }
        let pid = try XCTUnwrap(engine.activePid)
        engine.stop()
        XCTAssertEqual(engine.status.phase, .idle)
        try await until(5, "process gone") { kill(pid, 0) != 0 }
    }

    func testEngineLeftByAnEarlierRunIsStopped() async throws {
        try requireLive()
        // An earlier VerbVox that crashed left its server running and its pid on disk.
        let base = try XCTUnwrap(WhisperModelCatalog.find(ModelLadder.baseId))
        try await VerifiedDownload.download(session: .shared, from: base.url,
                                            to: Self.liveModels.appendingPathComponent(base.fileName),
                                            size: base.size, sha256: base.sha256)
        let leftover = Process()
        leftover.executableURL = Self.enginePath
        leftover.arguments = ["-m", Self.liveModels.appendingPathComponent(base.fileName).path,
                              "--host", "127.0.0.1", "--port", "\(BuiltinWhisper.freePort())"]
        leftover.standardOutput = FileHandle.nullDevice
        leftover.standardError = FileHandle.nullDevice
        try leftover.run()
        addTeardownBlock { if leftover.isRunning { leftover.terminate() } }
        let orphan = leftover.processIdentifier
        BuiltinWhisper.savePids([orphan], modelsDir: Self.liveModels)

        let next = make(enginePath: Self.enginePath, modelsDir: Self.liveModels)
        next.restart(.init(model: ModelLadder.baseId, autoModel: ""))
        try await until(5, "orphan stopped") { kill(orphan, 0) != 0 }
        try await until(120, "new engine ready") { next.status.phase == .ready }
    }
}
