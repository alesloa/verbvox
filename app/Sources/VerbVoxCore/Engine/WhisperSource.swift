import Foundation

/// Which whisper dictation goes through. `whisper_server.mode` is "builtin" (the
/// engine that ships inside VerbVox), "local", or "remote" (the user's own server).
/// A local/remote choice with no address yet stays on the built-in engine.
public enum WhisperSource {
    static func isWhisper(_ config: [String: String]) -> Bool {
        (config[ConfigCatalog.sttProviderKey] ?? "").isEmpty
            || config[ConfigCatalog.sttProviderKey] == "whisper_server"
    }

    static func mode(_ config: [String: String]) -> String {
        let raw = config[ConfigCatalog.serverModeKey] ?? ""
        return raw.isEmpty ? "builtin" : raw
    }

    public static func usesExternal(_ config: [String: String]) -> Bool {
        isWhisper(config) && mode(config) != "builtin"
            && !(config[ConfigCatalog.serverURLKey] ?? "").trimmingCharacters(in: .whitespaces).isEmpty
    }

    public static func usesBuiltin(_ config: [String: String]) -> Bool {
        isWhisper(config) && !usesExternal(config)
    }

    /// The mode to save on first open, or nil when one is already saved. A database
    /// that already points at a whisper server keeps using it; only new ones start
    /// on the built-in engine.
    public static func initialMode(_ config: [String: String]) -> String? {
        guard (config[ConfigCatalog.serverModeKey] ?? "").isEmpty else { return nil }
        return (config[ConfigCatalog.serverURLKey] ?? "").isEmpty ? "builtin" : "local"
    }
}

/// Watches the user's own whisper server. Once it stays unreachable for `grace`
/// the built-in engine covers dictation, and when it answers again dictation goes
/// back to it. The saved setting never changes.
public struct ExternalServerWatch {
    public static let grace: TimeInterval = 15
    public private(set) var covering = false
    private var downSince: Date?

    public init() {}

    /// Record one health probe. Returns true when `covering` flipped.
    public mutating func observe(ready: Bool, at now: Date) -> Bool {
        if ready {
            downSince = nil
            guard covering else { return false }
            covering = false
            return true
        }
        let since = downSince ?? now
        downSince = since
        guard !covering, now.timeIntervalSince(since) >= Self.grace else { return false }
        covering = true
        return true
    }

    public mutating func reset() {
        downSince = nil
        covering = false
    }
}

/// Where the built-in engine listens, or why it can't take dictation yet. Its port
/// changes on every launch, so it never goes in the database.
public struct SpeechEndpoint: Equatable {
    public let url: String?
    public let unavailable: String?

    /// What dictation reports while `url` is nil.
    var notReadyMessage: String { unavailable ?? "The speech engine is not ready yet." }
}
