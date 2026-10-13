import Foundation

/// How an AI-question response should be delivered.
public enum ActionType: Equatable {
    case speak    // informational → read the answer aloud
    case replace  // editing → replace the highlighted text
}

/// Port of `detect_ai_action_type` (transcribe_cli.py). Classifies an AI
/// command as editing (replace) or informational (speak) by substring match,
/// checking the (more specific) editing keywords first.
public enum ActionTypeDetector {

    private static let replaceKeywords = [
        "fix", "correct", "improve", "make better", "make this better",
        "rewrite", "change", "update", "modify", "edit", "refactor",
    ]

    private static let speakKeywords = [
        "what", "explain", "summarize", "tell me", "describe",
        "how does", "what does", "what is", "define", "meaning",
    ]

    public static func detect(_ text: String) -> ActionType {
        let lower = text.lowercased()

        // Editing keywords first (more specific).
        for keyword in replaceKeywords where lower.contains(keyword) {
            return .replace
        }
        for keyword in speakKeywords where lower.contains(keyword) {
            return .speak
        }
        // Default to speak mode for questions.
        return .speak
    }
}
