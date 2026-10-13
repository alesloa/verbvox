import Foundation

/// One transcription line read from the engine's per-app log files
/// (`logs/YYYY-MM/DD-AppName.log`, line format `TIMESTAMP||...||TEXT`).
public struct LogEntry: Identifiable, Equatable {
    public let id = UUID()
    public let timestamp: String
    public let app: String
    public let text: String

    public init(timestamp: String, app: String, text: String) {
        self.timestamp = timestamp
        self.app = app
        self.text = text
    }

    public static func == (l: LogEntry, r: LogEntry) -> Bool {
        l.timestamp == r.timestamp && l.app == r.app && l.text == r.text
    }
}

public enum LogReader {

    /// Parse one log line. Simple format is `TIMESTAMP||TEXT`; detailed format is
    /// `TIMESTAMP||app||context||original||cleaned`. The transcription text is the
    /// last `||`-separated field. Returns nil for malformed/blank lines.
    public static func parseLine(_ line: String, app: String) -> LogEntry? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let parts = trimmed.components(separatedBy: "||")
        guard parts.count >= 2 else { return nil }
        let timestamp = parts[0].trimmingCharacters(in: .whitespaces)
        let text = parts[parts.count - 1].trimmingCharacters(in: .whitespaces)
        guard !timestamp.isEmpty, !text.isEmpty else { return nil }
        return LogEntry(timestamp: timestamp, app: app, text: text)
    }

    /// Recover a display app name from a log filename like `23-Code_-_Insiders.log`
    /// → `Code - Insiders` (day prefix dropped, `_` restored to spaces).
    public static func appName(fromFileName name: String) -> String {
        var n = name
        if n.hasSuffix(".log") { n = String(n.dropLast(4)) }
        if let dash = n.firstIndex(of: "-") {
            n = String(n[n.index(after: dash)...])
        }
        return n.replacingOccurrences(of: "_", with: " ")
    }

    /// Return the last `maxBytes` of a log file as text (empty if missing).
    public static func tail(of path: String, maxBytes: Int) -> String {
        guard let data = FileManager.default.contents(atPath: path) else { return "" }
        let slice = data.count > maxBytes ? data.suffix(maxBytes) : data
        return String(decoding: slice, as: UTF8.self)
    }

    /// Read the most recent transcription entries across all per-app log files.
    public static func recentEntries(in logsDir: URL, limit: Int = 50) -> [LogEntry] {
        let fm = FileManager.default
        guard let monthDirs = try? fm.contentsOfDirectory(
            at: logsDir, includingPropertiesForKeys: [.contentModificationDateKey]) else { return [] }

        var files: [URL] = []
        for month in monthDirs {
            let logs = (try? fm.contentsOfDirectory(
                at: month, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
            files.append(contentsOf: logs.filter { $0.pathExtension == "log" })
        }
        // Newest files first by modification date.
        files.sort {
            let a = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            let b = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            return a > b
        }

        var entries: [LogEntry] = []
        for file in files {
            let app = appName(fromFileName: file.lastPathComponent)
            guard let contents = try? String(contentsOf: file, encoding: .utf8) else { continue }
            for line in contents.split(separator: "\n", omittingEmptySubsequences: true).reversed() {
                if let e = parseLine(String(line), app: app) { entries.append(e) }
                if entries.count >= limit { break }
            }
            if entries.count >= limit { break }
        }
        // Sort by timestamp string (ISO-like, lexicographically sortable) descending.
        return Array(entries.sorted { $0.timestamp > $1.timestamp }.prefix(limit))
    }
}
