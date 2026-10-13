import Foundation

/// Filesystem location of the app-data folder that holds the SQLite database and
/// the transcription log tree. Defaults to a portable per-user location
/// (`~/Library/Application Support/VerbVox/`) so the app compiles and runs on any
/// Mac with no external dependencies — the DB self-creates there on first launch.
/// The root is overridable (persisted in UserDefaults) via "Change backend
/// folder…", e.g. to point at a shared DB on another volume. The app runs no
/// Python; whisper runs in the bundled engine or on the user's own server.
public struct BackendPaths: Equatable {
    public var root: URL
    public var python: String

    public init(root: URL, python: String) {
        self.root = root
        self.python = python
    }

    /// `~/Library/Application Support/VerbVox/` — always exists or is creatable on
    /// any Mac, so a fresh install self-initializes an empty DB with no setup.
    public static let defaultRoot: URL = {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("VerbVox", isDirectory: true)
    }()
    public static let defaultPython =
        "/Library/Frameworks/Python.framework/Versions/3.12/bin/python3"

    public var dbPath: String { root.appendingPathComponent("transcribe_app.db").path }
    public var logsDir: URL { root.appendingPathComponent("logs") }

    /// Create the data folder (and its `logs/` subtree) if missing, so `sqlite3_open`
    /// can create the DB file on a fresh machine. Safe to call repeatedly.
    public func ensureRootExists() {
        let fm = FileManager.default
        try? fm.createDirectory(at: root, withIntermediateDirectories: true)
        try? fm.createDirectory(at: logsDir, withIntermediateDirectories: true)
    }

    private static let rootKey = "backendRoot"
    private static let pythonKey = "backendPython"
    private static let modelsKey = "modelsDir"

    /// Built-in engine models. They stay in the default data folder even when the
    /// backend folder moves, so they download once. `-modelsDir <path>` at launch
    /// (or the `modelsDir` default) points elsewhere.
    public static func modelsDir(_ defaults: UserDefaults = .standard) -> URL {
        defaults.string(forKey: modelsKey).map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? defaultRoot.appendingPathComponent("models", isDirectory: true)
    }

    public static func load(_ defaults: UserDefaults = .standard) -> BackendPaths {
        let root = defaults.string(forKey: rootKey).map { URL(fileURLWithPath: $0) } ?? defaultRoot
        let python = defaults.string(forKey: pythonKey) ?? defaultPython
        return BackendPaths(root: root, python: python)
    }

    public func save(_ defaults: UserDefaults = .standard) {
        defaults.set(root.path, forKey: Self.rootKey)
        defaults.set(python, forKey: Self.pythonKey)
    }
}
