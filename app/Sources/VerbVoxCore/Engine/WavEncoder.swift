import Foundation

/// Encodes 16-bit PCM samples into a canonical 44-byte-header WAV `Data`.
///
/// Mirrors the WAV the Python engine handed to the STT server: after recording
/// at the device rate, `transcribe_cli.py` ran `ffmpeg -ar 16000 -ac 1 -c:a
/// pcm_s16le`, i.e. 16 kHz mono signed-16-bit little-endian PCM. `AudioCapture`
/// produces those samples natively and this type wraps them in the header.
public enum WavEncoder {
    /// Build a little-endian PCM WAV. `samples` are interleaved if `channels > 1`.
    /// Defaults match the pipeline target: 16 kHz mono 16-bit.
    public static func encode(samples: [Int16], sampleRate: Int = 16000, channels: Int = 1) -> Data {
        let bitsPerSample = 16
        let blockAlign = channels * bitsPerSample / 8
        let byteRate = sampleRate * blockAlign
        let dataSize = samples.count * MemoryLayout<Int16>.size

        var data = Data(capacity: 44 + dataSize)

        // RIFF container.
        data.append(ascii: "RIFF")
        data.appendLE(UInt32(36 + dataSize))       // ChunkSize
        data.append(ascii: "WAVE")

        // fmt  subchunk (PCM).
        data.append(ascii: "fmt ")
        data.appendLE(UInt32(16))                   // Subchunk1Size for PCM
        data.appendLE(UInt16(1))                    // AudioFormat = PCM
        data.appendLE(UInt16(channels))
        data.appendLE(UInt32(sampleRate))
        data.appendLE(UInt32(byteRate))
        data.appendLE(UInt16(blockAlign))
        data.appendLE(UInt16(bitsPerSample))

        // data subchunk.
        data.append(ascii: "data")
        data.appendLE(UInt32(dataSize))
        for sample in samples {
            data.appendLE(UInt16(bitPattern: sample))
        }

        return data
    }
}

private extension Data {
    mutating func append(ascii string: String) {
        append(contentsOf: string.utf8)
    }
    mutating func appendLE(_ value: UInt16) {
        Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) }
    }
    mutating func appendLE(_ value: UInt32) {
        Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) }
    }
}
