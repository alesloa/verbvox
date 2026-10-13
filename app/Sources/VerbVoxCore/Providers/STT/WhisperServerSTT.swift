import Foundation

/// Default STT provider: a local/LAN `whisper.cpp` HTTP server. Faithful port of
/// Python `convert_speech_to_text` — POST multipart to `{url}/inference` with the
/// WAV file, `response_format=json` and a `language` field (Python always sent
/// `"auto"`; a caller-supplied language overrides it). No authentication.
public struct WhisperServerSTT: STTProvider {
    let url: String
    let session: URLSession

    public init(url: String, session: URLSession = .shared) {
        self.url = url
        self.session = session
    }

    public func transcribe(wav: Data, language: String?) async throws -> STTResult {
        guard let endpoint = URL(string: "\(url)/inference") else {
            throw ProviderError.decode("invalid whisper server url: \(url)")
        }

        var form = MultipartFormData()
        form.addFile(name: "file", filename: "audio.wav", contentType: "audio/wav", data: wav)
        form.addField(name: "response_format", value: "json")
        form.addField(name: "language", value: language ?? "auto")

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
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
            throw ProviderError.decode("unexpected inference response")
        }
        let text = (object["text"] as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ")
        let detected = object["language"] as? String
        return STTResult(text: text, detectedLanguage: detected)
    }
}
