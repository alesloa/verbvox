import Foundation
import AVFoundation

/// OpenAI cloud TTS (`/v1/audio/speech`). POSTs `{model, voice, input}` with
/// `Bearer` auth and plays the returned audio via `AVAudioPlayer`. The HTTP part
/// is isolated in `synthesize` so it can be request-shape tested without playback.
public final class OpenAITTS: TTSProvider {
    static let endpoint = URL(string: "https://api.openai.com/v1/audio/speech")!

    let apiKey: String
    let model: String
    let voice: String
    let session: URLSession
    private var player: AVAudioPlayer?

    public init(apiKey: String, model: String, voice: String, session: URLSession = .shared) {
        self.apiKey = apiKey
        self.model = model
        self.voice = voice
        self.session = session
    }

    /// Request the synthesized audio bytes. Testable network path.
    func synthesize(_ text: String, voice overrideVoice: String?) async throws -> Data {
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let payload: [String: Any] = [
            "model": model,
            "voice": overrideVoice ?? voice,
            "input": text,
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

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
        let audio = try await synthesize(text, voice: voice)
        let player = try AVAudioPlayer(data: audio)
        self.player = player
        player.play()
    }

    public func stop() {
        player?.stop()
    }
}
