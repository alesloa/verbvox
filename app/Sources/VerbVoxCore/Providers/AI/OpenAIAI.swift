import Foundation

/// OpenAI AI-cleanup provider. Same OpenAI-compatible chat wire format as Groq,
/// pointed at `api.openai.com/v1/chat/completions`.
public struct OpenAIAI: AIProvider {
    private let chat: OpenAICompatChat

    public init(apiKey: String, model: String, session: URLSession = .shared) {
        chat = OpenAICompatChat(
            endpoint: URL(string: "https://api.openai.com/v1/chat/completions")!,
            apiKey: apiKey, model: model, session: session)
    }

    public func complete(system: String, user: String, temperature: Double, maxTokens: Int) async throws -> String {
        try await chat.complete(system: system, user: user, temperature: temperature, maxTokens: maxTokens)
    }
}
