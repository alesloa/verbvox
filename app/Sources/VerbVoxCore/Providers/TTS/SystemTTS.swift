import Foundation
import AVFoundation

/// Language of a spoken segment, from the `[ES]…[/ES]` markup.
public enum TTSLang: Equatable {
    case english
    case spanish
}

/// Default TTS provider: on-device `AVSpeechSynthesizer`. Faithful port of Python
/// `parse_and_speak` — splits the text into `[ES]…[/ES]` segments, speaking Spanish
/// ones with an `es-*` voice (Python's `get_spanish_system_voice`) and the rest with
/// the system default. Only the pure `parseSegments` splitter is unit-tested.
public final class SystemTTS: TTSProvider {
    private let synthesizer = AVSpeechSynthesizer()

    public init() {}

    /// Split `text` into ordered `(language, segment)` pairs, mirroring
    /// `parse_and_speak`: English runs between/around `[ES]…[/ES]` tags are trimmed
    /// and dropped if empty; Spanish captures are trimmed; when no tags are present
    /// the whole (untrimmed) text is one English segment.
    public static func parseSegments(_ text: String) -> [(TTSLang, String)] {
        var segments: [(TTSLang, String)] = []
        let ns = text as NSString
        let regex = try! NSRegularExpression(pattern: "\\[ES\\](.*?)\\[/ES\\]",
                                             options: [.dotMatchesLineSeparators])
        var lastEnd = 0
        for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            if match.range.location > lastEnd {
                let english = ns
                    .substring(with: NSRange(location: lastEnd, length: match.range.location - lastEnd))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !english.isEmpty { segments.append((.english, english)) }
            }
            let spanish = ns.substring(with: match.range(at: 1))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !spanish.isEmpty { segments.append((.spanish, spanish)) }
            lastEnd = match.range.location + match.range.length
        }
        if lastEnd < ns.length {
            let remaining = ns.substring(from: lastEnd)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !remaining.isEmpty { segments.append((.english, remaining)) }
        }
        if segments.isEmpty {
            segments.append((.english, text))
        }
        return segments
    }

    public func speak(_ text: String, wpm: Int, voice: String?) async throws {
        for (lang, segment) in Self.parseSegments(text) {
            let utterance = AVSpeechUtterance(string: segment)
            utterance.rate = Self.rate(forWPM: wpm)
            if lang == .spanish {
                utterance.voice = Self.spanishVoice()
            } else if let voice, let resolved = Self.englishVoice(voice) {
                utterance.voice = resolved
            }
            synthesizer.speak(utterance)
        }
    }

    public func stop() {
        synthesizer.stopSpeaking(at: .immediate)
    }

    /// Map words-per-minute to `AVSpeechUtterance.rate`. macOS speech synthesis
    /// (the `say` engine, which Python drove directly) speaks at ~175 wpm at its
    /// default rate, which equals `AVSpeechUtteranceDefaultSpeechRate`; scale
    /// linearly from that anchor and clamp to the supported range.
    static func rate(forWPM wpm: Int) -> Float {
        let scaled = AVSpeechUtteranceDefaultSpeechRate * Float(wpm) / 175.0
        return min(max(scaled, AVSpeechUtteranceMinimumSpeechRate), AVSpeechUtteranceMaximumSpeechRate)
    }

    /// First available Spanish system voice (`es-*`), like `get_spanish_system_voice`.
    static func spanishVoice() -> AVSpeechSynthesisVoice? {
        if let voice = AVSpeechSynthesisVoice.speechVoices()
            .first(where: { $0.language.lowercased().hasPrefix("es") }) {
            return voice
        }
        return AVSpeechSynthesisVoice(language: "es-ES")
    }

    /// Resolve an optional English voice preference, accepting either a voice
    /// identifier or a BCP-47 language code.
    private static func englishVoice(_ value: String) -> AVSpeechSynthesisVoice? {
        AVSpeechSynthesisVoice(identifier: value) ?? AVSpeechSynthesisVoice(language: value)
    }
}
