import Foundation

/// Default AI-cleanup provider. Wraps the shared OpenAI-compatible chat client
/// pointed at Groq's `/chat/completions` endpoint (Python `call_groq`).
public struct GroqAI: AIProvider {
    private let chat: OpenAICompatChat

    public init(apiKey: String, model: String, session: URLSession = .shared) {
        chat = OpenAICompatChat(
            endpoint: URL(string: "https://api.groq.com/openai/v1/chat/completions")!,
            apiKey: apiKey, model: model, session: session)
    }

    public func complete(system: String, user: String, temperature: Double, maxTokens: Int) async throws -> String {
        try await chat.complete(system: system, user: user, temperature: temperature, maxTokens: maxTokens)
    }
}
