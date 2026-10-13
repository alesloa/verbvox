import XCTest
@testable import VerbVoxCore

final class WavEncoderTests: XCTestCase {

    /// Little-endian read helpers over the encoded header.
    private func u16(_ data: Data, _ offset: Int) -> UInt16 {
        UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
    }
    private func u32(_ data: Data, _ offset: Int) -> UInt32 {
        UInt32(data[offset]) | (UInt32(data[offset + 1]) << 8)
            | (UInt32(data[offset + 2]) << 16) | (UInt32(data[offset + 3]) << 24)
    }
    private func ascii(_ data: Data, _ range: Range<Int>) -> String {
        String(bytes: data[range], encoding: .ascii) ?? ""
    }

    func testEncodesCanonicalWavHeader() {
        let samples = [Int16](repeating: 0, count: 1600) // 0.1s @ 16kHz
        let data = WavEncoder.encode(samples: samples, sampleRate: 16000, channels: 1)

        // Canonical 44-byte header + PCM body.
        XCTAssertEqual(data.count, 44 + 1600 * 2)

        // RIFF / WAVE container.
        XCTAssertEqual(ascii(data, 0..<4), "RIFF")
        XCTAssertEqual(u32(data, 4), UInt32(36 + 1600 * 2)) // ChunkSize
        XCTAssertEqual(ascii(data, 8..<12), "WAVE")

        // fmt  chunk: PCM, 16000 Hz, 1 channel, 16-bit.
        XCTAssertEqual(ascii(data, 12..<16), "fmt ")
        XCTAssertEqual(u32(data, 16), 16)      // Subchunk1Size (PCM)
        XCTAssertEqual(u16(data, 20), 1)       // AudioFormat = PCM
        XCTAssertEqual(u16(data, 22), 1)       // NumChannels
        XCTAssertEqual(u32(data, 24), 16000)   // SampleRate
        XCTAssertEqual(u32(data, 28), 16000 * 1 * 16 / 8) // ByteRate
        XCTAssertEqual(u16(data, 32), 1 * 16 / 8)          // BlockAlign
        XCTAssertEqual(u16(data, 34), 16)      // BitsPerSample

        // data chunk length == samples * 2.
        XCTAssertEqual(ascii(data, 36..<40), "data")
        XCTAssertEqual(u32(data, 40), UInt32(1600 * 2))
    }

    func testWritesSamplesLittleEndian() {
        let samples: [Int16] = [1, -1, 256, Int16.min, Int16.max]
        let data = WavEncoder.encode(samples: samples, sampleRate: 16000, channels: 1)
        // First sample (1) at byte 44 -> 0x01 0x00.
        XCTAssertEqual(data[44], 0x01)
        XCTAssertEqual(data[45], 0x00)
        // Second sample (-1) -> 0xFF 0xFF.
        XCTAssertEqual(data[46], 0xFF)
        XCTAssertEqual(data[47], 0xFF)
    }
}
