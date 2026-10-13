import Foundation
import AVFoundation

/// Deepgram cloud TTS (`/v1/speak`). POSTs `{"text": …}` with `Token` auth and
/// plays the returned audio via `AVAudioPlayer`. The HTTP part is isolated in
/// `synthesize` so it can be request-shape tested without playback.
public final class DeepgramTTS: TTSProvider {
    let apiKey: String
    let model: String
    let session: URLSession
    private var player: AVAudioPlayer?

    public init(apiKey: String, model: String, session: URLSession = .shared) {
        self.apiKey = apiKey
        self.model = model
        self.session = session
    }

    /// Request the synthesized audio bytes. Testable network path.
    func synthesize(_ text: String) async throws -> Data {
        guard let endpoint = URL(string: "https://api.deepgram.com/v1/speak?model=\(model)") else {
            throw ProviderError.decode("invalid deepgram url")
        }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Token \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["text": text])

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ProviderError.http(-1, "no HTTP response")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw ProviderError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        return data
    }

    public func speak(_ text: String, wpm: Int, voice: String?) async throws {
        let audio = try await synthesize(text)
        let player = try AVAudioPlayer(data: audio)
        self.player = player
        player.play()
    }

    public func stop() {
        player?.stop()
    }
}
