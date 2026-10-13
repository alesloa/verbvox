import XCTest
@testable import VerbVoxCore

final class DatabaseTests: XCTestCase {

    private func makeDB() throws -> (Database, String) {
        let path = NSTemporaryDirectory() + "tts-test-\(UUID().uuidString).db"
        let db = try Database(path: path)
        return (db, path)
    }

    // MARK: Config

    func testConfigSetAndGet() throws {
        let (db, _) = try makeDB()
        try db.setConfig("features.use_cleanup", "True", category: "features")
        XCTAssertEqual(try db.configValue("features.use_cleanup"), "True")
    }

    func testConfigSetOverwrites() throws {
        let (db, _) = try makeDB()
        try db.setConfig("ai_settings.provider", "groq", category: "ai_settings")
        try db.setConfig("ai_settings.provider", "gemini", category: "ai_settings")
        XCTAssertEqual(try db.configValue("ai_settings.provider"), "gemini")
    }

    func testConfigMissingReturnsNil() throws {
        let (db, _) = try makeDB()
        XCTAssertNil(try db.configValue("nope.nope"))
    }

    func testAllConfig() throws {
        let (db, _) = try makeDB()
        try db.setConfig("a.b", "1", category: "x")
        try db.setConfig("c.d", "2", category: "y")
        let all = try db.allConfig()
        XCTAssertEqual(all["a.b"], "1")
        XCTAssertEqual(all["c.d"], "2")
    }

    // MARK: Dictionary

