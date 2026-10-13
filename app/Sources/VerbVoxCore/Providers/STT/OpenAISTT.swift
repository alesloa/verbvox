import Foundation

/// OpenAI cloud STT (`/v1/audio/transcriptions`). Multipart upload of the WAV file
/// plus a `model` field, `Bearer` auth. Response parsed from the JSON `text` field.
public struct OpenAISTT: STTProvider {
    static let endpoint = URL(string: "https://api.openai.com/v1/audio/transcriptions")!

    let apiKey: String
    let model: String
    let session: URLSession

    public init(apiKey: String, model: String, session: URLSession = .shared) {
        self.apiKey = apiKey
        self.model = model
        self.session = session
    }

    public func transcribe(wav: Data, language: String?) async throws -> STTResult {
        var form = MultipartFormData()
        form.addFile(name: "file", filename: "audio.wav", contentType: "audio/wav", data: wav)
        form.addField(name: "model", value: model)
        form.addField(name: "response_format", value: "json")
        if let language { form.addField(name: "language", value: language) }

        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue(form.contentType, forHTTPHeaderField: "Content-Type")
        request.httpBody = form.finished()

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ProviderError.http(-1, "no HTTP response")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw ProviderError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ProviderError.decode("unexpected transcription response")
        }
        let text = (object["text"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return STTResult(text: text, detectedLanguage: object["language"] as? String)
    }
}
