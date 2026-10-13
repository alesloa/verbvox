import Foundation

/// Port of `log_transcription` (transcribe_cli.py). Appends each transcription to
/// a date-prefixed, per-app log file — `<logsDir>/YYYY-MM/DD-App.log` — which the
/// GUI's History tab reads back through `LogReader`. Gated on `logging.enable_logging`.
///
/// The log directory is injected (Phase 6 passes `paths.logsDir`, i.e. the backend
/// `logs/` folder the Python engine wrote to) rather than assuming a CWD.
public struct TranscriptionLogger {

    /// Resolved `logging.*` config the writer needs.
    public struct Options {
        public let enabled: Bool          // logging.enable_logging
        public let logOriginalText: Bool  // logging.log_original_text
        public let format: String         // logging.log_format: "simple" | "detailed"

        public init(enabled: Bool, logOriginalText: Bool, format: String) {
            self.enabled = enabled
            self.logOriginalText = logOriginalText
            self.format = format
        }
    }

    private let logsDir: URL
    private let options: Options

    public init(logsDir: URL, options: Options) {
        self.logsDir = logsDir
        self.options = options
    }

    /// Append one entry. No-op when logging is disabled (Python returned early).
    public func log(original: String, cleaned: String, app: String?, context: String) {
        guard options.enabled else { return }

        let now = Date()
        let yearMonth = Self.format(now, "yyyy-MM") // e.g. "2025-11"
        let day = Self.format(now, "dd")            // e.g. "02"
        let timestamp = Self.format(now, "yyyy-MM-dd HH:mm:ss")

        let monthDir = logsDir.appendingPathComponent(yearMonth)
        try? FileManager.default.createDirectory(at: monthDir, withIntermediateDirectories: true)

        let appName = app ?? "Unknown"
        let safeAppName = Self.sanitize(appName)
        let logFile = monthDir.appendingPathComponent("\(day)-\(safeAppName).log")

        // Which text to persist (Python `log_original_text` toggle).
        let textToLog = options.logOriginalText ? original : cleaned

        let entry: String
        if options.format == "simple" {
            entry = "\(timestamp)||\(textToLog)\n"
        } else { // detailed
            if context.hasPrefix("translate_to_") {
                let rule = String(repeating: "=", count: 80)
                entry = "\(timestamp)||\(appName)||\(context)\n"
                    + "SELECTED TEXT: \(original)\n"
                    + "AI TRANSLATION: \(cleaned)\n"
                    + "\(rule)\n"
            } else {
                entry = "\(timestamp)||\(appName)||\(context)||\(original)||\(cleaned)\n"
            }
        }

        append(entry, to: logFile)
    }

    // MARK: - Helpers

    private func append(_ text: String, to url: URL) {
        let data = Data(text.utf8)
        if FileManager.default.fileExists(atPath: url.path) {
            guard let handle = try? FileHandle(forWritingTo: url) else { return }
            defer { try? handle.close() }
            handle.seekToEndOfFile()
            handle.write(data)
        } else {
            try? data.write(to: url)
        }
    }

    /// Python: keep alphanumerics + space/dash/underscore, replace the rest with
    /// `_`, then collapse spaces to `_`.
    private static func sanitize(_ name: String) -> String {
        let mapped = name.map { ch -> Character in
            (ch.isLetter || ch.isNumber || ch == " " || ch == "-" || ch == "_") ? ch : "_"
        }
        return String(mapped).replacingOccurrences(of: " ", with: "_")
    }

    private static func format(_ date: Date, _ pattern: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = pattern
        return formatter.string(from: date)
    }
}
