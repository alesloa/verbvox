import Foundation

/// Port of `get_ai_prompt` (transcribe_cli.py). Builds the final AI prompt for
/// a given context by looking up a named template and substituting placeholders.
///
/// The template lookup (Python's `db_helpers.get_prompt`) is injected as a
/// closure so the builder needs neither a database nor a network.
public struct PromptBuilder {

    /// Maps a prompt name → its template text (nil/empty ⇒ not found).
    private let template: (String) -> String?

    public init(_ template: @escaping (String) -> String?) {
        self.template = template
    }

    public func build(text: String, context: DictationContext) -> String {
        var text = text

        // For AI questions, strip out the trigger phrase.
        if case let .aiQuestion(trigger) = context {
            text = text.replacingOccurrences(of: trigger, with: "", options: [.caseInsensitive])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            text = stripLeadingCommasAndSpaces(text)
        }

        // Determine which prompt to use.
        let promptName: String
        if case let .translate(language) = context, language.lowercased() == "spanish" {
            promptName = "translate_to_spanish"
        } else {
            promptName = name(for: context)
        }

        // Missing (nil) or empty template → hardcoded default with text already
        // interpolated (no further placeholder substitution, mirroring Python).
        guard let found = template(promptName), !found.isEmpty else {
            return defaultPrompt(text: text)
        }

        var result = found
        // For translation, replace the target-language placeholder.
        if case let .translate(language) = context {
            result = result.replacingOccurrences(of: "{target_language}", with: language)
        }
        return result.replacingOccurrences(of: "{text}", with: text)
    }

    // MARK: - Helpers

    private func name(for context: DictationContext) -> String {
        switch context {
        case .default: return "default"
        case .codePrompt: return "code_prompt"
        case .formalChat: return "formal_chat"
        case .aiQuestion: return "ai_question"
        case .translate: return "translate"
        }
    }

    /// Python: re.sub(r'^[,\s]+', '', text)
    private func stripLeadingCommasAndSpaces(_ s: String) -> String {
        var r = Substring(s)
        while let f = r.first, f == "," || f.isWhitespace { r = r.dropFirst() }
        return String(r)
    }

    private func defaultPrompt(text: String) -> String {
        """
        Clean up this text. Remove filler words and pauses, fix grammar:

        "\(text)"

        Return only the cleaned text, no explanations.
        """
    }
}
