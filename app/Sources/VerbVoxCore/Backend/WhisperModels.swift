import Foundation
import CryptoKit

/// One downloadable whisper.cpp model for the built-in engine.
public struct WhisperModelInfo: Equatable, Identifiable {
    public let id: String
    public let label: String
    public let fileName: String
    public let size: Int64
    public let sha256: String

    public var url: URL {
        URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/\(fileName)")!
    }
}

public enum WhisperModelCatalog {
    // Sizes and SHA-256 digests are the ones Hugging Face publishes for
    // ggerganov/whisper.cpp (same catalog as VerbVox for Windows).
    public static let models: [WhisperModelInfo] = [
        .init(id: "large-v3-turbo-q5_0", label: "Large v3 Turbo (compressed)", fileName: "ggml-large-v3-turbo-q5_0.bin",
              size: 574_041_195, sha256: "394221709cd5ad1f40c46e6031ca61bce88931e6e088c188294c6d5a55ffa7e2"),
        .init(id: "large-v3-turbo", label: "Large v3 Turbo (full)", fileName: "ggml-large-v3-turbo.bin",
              size: 1_624_555_275, sha256: "1fc70f774d38eb169993ac391eea357ef47c88757ef72ee5943879b7e8e2bc69"),
        .init(id: "small-q5_1", label: "Small (compressed)", fileName: "ggml-small-q5_1.bin",
              size: 190_085_487, sha256: "ae85e4a935d7a567bd102fe55afc16bb595bdb618e11b2fc7591bc08120411bb"),
        .init(id: "base-q5_1", label: "Base (compressed)", fileName: "ggml-base-q5_1.bin",
              size: 59_707_625, sha256: "422f1ae452ade6f30a004d7e5c6a43195e4433bc370bf23fac9cc591f01a8898"),
    ]

    public static func find(_ id: String) -> WhisperModelInfo? { models.first { $0.id == id } }
}

/// Automatic model choice: start on Small, time the warm-up clip, then step up to
/// Turbo on a fast Mac or down to Base on a slow one.
public enum ModelLadder {
    public static let baseId = "base-q5_1"
    public static let smallId = "small-q5_1"
    public static let turboId = "large-v3-turbo-q5_0"
    static let order = [baseId, smallId, turboId]
    static let upgradeBelow = 0.8
    static let turboLimit = 2.5
    static let downgradeAbove = 4.0
    // Words from the bundled warm-up clip; a transcript that misses most of them is broken output.
    static let warmupWords = ["schedule", "quarterly", "review", "thursday", "afternoon",
                              "budget", "spreadsheet", "team", "friday"]

    /// The model to test next after `id` took `seconds` on the warm-up clip, or nil to stay.
    public static func next(after id: String, seconds: Double, tried: Set<String>) -> WhisperModelInfo? {
        guard let rank = order.firstIndex(of: id) else { return nil }
        if seconds <= upgradeBelow, rank + 1 < order.count, !tried.contains(order[rank + 1]) {
            return WhisperModelCatalog.find(order[rank + 1])
        }
        if seconds > limit(id), rank > 0, !tried.contains(order[rank - 1]) {
            return WhisperModelCatalog.find(order[rank - 1])
        }
        return nil
    }

    /// Slowest acceptable warm-up time for a model.
    static func limit(_ id: String) -> Double {
        switch id {
        case turboId: return turboLimit
        case smallId: return downgradeAbove
        default: return .infinity
        }
    }

    /// Whether `candidate` sits higher on the ladder than `current`.
    static func isUpgrade(_ candidate: String, over current: String) -> Bool {
        (order.firstIndex(of: candidate) ?? 0) > (order.firstIndex(of: current) ?? 0)
    }

    /// Whether a tested candidate replaces the current model.
    public static func accepts(_ candidate: String, seconds: Double, over current: String, currentSeconds: Double) -> Bool {
        seconds <= limit(candidate) || (!isUpgrade(candidate, over: current) && seconds < currentSeconds)
    }

    /// The saved automatic choice when its file is on disk, otherwise Small.
    public static func startingModel(saved: String, isDownloaded: (WhisperModelInfo) -> Bool) -> WhisperModelInfo {
        if let model = WhisperModelCatalog.find(saved), isDownloaded(model) { return model }
        return WhisperModelCatalog.find(smallId)!
    }

    public static func recognizesWarmup(_ text: String) -> Bool {
        let lower = text.lowercased()
        return warmupWords.filter { lower.contains($0) }.count >= 5
    }
}

public struct DownloadProgress: Equatable, Sendable {
    public let received: Int64
    public let total: Int64
}

/// A built-in engine problem, worded for the user. `download` failures are retried
/// sooner than an engine that will not run.
public struct SpeechEngineError: Error, CustomStringConvertible {
    public enum Kind { case download, engine }
    public let kind: Kind
    public let description: String
    init(_ description: String, kind: Kind = .download) {
        self.kind = kind
        self.description = description
    }
}

