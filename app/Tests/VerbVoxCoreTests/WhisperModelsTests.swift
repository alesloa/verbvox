import XCTest
import CryptoKit
@testable import VerbVoxCore

/// The built-in engine's model catalog, its automatic size ladder, and the
/// resumable, SHA-256-checked model download (served by `MockURLProtocol`).
final class WhisperModelsTests: XCTestCase {

    private var folder: URL!
    private var destination: URL { folder.appendingPathComponent("ggml-test.bin") }
    private var partial: URL { folder.appendingPathComponent("ggml-test.bin.partial") }
    private let url = URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-test.bin")!
    private let content = Data((0..<5000).map { UInt8($0 % 251) })
    private var digest: String { SHA256.hash(data: content).map { String(format: "%02x", $0) }.joined() }

    /// Range headers of every request the mock server saw (nil = no Range).
    private var ranges: [String?] = []

    override func setUp() {
        super.setUp()
        MockURLProtocol.reset()
        ranges = []
        folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("vv-models-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: folder)
        MockURLProtocol.reset()
        super.tearDown()
    }

    /// Serve `content` honoring Range (206) unless told to ignore it.
    private func serve(ignoreRange: Bool = false, body: Data? = nil, status: Int? = nil) {
        let content = self.content
        MockURLProtocol.handler = { [weak self] request, _ in
            let range = request.value(forHTTPHeaderField: "Range")
            self?.ranges.append(range)
            var code = status ?? 200
            var payload = body ?? content
            if status == nil, !ignoreRange, let range,
               let from = Int(range.dropFirst("bytes=".count).dropLast()) {
                if from >= content.count { code = 416; payload = Data() } else {
                    code = 206; payload = content.subdata(in: from..<content.count)
                }
            }
            let response = HTTPURLResponse(url: request.url!, statusCode: code,
                                           httpVersion: "HTTP/1.1", headerFields: nil)!
            return (response, payload)
        }
    }

    private func download(sha256: String? = nil, progress: (@Sendable (DownloadProgress) -> Void)? = nil) async throws {
        try await VerifiedDownload.download(
            session: MockURLProtocol.makeSession(), from: url, to: destination,
            size: Int64(content.count), sha256: sha256 ?? digest, progress: progress)
    }

    private func writePartial(_ data: Data) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try data.write(to: partial)
    }

    // MARK: Catalog

    func testCatalogMatchesTheWindowsBuild() {
        XCTAssertEqual(WhisperModelCatalog.models.map(\.id),
                       ["large-v3-turbo-q5_0", "large-v3-turbo", "small-q5_1", "base-q5_1"])
        for model in WhisperModelCatalog.models {
            XCTAssertEqual(model.url.host, "huggingface.co")
            XCTAssertTrue(model.url.path.hasSuffix("/" + model.fileName))
            XCTAssertEqual(model.sha256.count, 64)
        }
        let small = WhisperModelCatalog.find("small-q5_1")
        XCTAssertEqual(small?.size, 190_085_487)
        XCTAssertEqual(small?.sha256, "ae85e4a935d7a567bd102fe55afc16bb595bdb618e11b2fc7591bc08120411bb")
        XCTAssertNil(WhisperModelCatalog.find(""))
        XCTAssertNil(WhisperModelCatalog.find("medium"))
    }

    // MARK: Ladder

    func testFastSmallUpgradesToTurbo() {
        XCTAssertEqual(ModelLadder.next(after: "small-q5_1", seconds: 0.5, tried: [])?.id, "large-v3-turbo-q5_0")
    }

    func testSlowSmallDropsToBase() {
        XCTAssertEqual(ModelLadder.next(after: "small-q5_1", seconds: 4.5, tried: [])?.id, "base-q5_1")
    }

    func testMiddlingSmallStays() {
        XCTAssertNil(ModelLadder.next(after: "small-q5_1", seconds: 2.0, tried: []))
    }

    func testSlowTurboDropsToSmallUnlessTried() {
        XCTAssertEqual(ModelLadder.next(after: "large-v3-turbo-q5_0", seconds: 3.0, tried: [])?.id, "small-q5_1")
        XCTAssertNil(ModelLadder.next(after: "large-v3-turbo-q5_0", seconds: 3.0, tried: ["small-q5_1"]))
    }

    func testPinnedOnlyModelsAreOffTheLadder() {
        XCTAssertNil(ModelLadder.next(after: "large-v3-turbo", seconds: 0.1, tried: []))
    }

    func testUpgradeMustMeetTheCandidateLimit() {
        XCTAssertTrue(ModelLadder.accepts("large-v3-turbo-q5_0", seconds: 2.4, over: "small-q5_1", currentSeconds: 0.5))
        XCTAssertFalse(ModelLadder.accepts("large-v3-turbo-q5_0", seconds: 2.6, over: "small-q5_1", currentSeconds: 0.5))
    }

