import Foundation

/// Gemini AI-cleanup provider (Python `call_gemini`). POSTs to
/// `.../models/{model}:generateContent?key=` with the user prompt in
/// `contents[].parts[].text`; the caller's system message is carried in
/// `systemInstruction` so it is not lost (Python only ever passed a user prompt).
/// Reply read from `candidates[0].content.parts[0].text`, wrapping quotes stripped.
public struct GeminiAI: AIProvider {
    let apiKey: String
    let model: String
    let session: URLSession

    public init(apiKey: String, model: String, session: URLSession = .shared) {
        self.apiKey = apiKey
        self.model = model
        self.session = session
    }

    public func complete(system: String, user: String, temperature: Double, maxTokens: Int) async throws -> String {
        guard let endpoint = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent?key=\(apiKey)") else {
            throw ProviderError.decode("invalid gemini url")
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var payload: [String: Any] = [
            "contents": [["parts": [["text": user]]]],
            "generationConfig": [
                "temperature": temperature,
                "maxOutputTokens": maxTokens,
            ],
        ]
        if !system.isEmpty {
            payload["systemInstruction"] = ["parts": [["text": system]]]
        }
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
            let candidates = object["candidates"] as? [[String: Any]],
            let content = candidates.first?["content"] as? [String: Any],
            let parts = content["parts"] as? [[String: Any]],
            let text = parts.first?["text"] as? String
        else {
            throw ProviderError.decode("unexpected generateContent response")
        }
        return stripWrappingQuotes(text.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
