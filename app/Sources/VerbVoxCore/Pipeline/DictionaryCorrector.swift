import Foundation

/// Port of `apply_custom_dictionary` (transcribe_cli.py). Applies user
/// dictionary corrections longest-match-first, on whole words, case-insensitive.
/// Unlike the profanity filter, it does NOT trim the result.
public enum DictionaryCorrector {

    /// - Parameters:
    ///   - text: transcription to correct.
    ///   - map: wrong → correct entries (injected from the DB by the caller).
    public static func apply(_ text: String, map: [String: String]) -> String {
        PhraseReplacer.apply(text, map: map)
    }
}
