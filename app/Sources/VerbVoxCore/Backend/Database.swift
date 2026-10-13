import Foundation

/// Typed access to `transcribe_app.db`. Mirrors `db_helpers.py` so the Swift GUI
/// and the Python engine read/write the same tables compatibly.
public final class Database {
    let db: SQLiteDB

    public init(path: String) throws {
        db = try SQLiteDB(path: path)
        try ensureSchema()
    }

    /// Create tables/indexes if missing. Matches `init_database.py`. No-op on the
    /// real DB (everything already exists); used for fresh locations and tests.
    func ensureSchema() throws {
        try db.execute(Self.schemaSQL)
    }

    // MARK: Config

    public func allConfig() throws -> [String: String] {
        var out: [String: String] = [:]
        for row in try db.query("SELECT key, value FROM config") {
            if let k = row[0].stringValue { out[k] = row[1].stringValue ?? "" }
        }
        return out
    }

    public func configValue(_ key: String) throws -> String? {
        let rows = try db.query("SELECT value FROM config WHERE key = ?", [.text(key)])
        return rows.first?[0].stringValue
    }

    public func setConfig(_ key: String, _ value: String, category: String) throws {
        try db.run(
            "INSERT OR REPLACE INTO config (key, value, category) VALUES (?, ?, ?)",
            [.text(key), .text(value), .text(category)])
    }

    // MARK: Dictionary

    public func dictionaryEntries() throws -> [DictionaryEntry] {
        try db.query("""
            SELECT id, category, from_word, to_word
            FROM dictionary_entries ORDER BY category, from_word
            """).map {
            DictionaryEntry(
                id: $0[0].intValue ?? 0,
                category: $0[1].stringValue ?? "",
                from: $0[2].stringValue ?? "",
                to: $0[3].stringValue ?? "")
        }
    }

    @discardableResult
    public func addDictionaryEntry(category: String, from: String, to: String) throws -> Int64 {
        try db.run(
            "INSERT INTO dictionary_entries (category, from_word, to_word) VALUES (?, ?, ?)",
            [.text(category), .text(from), .text(to)])
    }

    public func updateDictionaryEntry(id: Int64, category: String, from: String, to: String) throws {
        try db.run(
            "UPDATE dictionary_entries SET category = ?, from_word = ?, to_word = ? WHERE id = ?",
            [.text(category), .text(from), .text(to), .int(id)])
    }

    public func deleteDictionaryEntry(id: Int64) throws {
        try db.run("DELETE FROM dictionary_entries WHERE id = ?", [.int(id)])
    }

    public func dictionaryCategories() throws -> [String] {
        try db.query("SELECT DISTINCT category FROM dictionary_entries ORDER BY category")
            .compactMap { $0[0].stringValue }
    }

    /// `from` → `to` lookup for the dictionary corrector. First entry wins on
    /// duplicate `from` words (mirrors the Python engine's dict build order).
    public func dictionaryMap() throws -> [String: String] {
        Dictionary(try dictionaryEntries().map { ($0.from, $0.to) }, uniquingKeysWith: { a, _ in a })
    }

    // MARK: Profanity

    public func profanityFilters() throws -> [ProfanityEntry] {
        try db.query("SELECT id, word, replacement FROM profanity_filters ORDER BY word").map {
            ProfanityEntry(
                id: $0[0].intValue ?? 0,
                word: $0[1].stringValue ?? "",
                replacement: $0[2].stringValue ?? "")
        }
    }

    @discardableResult
    public func addProfanity(word: String, replacement: String) throws -> Int64 {
        try db.run(
            "INSERT INTO profanity_filters (word, replacement) VALUES (?, ?)",
            [.text(word), .text(replacement)])
    }

    public func updateProfanity(id: Int64, word: String, replacement: String) throws {
        try db.run(
            "UPDATE profanity_filters SET word = ?, replacement = ? WHERE id = ?",
            [.text(word), .text(replacement), .int(id)])
    }

    public func deleteProfanity(id: Int64) throws {
        try db.run("DELETE FROM profanity_filters WHERE id = ?", [.int(id)])
    }

    /// `word` → `replacement` lookup for the profanity filter. First entry wins
    /// on duplicate words.
    public func profanityMap() throws -> [String: String] {
        Dictionary(try profanityFilters().map { ($0.word, $0.replacement) }, uniquingKeysWith: { a, _ in a })
    }

    // MARK: Prompts

