import Foundation

public struct DictionaryEntry: Identifiable, Equatable, Hashable {
    public let id: Int64
    public var category: String
    public var from: String
    public var to: String

    public init(id: Int64, category: String, from: String, to: String) {
        self.id = id
        self.category = category
        self.from = from
        self.to = to
    }
}

public struct ProfanityEntry: Identifiable, Equatable, Hashable {
    public let id: Int64
    public var word: String
    public var replacement: String

    public init(id: Int64, word: String, replacement: String) {
        self.id = id
        self.word = word
        self.replacement = replacement
    }
}

public struct Prompt: Identifiable, Equatable, Hashable {
    public var name: String
    public var text: String
    public var id: String { name }

    public init(name: String, text: String) {
        self.name = name
        self.text = text
    }
}

public struct Stat: Identifiable {
    public let id = UUID()
    public let timestamp: Double
    public let words: Int
    public let time: Double
    public let wpm: Double
    public let mode: String

    public init(timestamp: Double, words: Int, time: Double, wpm: Double, mode: String) {
        self.timestamp = timestamp
        self.words = words
        self.time = time
        self.wpm = wpm
        self.mode = mode
    }
}

public struct StatsSummary: Equatable {
    public var totalCount: Int
    public var avgWPM: Double
    public var maxWPM: Double
    public var minWPM: Double
    public var totalWords: Int
    public var totalTime: Double

    public static let empty = StatsSummary(
        totalCount: 0, avgWPM: 0, maxWPM: 0, minWPM: 0, totalWords: 0, totalTime: 0)
}

public struct DayCount: Equatable, Identifiable {
    public var day: String   // "YYYY-MM-DD" (local)
    public var words: Int
    public var count: Int
    public var id: String { day }
}