    func testDowngradeIsTakenWhenItIsFaster() {
        XCTAssertTrue(ModelLadder.accepts("base-q5_1", seconds: 3.0, over: "small-q5_1", currentSeconds: 4.5))
        XCTAssertTrue(ModelLadder.accepts("small-q5_1", seconds: 3.9, over: "large-v3-turbo-q5_0", currentSeconds: 3.0))
        XCTAssertFalse(ModelLadder.accepts("small-q5_1", seconds: 4.5, over: "large-v3-turbo-q5_0", currentSeconds: 3.0))
    }

    func testStartingModelPrefersTheSavedChoiceOnlyWhenDownloaded() {
        XCTAssertEqual(ModelLadder.startingModel(saved: "large-v3-turbo-q5_0", isDownloaded: { _ in true }).id,
                       "large-v3-turbo-q5_0")
        XCTAssertEqual(ModelLadder.startingModel(saved: "large-v3-turbo-q5_0", isDownloaded: { _ in false }).id,
                       "small-q5_1")
        XCTAssertEqual(ModelLadder.startingModel(saved: "", isDownloaded: { _ in true }).id, "small-q5_1")
    }

    func testWarmupTranscriptNeedsMostOfTheClipWords() {
        XCTAssertTrue(ModelLadder.recognizesWarmup(
            " Please schedule the quarterly review for next Thursday afternoon, and send the updated "
            + "budget spreadsheet to the whole team before Friday."))
        XCTAssertFalse(ModelLadder.recognizesWarmup("[BLANK_AUDIO]"))
        XCTAssertFalse(ModelLadder.recognizesWarmup("schedule the review on thursday"))
    }

    // MARK: Download

    func testFreshDownloadIsVerifiedAndMovedIntoPlace() async throws {
        serve()
        let seen = ProgressLog()
        try await download(progress: { seen.add($0) })
        XCTAssertEqual(try Data(contentsOf: destination), content)
        XCTAssertFalse(FileManager.default.fileExists(atPath: partial.path))
        XCTAssertEqual(ranges, [nil])
        XCTAssertEqual(seen.items.first, DownloadProgress(received: 0, total: Int64(content.count)))
        XCTAssertEqual(seen.items.last, DownloadProgress(received: Int64(content.count), total: Int64(content.count)))
    }

    func testPartialFileResumesWithRangeRequest() async throws {
        try writePartial(content.prefix(1000))
        serve()
        try await download()
        XCTAssertEqual(ranges, ["bytes=1000-"])
        XCTAssertEqual(try Data(contentsOf: destination), content)
    }

    func testServerThatIgnoresRangeRestartsFromTheBeginning() async throws {
        try writePartial(content.prefix(1000))
        serve(ignoreRange: true)
        try await download()
        XCTAssertEqual(ranges, ["bytes=1000-"])
        XCTAssertEqual(try Data(contentsOf: destination), content)
    }

    func testCompletePartialFileIsFinishedWhenServerHasNothingLeft() async throws {
        try writePartial(content)
        serve()
        try await download()
        XCTAssertEqual(ranges, ["bytes=\(content.count)-"])
        XCTAssertEqual(try Data(contentsOf: destination), content)
        XCTAssertFalse(FileManager.default.fileExists(atPath: partial.path))
    }

    func testChecksumMismatchDeletesTheDownload() async throws {
        serve()
        do {
            try await download(sha256: String(repeating: "0", count: 64))
            XCTFail("expected a checksum error")
        } catch {
            XCTAssertTrue("\(error)".contains("checksum"), "\(error)")
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: partial.path))
    }

    func testInterruptedDownloadKeepsThePartialFileAndResumesNextTime() async throws {
        serve(body: content.prefix(2000))
        do {
            try await download()
            XCTFail("expected an early end")
        } catch {
            XCTAssertTrue("\(error)".contains("ended early"), "\(error)")
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
        XCTAssertEqual(try Data(contentsOf: partial).count, 2000)

        serve()
        try await download()
        XCTAssertEqual(ranges.last, "bytes=2000-")
        XCTAssertEqual(try Data(contentsOf: destination), content)
    }

    func testExistingModelIsNotDownloadedAgain() async throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try content.write(to: destination)
        serve()
        try await download()
        XCTAssertEqual(ranges, [])
    }

    func testHttpFailureIsADownloadError() async throws {
        serve(body: Data("Not found".utf8), status: 404)
        do {
            try await download()
            XCTFail("expected an HTTP error")
        } catch {
            XCTAssertTrue("\(error)".contains("HTTP 404"), "\(error)")
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
    }

    func testOversizedBodyIsADownloadError() async throws {
        serve(body: content + Data([1, 2, 3]))
        do {
            try await download()
            XCTFail("expected a size error")
        } catch {
            XCTAssertTrue("\(error)".contains("larger than expected"), "\(error)")
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
    }
}

/// Thread-safe progress recorder (the download reports from URLSession's queue).
private final class ProgressLog: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [DownloadProgress] = []
    var items: [DownloadProgress] { lock.withLock { stored } }
    func add(_ item: DownloadProgress) { lock.withLock { stored.append(item) } }
}