    public func prompts() throws -> [Prompt] {
        try db.query("SELECT name, text FROM prompts ORDER BY name").map {
            Prompt(name: $0[0].stringValue ?? "", text: $0[1].stringValue ?? "")
        }
    }

    public func prompt(named name: String) throws -> String? {
        try db.query("SELECT text FROM prompts WHERE name = ?", [.text(name)]).first?[0].stringValue
    }

    public func setPrompt(name: String, text: String) throws {
        try db.run(
            "INSERT OR REPLACE INTO prompts (name, text) VALUES (?, ?)",
            [.text(name), .text(text)])
    }

    public func deletePrompt(name: String) throws {
        try db.run("DELETE FROM prompts WHERE name = ?", [.text(name)])
    }

    // MARK: Stats

    /// Record one dictation result. Stats live in the `transcriptions` table
    /// (there is no separate `stats` table); `seconds` maps to the `time` column.
    public func addTranscriptionStat(timestamp: Double, words: Int, seconds: Double, wpm: Double, mode: String) throws {
        try db.run(
            "INSERT INTO transcriptions (timestamp, words, time, wpm, mode) VALUES (?, ?, ?, ?, ?)",
            [.double(timestamp), .int(Int64(words)), .double(seconds), .double(wpm), .text(mode)])
    }

    public func statsSummary() throws -> StatsSummary {
        let rows = try db.query("""
            SELECT COUNT(*), AVG(wpm), MAX(wpm), MIN(wpm), SUM(words), SUM(time)
            FROM transcriptions
            """)
        guard let r = rows.first else { return .empty }
        return StatsSummary(
            totalCount: Int(r[0].intValue ?? 0),
            avgWPM: r[1].doubleValue ?? 0,
            maxWPM: r[2].doubleValue ?? 0,
            minWPM: r[3].doubleValue ?? 0,
            totalWords: Int(r[4].intValue ?? 0),
            totalTime: r[5].doubleValue ?? 0)
    }

    public func recentStats(limit: Int) throws -> [Stat] {
        try db.query("""
            SELECT timestamp, words, time, wpm, mode
            FROM transcriptions ORDER BY timestamp DESC LIMIT ?
            """, [.int(Int64(limit))]).map {
            Stat(
                timestamp: $0[0].doubleValue ?? 0,
                words: Int($0[1].intValue ?? 0),
                time: $0[2].doubleValue ?? 0,
                wpm: $0[3].doubleValue ?? 0,
                mode: $0[4].stringValue ?? "")
        }
    }

    public func dailyWordCounts() throws -> [DayCount] {
        try db.query("""
            SELECT date(timestamp, 'unixepoch', 'localtime') AS day,
                   SUM(words), COUNT(*)
            FROM transcriptions GROUP BY day ORDER BY day
            """).map {
            DayCount(
                day: $0[0].stringValue ?? "",
                words: Int($0[1].intValue ?? 0),
                count: Int($0[2].intValue ?? 0))
        }
    }

    // MARK: Schema

    static let schemaSQL = """
    CREATE TABLE IF NOT EXISTS config (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL,
        category TEXT NOT NULL,
        updated_at REAL DEFAULT (datetime('now'))
    );
    CREATE TABLE IF NOT EXISTS dictionary_entries (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        category TEXT NOT NULL,
        from_word TEXT NOT NULL COLLATE NOCASE,
        to_word TEXT NOT NULL,
        created_at REAL DEFAULT (datetime('now'))
    );
    CREATE INDEX IF NOT EXISTS idx_dictionary_from
        ON dictionary_entries(from_word COLLATE NOCASE);
    CREATE TABLE IF NOT EXISTS profanity_filters (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        word TEXT NOT NULL COLLATE NOCASE,
        replacement TEXT NOT NULL,
        created_at REAL DEFAULT (datetime('now'))
    );
    CREATE INDEX IF NOT EXISTS idx_profanity_word
        ON profanity_filters(word COLLATE NOCASE);
    CREATE TABLE IF NOT EXISTS transcriptions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        timestamp REAL NOT NULL,
        words INTEGER NOT NULL,
        time REAL NOT NULL,
        wpm REAL NOT NULL,
        mode TEXT NOT NULL
    );
    CREATE INDEX IF NOT EXISTS idx_timestamp ON transcriptions(timestamp);
    CREATE TABLE IF NOT EXISTS prompts (
        name TEXT PRIMARY KEY,
        text TEXT NOT NULL,
        updated_at REAL DEFAULT (datetime('now'))
    );
    """
}
