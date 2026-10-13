import Foundation

/// Port of `detect_context` (transcribe_cli.py). Derives a `DictationContext`
/// from the transcription text and the frontmost app name, honoring the same
/// precedence order and trigger lists as the Python.
public enum ContextDetector {

    /// Wake words that mark an AI-assistant question (matched only at the start).
    private static let aiTriggers = [
        "hey gemini", "hey claude", "hey chatgpt", "hey gpt", "hey ai",
        "hey cloud", "hey flow", "hey flo", "hey flux",
    ]

    private static let codeEditors = [
        "Visual Studio Code", "Cursor", "Zed", "Sublime Text", "Code", "Xcode", "Terminal",
    ]

    private static let chatApps = [
        "WhatsApp", "Slack", "Discord", "Messages", "Telegram",
        "Teams", "Signal", "Messenger", "Facebook Messenger",
        "iMessage", "WeChat", "Line", "Viber", "Skype",
        "GroupMe", "Snapchat", "Instagram",
    ]

    /// - Parameters:
    ///   - text: transcribed text.
    ///   - app: frontmost app's localized name (may be nil).
    ///   - translationEnabled: the `enable_translation` feature flag.
    ///   - contextEnabled: the `enable_context_detection` feature flag.
    public static func detect(_ text: String, app: String?,
                              translationEnabled: Bool, contextEnabled: Bool) -> DictationContext {
        guard contextEnabled else { return .default }

        let textLower = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        // AI assistant question detection (only at start of text).
        for trigger in aiTriggers where textLower.hasPrefix(trigger) {
            var remaining = String(textLower.dropFirst(trigger.count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            remaining = lstripCommas(remaining).trimmingCharacters(in: .whitespacesAndNewlines)

            // Is the trigger followed by a translation command?
            if remaining.contains("translate")
                && (remaining.contains("to spanish") || remaining.contains("to english") || remaining.contains("in spanish")) {
                if remaining.contains("spanish") {
                    return .translate(language: "spanish")
                } else if remaining.contains("english") {
                    return .translate(language: "english")
                }
            }
            if remaining.hasPrefix("translate this") || remaining.hasPrefix("translate to ") {
                if let lang = firstGroup(#"translate (?:this )?to (\w+)"#, in: remaining) {
                    return .translate(language: lang)
                }
                return .translate(language: "english")
            }
            // Otherwise, it's an AI question.
            return .aiQuestion(trigger: trigger)
        }

        // Translation command detection (without wake word).
        if translationEnabled {
            if textLower.hasPrefix("translate this") || textLower.hasPrefix("translate that")
                || textLower.hasPrefix("translate to ") || textLower.hasPrefix("say this in ")
                || textLower.hasPrefix("say that in ") {
                if let lang = firstGroup(#"(?:translate (?:this|that) ?to|say (?:this|that) in) (\w+)"#, in: textLower) {
                    return .translate(language: lang)
                }
                return .translate(language: "english")
            }
        }

        // Code editor detection.
        if let app = app, codeEditors.contains(where: { app.contains($0) }) {
            return .codePrompt
        }

        // Chat/messaging apps detection (casual grammar fix).
        if let app = app, chatApps.contains(where: { app.contains($0) }) {
            return .formalChat
        }

        return .default
    }

    // MARK: - Helpers

    private static func lstripCommas(_ s: String) -> String {
        var r = Substring(s)
        while r.first == "," { r = r.dropFirst() }
        return String(r)
    }

    /// Anchored first-capture-group match, mirroring Python's `re.match`.
    private static func firstGroup(_ pattern: String, in text: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = text as NSString
        guard let m = re.firstMatch(in: text, options: [.anchored],
                                    range: NSRange(location: 0, length: ns.length)),
              m.numberOfRanges > 1,
              m.range(at: 1).location != NSNotFound else { return nil }
        return ns.substring(with: m.range(at: 1))
    }
}
