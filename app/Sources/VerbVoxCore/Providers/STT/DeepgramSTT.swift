import Foundation

/// Deepgram cloud STT (`/v1/listen`). Unlike the OpenAI-style providers this sends
/// the RAW WAV bytes as the request body (not multipart), with `Token` auth and
/// `detect_language=true`. Transcript read from
/// `results.channels[0].alternatives[0].transcript`.
public struct DeepgramSTT: STTProvider {
    let apiKey: String
    let model: String
    let session: URLSession

    public init(apiKey: String, model: String, session: URLSession = .shared) {
        self.apiKey = apiKey
        self.model = model
        self.session = session
    }

    public func transcribe(wav: Data, language: String?) async throws -> STTResult {
        guard let endpoint = URL(string: "https://api.deepgram.com/v1/listen?model=\(model)&detect_language=true") else {
            throw ProviderError.decode("invalid deepgram url")
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Token \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("audio/wav", forHTTPHeaderField: "Content-Type")
        request.httpBody = wav

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ProviderError.http(-1, "no HTTP response")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw ProviderError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        guard
            let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let results = object["results"] as? [String: Any],
            let channels = results["channels"] as? [[String: Any]],
            let channel = channels.first,
            let alternatives = channel["alternatives"] as? [[String: Any]],
            let transcript = alternatives.first?["transcript"] as? String
        else {
            throw ProviderError.decode("unexpected listen response")
        }
        let detected = channel["detected_language"] as? String
        return STTResult(text: transcript.trimmingCharacters(in: .whitespacesAndNewlines),
                         detectedLanguage: detected)
    }
}
