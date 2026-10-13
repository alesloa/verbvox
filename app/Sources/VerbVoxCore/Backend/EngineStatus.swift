import Foundation

/// The engine's live state, decoded from `/tmp/transcribe_status.json`
/// (written by `transcribe_cli.py write_status`).
public struct EngineStatus: Equatable {
    public enum Phase: String {
        case idle, recording, processing, stopped, unknown
    }

    public var phase: Phase
    public var mode: String
    public var lastTranscription: String
    public var wpm: Double
    public var timestamp: Double

    public init(phase: Phase, mode: String, lastTranscription: String, wpm: Double, timestamp: Double) {
        self.phase = phase
        self.mode = mode
        self.lastTranscription = lastTranscription
        self.wpm = wpm
        self.timestamp = timestamp
    }

    public static let stopped = EngineStatus(
        phase: .stopped, mode: "", lastTranscription: "", wpm: 0, timestamp: 0)

    /// Decode the status JSON. Returns nil on malformed input.
    public static func decode(from data: Data) -> EngineStatus? {
        guard let raw = try? JSONSerialization.jsonObject(with: data),
              let obj = raw as? [String: Any] else { return nil }
        let phase = Phase(rawValue: obj["status"] as? String ?? "") ?? .unknown
        return EngineStatus(
            phase: phase,
            mode: obj["mode"] as? String ?? "",
            lastTranscription: obj["last_transcription"] as? String ?? "",
            wpm: (obj["wpm"] as? NSNumber)?.doubleValue ?? 0,
            timestamp: (obj["timestamp"] as? NSNumber)?.doubleValue ?? 0)
    }
}
