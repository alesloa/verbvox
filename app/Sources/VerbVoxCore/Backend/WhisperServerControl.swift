import Foundation

/// Client for the external `whisperctl` supervisor that owns the whisper-server
/// process (a launchd agent on :8722 that spawns and watches whisper-server on
/// :8080).
///
/// This is for the user's own server only; VerbVox's bundled engine is run by
/// `BuiltinWhisper`. No process is spawned here: VerbVox asks a separate,
/// already-running service to start or stop its own child, exactly as the
/// whisperctl web panel does. If the supervisor is not installed the calls simply
/// fail to connect and the UI reports it.
///
/// Endpoints used (see `whisperctl/server.js`):
/// `GET /api/status`, `POST /api/start`, `POST /api/stop`, `POST /api/restart`.
public struct WhisperServerControl {

    /// The supervisor's view of the whisper-server child: `running` is "the
    /// process is alive", `healthy` is "it answers its HTTP endpoint".
    public struct Status {
        public let running: Bool
        public let healthy: Bool
        public let pid: Int?
        public let uptimeSec: Int
        /// File name of the model the supervisor has loaded, e.g. `ggml-medium.en.bin`.
        public let model: String
        /// Where the supervisor says whisper-server listens.
        public let whisperURL: String

        public static let unknown = Status(running: false, healthy: false, pid: nil,
                                           uptimeSec: 0, model: "", whisperURL: "")
    }

    /// One ggml model file sitting in whisper.cpp's `models/` directory.
    public struct Model: Identifiable, Equatable {
        public let file: String   // "ggml-large-v3-turbo.bin"
        public let name: String   // "large-v3-turbo"
        public let sizeMB: Int
        public var id: String { file }

        /// English-only weights, which whisper.cpp marks with a `.en` suffix.
        public var isEnglishOnly: Bool { name.hasSuffix(".en") }
    }

    let baseURL: String
    let session: URLSession

    public init(baseURL: String, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    public func status() async throws -> Status {
        let data = try await call(path: "/api/status", method: "GET")
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ProviderError.decode("unexpected whisperctl status response")
        }
        let whisperConfig = (object["config"] as? [String: Any])?["whisper"] as? [String: Any]
        return Status(running: object["running"] as? Bool ?? false,
                      healthy: object["healthy"] as? Bool ?? false,
                      pid: object["pid"] as? Int,
                      uptimeSec: object["uptimeSec"] as? Int ?? 0,
                      model: whisperConfig?["model"] as? String ?? "",
                      whisperURL: object["whisperUrl"] as? String ?? "")
    }

    /// The ggml models already downloaded, in the order the supervisor lists them.
    public func models() async throws -> [Model] {
        let data = try await call(path: "/api/models", method: "GET")
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let installed = object["installed"] as? [[String: Any]] else {
            throw ProviderError.decode("unexpected whisperctl models response")
        }
        return installed.compactMap { entry in
            guard let file = entry["file"] as? String else { return nil }
            return Model(file: file,
                         name: entry["name"] as? String ?? file,
                         sizeMB: entry["sizeMB"] as? Int ?? 0)
        }
    }

    /// Switch the loaded model. The supervisor hot-swaps a running server, so a
    /// model change costs no downtime; only `model` is sent so the saved host,
    /// port and thread count survive the write.
    public func setModel(_ file: String) async throws {
        let body = try JSONSerialization.data(withJSONObject: ["whisper": ["model": file]])
        _ = try await call(path: "/api/config", method: "POST", json: body)
    }

    public func start() async throws {
        _ = try await call(path: "/api/start", method: "POST")
    }

    public func stop() async throws {
        _ = try await call(path: "/api/stop", method: "POST")
    }

    public func restart() async throws {
        _ = try await call(path: "/api/restart", method: "POST")
    }

    /// A start can take a while (a large model loads before the server answers),
    /// so give the supervisor room rather than the 1.5s health-ping timeout.
    private func call(path: String, method: String, json: Data? = nil) async throws -> Data {
        let trimmed = baseURL.hasSuffix("/") ? String(baseURL.dropLast()) : baseURL
        // A hand-typed panel address is a real input, so reject one that has no
        // scheme/host here rather than letting URLSession raise an opaque -1002.
        guard let endpoint = URL(string: trimmed + path),
              endpoint.scheme != nil, endpoint.host != nil else {
            throw ProviderError.decode("invalid whisperctl url: \(baseURL)")
        }
        var request = URLRequest(url: endpoint)
        request.httpMethod = method
        request.timeoutInterval = 30
        if let json {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = json
        }

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ProviderError.http(-1, "no HTTP response")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw ProviderError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        return data
    }
}
