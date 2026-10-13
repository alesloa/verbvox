import Foundation

/// Port of `save_stats` + the WPM math in `AudioRecorder.stop_recording`
/// (transcribe_cli.py). Records one dictation result to the `transcriptions`
/// stats table via `Database.addTranscriptionStat`.
///
/// The caller gates on `features.show_wpm_stats` (Python only recorded when that
/// flag was on); this type just does the math + insert.
public struct StatsLogger {
    private let db: Database

    public init(db: Database) {
        self.db = db
    }

    /// Compute WPM and persist the stat. Returns the computed WPM.
    ///
    /// Python: `wpm = (word_count / elapsed_time) * 60 if elapsed_time > 0 else 0`,
    /// `word_count = len(text.split())`, `timestamp = time.time()`,
    /// `mode` = the recording mode string (`"no_ai"` / `"with_ai"`).
    @discardableResult
    public func record(words: Int, seconds: Double, mode: String) throws -> Double {
        let wpm = seconds > 0 ? (Double(words) / seconds) * 60.0 : 0
        try db.addTranscriptionStat(
            timestamp: Date().timeIntervalSince1970,
            words: words,
            seconds: seconds,
            wpm: wpm,
            mode: mode)
        return wpm
    }
}
