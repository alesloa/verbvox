import Foundation

/// Port of `clean_transcription` (transcribe_cli.py). Collapses whitespace,
/// rewrites Whisper's " . [Capital]" into ", [lowercase]", strips filler
/// words, and normalizes spacing after punctuation.
public enum TranscriptCleaner {

    /// Filler/hesitation sounds removed as whole words (case-insensitive).
    private static let fillers = ["uh", "um", "uhm", "er", "ah", "mm", "hmm", "uhh", "umm"]

    public static func clean(_ text: String) -> String {
        // Python: ' '.join(text.split()) — collapse every whitespace run to one space.
        var result = collapseWhitespace(text)

        // Python: re.sub(r'\s+\.\s+([A-Z])', lambda m: ', ' + m.group(1).lower(), text)
        result = fixDotBeforeCapital(result)

        // Remove hesitation/filler sounds (case-insensitive, word boundaries).
        for filler in fillers {
            result = replaceAll(#"\b"# + filler + #"\b"#, in: result, with: "", caseInsensitive: true)
        }

        // Clean up any resulting multiple spaces.
        result = collapseWhitespace(result)

        // Ensure single space after common punctuation (no-op after the collapse
        // above, but kept to mirror the Python 1:1).
        result = result.replacingOccurrences(of: ".  ", with: ". ")
        result = result.replacingOccurrences(of: ",  ", with: ", ")
        result = result.replacingOccurrences(of: "?  ", with: "? ")
        result = result.replacingOccurrences(of: "!  ", with: "! ")

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Every horizontal space character a transcript or an AI reply can carry:
    /// plain space, tab, no-break space, the Unicode fixed-width spaces. Line
    /// terminators are deliberately absent so paragraphs survive.
    private static let horizontalSpace = #"[ \t\u00A0\u1680\u2000-\u200A\u202F\u205F\u3000]"#

    /// Collapses a run of two or more horizontal spaces that follows visible text
    /// down to a single plain space, however long the run is. Newlines and
    /// line-leading indentation are left alone, so pasted code keeps its shape.
    ///
    /// Applied to the final text just before it is pasted/typed: a dictionary or
    /// profanity entry with a blank replacement deletes its word and leaves the
    /// surrounding spaces behind, and AI cleanup can return double spaces too.
    public static func collapseInlineSpaces(_ text: String) -> String {
        replaceAll(#"(?<=\S)"# + horizontalSpace + #"{2,}"#, in: text, with: " ", caseInsensitive: false)
    }

    // MARK: - Helpers

    private static func collapseWhitespace(_ text: String) -> String {
        text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    private static func fixDotBeforeCapital(_ text: String) -> String {
        guard let re = try? NSRegularExpression(pattern: #"\s+\.\s+([A-Z])"#) else { return text }
        let ns = text as NSString
        let matches = re.matches(in: text, range: NSRange(location: 0, length: ns.length))
        guard !matches.isEmpty else { return text }
        let out = NSMutableString(string: text)
        // Replace back-to-front so earlier ranges stay valid.
        for m in matches.reversed() {
            let capital = ns.substring(with: m.range(at: 1)).lowercased()
            out.replaceCharacters(in: m.range, with: ", " + capital)
        }
        return out as String
    }

    private static func replaceAll(_ pattern: String, in text: String, with template: String, caseInsensitive: Bool) -> String {
        let opts: NSRegularExpression.Options = caseInsensitive ? [.caseInsensitive] : []
        guard let re = try? NSRegularExpression(pattern: pattern, options: opts) else { return text }
        let range = NSRange(location: 0, length: (text as NSString).length)
        return re.stringByReplacingMatches(in: text, range: range, withTemplate: template)
    }
}
