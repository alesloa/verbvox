import Foundation

/// Port of `filter_profanity` (transcribe_cli.py). Replaces profanity
/// longest-match-first, on whole words, case-insensitive — then trims the
/// result (the trailing `.strip()` the dictionary path omits).
public enum ProfanityFilter {

    /// - Parameters:
    ///   - text: text to filter.
    ///   - map: word → replacement entries (injected from the DB by the caller).
    public static func apply(_ text: String, map: [String: String]) -> String {
        PhraseReplacer.apply(text, map: map).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
