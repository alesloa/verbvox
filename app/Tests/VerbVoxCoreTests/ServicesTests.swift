import XCTest
@testable import VerbVoxCore

final class ServicesTests: XCTestCase {

    // MARK: BackendPaths

    func testDefaultPathsCompose() {
        let p = BackendPaths(root: BackendPaths.defaultRoot, python: BackendPaths.defaultPython)
        XCTAssertTrue(p.dbPath.hasSuffix("VerbVox/transcribe_app.db"))
        XCTAssertTrue(p.logsDir.path.hasSuffix("VerbVox/logs"))
        XCTAssertTrue(p.root.path.contains("Application Support"))
    }

    func testRootOverrideChangesPaths() {
        let p = BackendPaths(root: URL(fileURLWithPath: "/tmp/foo"), python: "/usr/bin/python3")
        XCTAssertEqual(p.dbPath, "/tmp/foo/transcribe_app.db")
        XCTAssertEqual(p.logsDir.path, "/tmp/foo/logs")
    }

    // MARK: EngineStatus.decode

    func testDecodeRecording() {
        let json = #"{"status":"recording","mode":"no_ai","last_transcription":"","wpm":0,"timestamp":123.4}"#
        let s = EngineStatus.decode(from: Data(json.utf8))
        XCTAssertEqual(s?.phase, .recording)
        XCTAssertEqual(s?.mode, "no_ai")
        XCTAssertEqual(s?.timestamp ?? 0, 123.4, accuracy: 0.001)
    }

    func testDecodeIdleWithTranscriptionAndFloatWpm() {
        let json = #"{"status":"idle","mode":"with_ai","last_transcription":"hello world","wpm":152.5,"timestamp":1}"#
        let s = EngineStatus.decode(from: Data(json.utf8))
        XCTAssertEqual(s?.phase, .idle)
        XCTAssertEqual(s?.lastTranscription, "hello world")
        XCTAssertEqual(s?.wpm ?? 0, 152.5, accuracy: 0.001)
    }

    func testDecodeUnknownStatusMapsToUnknown() {
        let json = #"{"status":"weird","mode":"","last_transcription":"","wpm":0,"timestamp":0}"#
        XCTAssertEqual(EngineStatus.decode(from: Data(json.utf8))?.phase, .unknown)
    }

    func testDecodeGarbageReturnsNil() {
        XCTAssertNil(EngineStatus.decode(from: Data("not json".utf8)))
    }

    // MARK: LogReader

    func testParseSimpleLine() {
        let entry = LogReader.parseLine("2026-05-23 08:10:14||This is the text.", app: "zed")
        XCTAssertEqual(entry?.timestamp, "2026-05-23 08:10:14")
        XCTAssertEqual(entry?.text, "This is the text.")
        XCTAssertEqual(entry?.app, "zed")
    }

    func testParseDetailedLineUsesCleanedField() {
        let line = "2026-05-23 08:10:14||Cursor||code_prompt||orig text||cleaned text"
        XCTAssertEqual(LogReader.parseLine(line, app: "Cursor")?.text, "cleaned text")
    }

    func testParseBlankOrMalformedReturnsNil() {
        XCTAssertNil(LogReader.parseLine("", app: "x"))
        XCTAssertNil(LogReader.parseLine("no separators here", app: "x"))
    }

    func testAppNameFromFileName() {
        XCTAssertEqual(LogReader.appName(fromFileName: "23-zed.log"), "zed")
        XCTAssertEqual(LogReader.appName(fromFileName: "23-Code_-_Insiders.log"), "Code - Insiders")
        XCTAssertEqual(LogReader.appName(fromFileName: "01-Windows_App.log"), "Windows App")
    }

    // MARK: Log tail

    func testTailReturnsWholeFileWhenSmall() throws {
        let path = NSTemporaryDirectory() + "tts-tail-\(UUID().uuidString).log"
        try "line1\nline2\n".write(toFile: path, atomically: true, encoding: .utf8)
        XCTAssertEqual(LogReader.tail(of: path, maxBytes: 10_000), "line1\nline2\n")
    }

    func testTailReturnsSuffixWhenLarge() throws {
        let path = NSTemporaryDirectory() + "tts-tail-\(UUID().uuidString).log"
        try String(repeating: "x", count: 100).write(toFile: path, atomically: true, encoding: .utf8)
        XCTAssertEqual(LogReader.tail(of: path, maxBytes: 10).count, 10)
    }

    func testTailMissingFileReturnsEmpty() {
        XCTAssertEqual(LogReader.tail(of: "/no/such/file.log", maxBytes: 100), "")
    }

    // MARK: Real DB compatibility (guarded — only when the copied DB exists)

    func testReadsRealCopiedDatabaseIfPresent() throws {
        let path = BackendPaths.defaultRoot.appendingPathComponent("transcribe_app.db").path
        guard FileManager.default.fileExists(atPath: path) else {
            throw XCTSkip("Real backend DB not present")
        }
        let db = try Database(path: path)
        XCTAssertGreaterThan(try db.dictionaryEntries().count, 0)
        XCTAssertGreaterThan(try db.profanityFilters().count, 0)
        XCTAssertNotNil(try db.configValue("whisper_server.url"))
        XCTAssertGreaterThan(try db.statsSummary().totalCount, 0)
    }
}
