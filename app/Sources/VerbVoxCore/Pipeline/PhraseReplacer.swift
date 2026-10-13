import Foundation

/// Shared longest-match-first, word-boundary, case-insensitive phrase
/// replacement used by both `DictionaryCorrector` and `ProfanityFilter`.
///
/// Mirrors the Python idiom in `apply_custom_dictionary` / `filter_profanity`:
///   pattern = r'\b' + re.escape(key).replace(r'\ ', r'\s+') + r'\b'
///   text = re.sub(pattern, value, text, flags=re.IGNORECASE)
///
/// Note on the whitespace rule: Python's `re.escape` escapes a space to `\ `,
/// which the `.replace` then turns into `\s+`. Swift's
/// `NSRegularExpression.escapedPattern(for:)` does NOT escape spaces, so here we
/// convert each literal space in the escaped key to `\s+` to reproduce the same
/// "match across any whitespace" behavior.
enum PhraseReplacer {

    static func apply(_ text: String, map: [String: String]) -> String {
        // Longest key first so multi-word phrases win over their sub-words.
        let sorted = map.sorted { $0.key.count > $1.key.count }

        var result = text
        for (key, value) in sorted where !key.isEmpty {
            let escaped = NSRegularExpression.escapedPattern(for: key)
                .replacingOccurrences(of: " ", with: #"\s+"#)
            let pattern = #"\b"# + escaped + #"\b"#
            guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
                continue
            }
            // Insert the replacement verbatim ($ and \ in the value stay literal).
            let template = NSRegularExpression.escapedTemplate(for: value)
            let range = NSRange(location: 0, length: (result as NSString).length)
            result = re.stringByReplacingMatches(in: result, range: range, withTemplate: template)
        }
        return result
    }
}