public enum VerifiedDownload {
    /// Downloads to "<destination>.partial", resumes an earlier partial file with
    /// an HTTP Range request, and only moves the file into place once its size and
    /// SHA-256 match. `idleTimeout` is how long the stream may stall.
    public static func download(session: URLSession, from url: URL, to destination: URL,
                                size: Int64, sha256: String, idleTimeout: TimeInterval = 60,
                                progress: (@Sendable (DownloadProgress) -> Void)? = nil) async throws {
        let fm = FileManager.default
        if fileSize(destination) == size { return }
        try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        let partial = destination.appendingPathExtension("partial")

        var hasher = SHA256()
        var received = fileSize(partial) ?? 0
        if received > size {
            try? fm.removeItem(at: partial)
            received = 0
        }
        if received > 0 { received = try hashExisting(partial, into: &hasher) }
        progress?(DownloadProgress(received: received, total: size))

        var request = URLRequest(url: url)
        request.timeoutInterval = idleTimeout
        if received > 0 { request.setValue("bytes=\(received)-", forHTTPHeaderField: "Range") }

        let writer = StreamWriter(partial: partial, size: size, received: received, hasher: hasher, progress: progress)
        let task = session.dataTask(with: request)
        task.delegate = writer
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                writer.continuation = continuation
                task.resume()
            }
        } onCancel: {
            task.cancel()
        }

        if writer.status == 416, writer.received == size {
            // The partial file already held everything.
        } else if let failure = writer.failure {
            if (failure as? URLError)?.code == .timedOut {
                throw SpeechEngineError("The download stalled for \(Int(idleTimeout)) seconds.")
            }
            throw failure
        } else if writer.received != size {
            throw SpeechEngineError("The download ended early (\(writer.received) of \(size) bytes). It will resume on the next try.")
        }

        let actual = writer.hasher.finalize().map { String(format: "%02x", $0) }.joined()
        guard actual == sha256.lowercased() else {
            try? fm.removeItem(at: partial)
            throw SpeechEngineError("The downloaded file failed its checksum (expected \(sha256), got \(actual)). It was deleted; try again.")
        }
        if fm.fileExists(atPath: destination.path) { try fm.removeItem(at: destination) }
        try fm.moveItem(at: partial, to: destination)
    }

    static func fileSize(_ url: URL) -> Int64? {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value
    }

    private static func hashExisting(_ url: URL, into hasher: inout SHA256) throws -> Int64 {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var total: Int64 = 0
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
            total += Int64(chunk.count)
        }
        return total
    }
}

/// Streams the response body into the partial file while hashing it. All callbacks
/// arrive on the session's serial delegate queue.
private final class StreamWriter: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    let partial: URL
    let size: Int64
    let progress: (@Sendable (DownloadProgress) -> Void)?
    var received: Int64
    var hasher: SHA256
    var status = 0
    var failure: Error?
    var continuation: CheckedContinuation<Void, Error>?
    private var handle: FileHandle?
    private var reported: Int64

    init(partial: URL, size: Int64, received: Int64, hasher: SHA256,
         progress: (@Sendable (DownloadProgress) -> Void)?) {
        self.partial = partial
        self.size = size
        self.received = received
        self.hasher = hasher
        self.progress = progress
        reported = received
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 416, received == size {
            completionHandler(.cancel)
            return
        }
        guard (200..<300).contains(status) else {
            failure = SpeechEngineError("The download server returned HTTP \(status) for \(response.url?.host ?? "the server").")
            completionHandler(.cancel)
            return
        }
        do {
            if received > 0, status != 206 {
                // The server ignored the Range request and is sending the whole file.
                received = 0
                hasher = SHA256()
            }
            if received == 0 {
                FileManager.default.createFile(atPath: partial.path, contents: nil)
            }
            let handle = try FileHandle(forWritingTo: partial)
            try handle.truncate(atOffset: UInt64(received))
            try handle.seekToEnd()
            self.handle = handle
            completionHandler(.allow)
        } catch {
            failure = error
            completionHandler(.cancel)
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard failure == nil, let handle else { return }
        guard received + Int64(data.count) <= size else {
            failure = SpeechEngineError("The download is larger than expected.")
            dataTask.cancel()
            return
        }
        do {
            try handle.write(contentsOf: data)
        } catch {
            failure = error
            dataTask.cancel()
            return
        }
        hasher.update(data: data)
        received += Int64(data.count)
        if received - reported >= size / 200 || received == size {
            reported = received
            progress?(DownloadProgress(received: received, total: size))
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        try? handle?.close()
        handle = nil
        let cancelledOnPurpose = (error as? URLError)?.code == .cancelled && (failure != nil || status == 416)
        if failure == nil, let error, !cancelledOnPurpose { failure = error }
        continuation?.resume()
        continuation = nil
    }
}
