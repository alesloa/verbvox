import Foundation

/// Port of `ai_cleanup_text` (transcribe_cli.py) as a composition over the
/// pipeline pieces: detect context → min-words gate → build prompt → call the
/// injected `AIProvider`. On any provider error it falls back to the original
/// text, matching the Python (where `call_groq`/`call_gemini` swallow errors).
public struct AICleanup {

    // Fixed request parameters from `call_groq()` in transcribe_cli.py.
    private static let systemPrompt = "You are a helpful AI assistant. Follow instructions exactly."
    private static let temperature = 0.3
    private static let maxTokens = 2000

    private let provider: AIProvider
    private let promptBuilder: PromptBuilder
    private let minWords: Int
    private let contextEnabled: Bool
    private let translationEnabled: Bool

    public init(provider: AIProvider,
                promptBuilder: PromptBuilder,
                minWords: Int,
                contextEnabled: Bool,
                translationEnabled: Bool) {
        self.provider = provider
        self.promptBuilder = promptBuilder
        self.minWords = minWords
        self.contextEnabled = contextEnabled
        self.translationEnabled = translationEnabled
    }

    public func run(text: String, app: String?) async throws -> String {
        // Detect context first.
        let context = ContextDetector.detect(text, app: app,
                                              translationEnabled: translationEnabled,
                                              contextEnabled: contextEnabled)

        // Skip AI for short text UNLESS it's an AI question or translation.
        let wordCount = text.split(whereSeparator: { $0.isWhitespace }).count
        if wordCount <= minWords && !isAIQuestionOrTranslate(context) {
            return text
        }

        let prompt = promptBuilder.build(text: text, context: context)

        do {
            return try await provider.complete(system: Self.systemPrompt,
                                               user: prompt,
                                               temperature: Self.temperature,
                                               maxTokens: Self.maxTokens)
        } catch {
            // Return original text on error (Python fallback behavior).
            return text
        }
    }

    private func isAIQuestionOrTranslate(_ context: DictationContext) -> Bool {
        switch context {
        case .aiQuestion, .translate: return true
        default: return false
        }
    }
}
