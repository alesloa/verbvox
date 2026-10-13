import Foundation

public struct STTResult {
    public let text: String
    public let detectedLanguage: String?

    public init(text: String, detectedLanguage: String?) {
        self.text = text
        self.detectedLanguage = detectedLanguage
    }
}

public enum ProviderError: Error {
    case http(Int, String)
    case missingKey(String)
    case decode(String)
}

public protocol STTProvider {
    func transcribe(wav: Data, language: String?) async throws -> STTResult
}

public protocol AIProvider {
    func complete(system: String, user: String, temperature: Double, maxTokens: Int) async throws -> String
}

public protocol TTSProvider: AnyObject {
    func speak(_ text: String, wpm: Int, voice: String?) async throws
    func stop()
}
