import Foundation

/// Client for the OpenAI-compatible `/chat/completions` endpoint. Shared by the
/// Groq and OpenAI AI providers (identical wire format) — a faithful port of
/// Python `call_groq`: `[system, user]` messages, `temperature`, `max_tokens`,
/// reply read from `choices[0].message.content` with wrapping quotes stripped.
struct OpenAICompatChat {
    let endpoint: URL
    let apiKey: String
    let model: String
    let session: URLSession

    init(endpoint: URL, apiKey: String, model: String, session: URLSession = .shared) {
        self.endpoint = endpoint
        self.apiKey = apiKey
        self.model = model
        self.session = session
    }

    func complete(system: String, user: String, temperature: Double, maxTokens: Int) async throws -> String {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": user],
            ],
            "temperature": temperature,
            "max_tokens": maxTokens,
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ProviderError.http(-1, "no HTTP response")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw ProviderError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        guard
            let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let choices = object["choices"] as? [[String: Any]],
            let message = choices.first?["message"] as? [String: Any],
            let content = message["content"] as? String
        else {
            throw ProviderError.decode("unexpected chat completion response")
        }
        return stripWrappingQuotes(content.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

/// Remove one pair of wrapping double quotes if present, matching Python's
/// `if cleaned.startswith('"') and cleaned.endswith('"'): cleaned = cleaned[1:-1]`.
func stripWrappingQuotes(_ text: String) -> String {
    if text.hasPrefix("\"") && text.hasSuffix("\"") {
        return String(text.dropFirst().dropLast())
    }
    return text
}