    func testDictionaryAddListUpdateDelete() throws {
        let (db, _) = try makeDB()
        let id = try db.addDictionaryEntry(category: "Tech", from: "vs code", to: "VS Code")
        var entries = try db.dictionaryEntries()
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].from, "vs code")
        XCTAssertEqual(entries[0].to, "VS Code")
        XCTAssertEqual(entries[0].category, "Tech")

        try db.updateDictionaryEntry(id: id, category: "Tech", from: "vs code", to: "Visual Studio Code")
        entries = try db.dictionaryEntries()
        XCTAssertEqual(entries[0].to, "Visual Studio Code")

        try db.deleteDictionaryEntry(id: id)
        XCTAssertTrue(try db.dictionaryEntries().isEmpty)
    }

    func testDictionaryCategoriesDistinctSorted() throws {
        let (db, _) = try makeDB()
        _ = try db.addDictionaryEntry(category: "B", from: "x", to: "X")
        _ = try db.addDictionaryEntry(category: "A", from: "y", to: "Y")
        _ = try db.addDictionaryEntry(category: "A", from: "z", to: "Z")
        XCTAssertEqual(try db.dictionaryCategories(), ["A", "B"])
    }

    // MARK: Profanity

    func testProfanityCRUD() throws {
        let (db, _) = try makeDB()
        let id = try db.addProfanity(word: "darn", replacement: "****")
        var f = try db.profanityFilters()
        XCTAssertEqual(f.count, 1)
        XCTAssertEqual(f[0].word, "darn")
        XCTAssertEqual(f[0].replacement, "****")

        try db.updateProfanity(id: id, word: "darn", replacement: "----")
        f = try db.profanityFilters()
        XCTAssertEqual(f[0].replacement, "----")

        try db.deleteProfanity(id: id)
        XCTAssertTrue(try db.profanityFilters().isEmpty)
    }

    /// A blank replacement means "delete the word", so it has to round-trip.
    func testBlankReplacementsRoundTrip() throws {
        let (db, _) = try makeDB()
        _ = try db.addProfanity(word: "darn", replacement: "")
        _ = try db.addDictionaryEntry(category: "Filler", from: "basically", to: "")
        XCTAssertEqual(try db.profanityMap(), ["darn": ""])
        XCTAssertEqual(try db.dictionaryMap(), ["basically": ""])
    }

    // MARK: Prompts

    func testPromptsSetListGetDelete() throws {
        let (db, _) = try makeDB()
        try db.setPrompt(name: "default", text: "Clean: {text}")
        XCTAssertEqual(try db.prompt(named: "default"), "Clean: {text}")

        try db.setPrompt(name: "default", text: "v2 {text}")  // overwrite
        XCTAssertEqual(try db.prompt(named: "default"), "v2 {text}")

        try db.setPrompt(name: "code", text: "Code {text}")
        XCTAssertEqual(try db.prompts().count, 2)

        try db.deletePrompt(name: "code")
        XCTAssertEqual(try db.prompts().count, 1)
    }

    // MARK: Stats

    private func seedStat(_ raw: SQLiteDB, _ ts: Double, _ words: Int64, _ time: Double, _ wpm: Double, _ mode: String) throws {
        try raw.run(
            "INSERT INTO transcriptions (timestamp,words,time,wpm,mode) VALUES (?,?,?,?,?)",
            [.double(ts), .int(words), .double(time), .double(wpm), .text(mode)])
    }

    func testStatsSummary() throws {
        let (db, path) = try makeDB()
        let raw = try SQLiteDB(path: path)
        try seedStat(raw, 1000, 10, 5, 120, "no_ai")
        try seedStat(raw, 2000, 20, 10, 180, "with_ai")

        let s = try db.statsSummary()
        XCTAssertEqual(s.totalCount, 2)
        XCTAssertEqual(s.totalWords, 30)
        XCTAssertEqual(s.maxWPM, 180, accuracy: 0.001)
        XCTAssertEqual(s.minWPM, 120, accuracy: 0.001)
        XCTAssertEqual(s.avgWPM, 150, accuracy: 0.001)
        XCTAssertEqual(s.totalTime, 15, accuracy: 0.001)
    }

    func testStatsSummaryEmpty() throws {
        let (db, _) = try makeDB()
        let s = try db.statsSummary()
        XCTAssertEqual(s.totalCount, 0)
        XCTAssertEqual(s.totalWords, 0)
        XCTAssertEqual(s.avgWPM, 0, accuracy: 0.001)
    }

    func testRecentStatsLimitAndOrder() throws {
        let (db, path) = try makeDB()
        let raw = try SQLiteDB(path: path)
        for i in 1...5 { try seedStat(raw, Double(i * 100), Int64(i), 1, 100, "no_ai") }
        let recent = try db.recentStats(limit: 3)
        XCTAssertEqual(recent.count, 3)
        XCTAssertEqual(recent[0].timestamp, 500, accuracy: 0.001)  // newest first
    }

    func testDailyWordCountsGroupsByDay() throws {
        let (db, path) = try makeDB()
        let raw = try SQLiteDB(path: path)
        let base = 1_700_000_000.0
        try seedStat(raw, base, 10, 1, 100, "no_ai")           // same day
        try seedStat(raw, base, 20, 1, 100, "no_ai")           // same day
        try seedStat(raw, base + 300_000, 5, 1, 100, "no_ai")  // ~3.5 days later -> new day

        let days = try db.dailyWordCounts()
        XCTAssertEqual(days.count, 2)
        XCTAssertEqual(days.reduce(0) { $0 + $1.words }, 35)
    }

    // MARK: Maps + stat insert (native engine)

    func testDictionaryMapAndStatInsert() throws {
        let db = try Database(path: ":memory:")
        _ = try db.addDictionaryEntry(category: "general", from: "teh", to: "the")
        XCTAssertEqual(try db.dictionaryMap()["teh"], "the")
        _ = try db.addProfanity(word: "darn", replacement: "****")
        XCTAssertEqual(try db.profanityMap()["darn"], "****")
        try db.addTranscriptionStat(timestamp: 1, words: 10, seconds: 5, wpm: 120, mode: "no_ai")
        XCTAssertGreaterThanOrEqual(try db.statsSummary().totalWords, 10)
    }
}
