import AVFoundation
import Foundation

/// Microphone capture via `AVAudioEngine`, producing a 16 kHz mono 16-bit WAV.
///
/// Port of `AudioRecorder` in `transcribe_cli.py`: it recorded at the device
/// rate (`sample_rate = 44100`, mono) into a buffer list between start/stop, then
/// down-converted to 16 kHz mono `pcm_s16le` via ffmpeg before handing the WAV to
/// the STT server. Here `AVAudioConverter` replaces ffmpeg and `WavEncoder`
/// replaces `scipy.io.wavfile` + the ffmpeg mux.
///
/// **Too-short handling:** Python's only guard was `len(self.audio_data) == 0`
/// ("released too quickly" → no buffers captured). There is no numeric
/// minimum-duration threshold in the Python. `stop()` reproduces that exactly by
/// returning `nil` when no audio frames were accumulated.
public final class AudioCapture {

    /// Target output: 16 kHz mono 16-bit — the format the STT providers expect.
    public static let outputSampleRate: Double = 16000

    private let engine = AVAudioEngine()

    /// Buffers copied out of the render thread, guarded by `lock`.
    private var buffers: [AVAudioPCMBuffer] = []
    private let lock = NSLock()

    /// The hardware input format captured at `start()`, needed to build the
    /// converter at `stop()`.
    private var inputFormat: AVAudioFormat?
    private var isRunning = false

    public init() {}

    /// Begin accumulating microphone input. Throws if the audio engine can't
    /// start (e.g. no input device / mic permission denied).
    public func start() throws {
        // Reset any prior session.
        lock.lock()
        buffers.removeAll()
        lock.unlock()

        let input = engine.inputNode
        let format = input.inputFormat(forBus: 0)
        inputFormat = format

        // DIAGNOSTIC: record mic authorization + the hardware input format we're
        // about to tap. A denied/zeroed mic yields silent buffers with no error.
        let auth = AVCaptureDevice.authorizationStatus(for: .audio)
        let authName: String
        switch auth {
        case .authorized: authName = "authorized"
        case .denied: authName = "denied"
        case .restricted: authName = "restricted"
        case .notDetermined: authName = "notDetermined"
        @unknown default: authName = "unknown(\(auth.rawValue))"
        }
        Self.appendLog("AUDIO start — auth=\(authName) inFmt=\(format.sampleRate)Hz ch=\(format.channelCount) common=\(format.commonFormat.rawValue)")

        // The tap block runs on a real-time audio I/O thread — NOT the main
        // thread. The incoming buffer is reused by the engine, so we deep-copy
        // it and append under `lock`; keep the block allocation-light.
        input.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
            guard let self, let copy = Self.copy(buffer) else { return }
            self.lock.lock()
            self.buffers.append(copy)
            self.lock.unlock()
        }

        engine.prepare()
        try engine.start()
        isRunning = true
    }

    /// Stop capture and return a 16 kHz mono 16-bit WAV, or `nil` if nothing was
    /// recorded (released too quickly — mirrors Python's empty-buffer guard).
    public func stop() -> Data? {
        guard isRunning else { return nil }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRunning = false

        lock.lock()
        let captured = buffers
        buffers.removeAll()
        lock.unlock()

        guard let inputFormat, !captured.isEmpty else { return nil }

        let totalFrames = captured.reduce(AVAudioFrameCount(0)) { $0 + $1.frameLength }
        guard totalFrames > 0 else { return nil }

        // DIAGNOSTIC: peak of the RAW captured Float32 samples, before any
        // conversion. ~0 here => the mic itself delivered silence (permission /
        // device), NOT a converter bug.
        Self.appendLog("AUDIO stop — buffers=\(captured.count) frames=\(totalFrames) rawPeak=\(String(format: "%.5f", Self.rawPeak(captured)))")

        guard let samples = Self.convertToInt16Mono16k(captured, from: inputFormat), !samples.isEmpty else {
            return nil
        }
        // DIAGNOSTIC: peak of the converted Int16 samples.
        let convPeak = samples.reduce(Int16(0)) { max($0, Swift.abs($1)) }
        Self.appendLog("AUDIO converted — samples=\(samples.count) int16Peak=\(convPeak)")
        return WavEncoder.encode(samples: samples, sampleRate: Int(Self.outputSampleRate), channels: 1)
    }

    // MARK: - Conversion

    /// Down-convert captured buffers (device rate, Float32, N channels) to 16 kHz
    /// mono signed-16-bit samples.
    ///
    /// Channel downmix is done **manually** (average all input channels into one
    /// mono Float32 stream at the device rate) before the sample-rate/format
    /// conversion. `AVAudioConverter` cannot reliably downmix more than two
    /// discrete channels without a recognized channel layout — it consumes the
    /// input and emits the correct number of frames but all silence. Multi-mic
    /// Macs report the input as 4 channels, which triggered exactly that. Feeding
    /// the converter a mono→mono resample sidesteps the bug entirely.
    private static func convertToInt16Mono16k(_ buffers: [AVAudioPCMBuffer], from inputFormat: AVAudioFormat) -> [Int16]? {
        // 1. Manual downmix to a single mono Float32 buffer at the device rate.
        guard let monoInputFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: inputFormat.sampleRate,
            channels: 1,
            interleaved: false
        ) else { return nil }

        let totalInputFrames = buffers.reduce(AVAudioFrameCount(0)) { $0 + $1.frameLength }
        guard totalInputFrames > 0,
              let monoBuffer = AVAudioPCMBuffer(pcmFormat: monoInputFormat, frameCapacity: totalInputFrames),
              let monoData = monoBuffer.floatChannelData else { return nil }

        let dst = monoData[0]
        var writeIndex = 0
        for buffer in buffers {
            guard let src = buffer.floatChannelData else { continue }
            let channels = Int(buffer.format.channelCount)
            let frames = Int(buffer.frameLength)
            if channels <= 1 {
                memcpy(dst + writeIndex, src[0], frames * MemoryLayout<Float>.size)
                writeIndex += frames
            } else {
                for i in 0..<frames {
                    var sum: Float = 0
                    for ch in 0..<channels { sum += src[ch][i] }
                    dst[writeIndex] = sum / Float(channels)
                    writeIndex += 1
                }
            }
        }
        monoBuffer.frameLength = AVAudioFrameCount(writeIndex)
        guard writeIndex > 0 else { return nil }

        // 2. Resample mono Float32 (device rate) → mono Int16 16 kHz.
        guard let outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: outputSampleRate,
            channels: 1,
            interleaved: true
        ) else { return nil }

        guard let converter = AVAudioConverter(from: monoInputFormat, to: outputFormat) else { return nil }

        // Output capacity: mono frames scaled by the sample-rate ratio, plus
        // slack for the resampler's edge frames.
        let ratio = outputFormat.sampleRate / monoInputFormat.sampleRate
        let capacity = AVAudioFrameCount((Double(writeIndex) * ratio).rounded(.up)) + 4096
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else { return nil }

        // Feed the whole mono buffer once, then signal end of stream.
        var fed = false
        let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
            if !fed {
                fed = true
                outStatus.pointee = .haveData
                return monoBuffer
            }
            outStatus.pointee = .endOfStream
            return nil
        }

        var error: NSError?
        let status = converter.convert(to: outputBuffer, error: &error, withInputFrom: inputBlock)
        if status == .error || error != nil { return nil }

        let frameCount = Int(outputBuffer.frameLength)
        guard frameCount > 0, let channel = outputBuffer.int16ChannelData else { return nil }
        return Array(UnsafeBufferPointer(start: channel[0], count: frameCount))
    }

    /// DIAGNOSTIC: max absolute Float32 amplitude across all captured buffers.
    private static func rawPeak(_ buffers: [AVAudioPCMBuffer]) -> Float {
        var peak: Float = 0
        for buffer in buffers {
            guard let data = buffer.floatChannelData else { continue }
            let channels = Int(buffer.format.channelCount)
            let frames = Int(buffer.frameLength)
            for ch in 0..<channels {
                for i in 0..<frames {
                    peak = max(peak, Swift.abs(data[ch][i]))
                }
            }
        }
        return peak
    }

    /// DIAGNOSTIC: append one line to the shared engine log (best-effort).
    private static func appendLog(_ message: String) {
        let path = "/tmp/verbvox-engine.log"
        let line = "\(ISO8601DateFormatter().string(from: Date())) \(message)\n"
        let fm = FileManager.default
        if !fm.fileExists(atPath: path) { fm.createFile(atPath: path, contents: nil) }
        guard let handle = FileHandle(forWritingAtPath: path) else { return }
        handle.seekToEndOfFile()
        handle.write(Data(line.utf8))
        try? handle.close()
    }

    /// Deep-copy a Float32 PCM buffer so it survives past the render-thread
    /// callback (the engine reuses the original).
    private static func copy(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let out = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: buffer.frameLength) else { return nil }
        out.frameLength = buffer.frameLength
        let channels = Int(buffer.format.channelCount)
        let frames = Int(buffer.frameLength)
        if let src = buffer.floatChannelData, let dst = out.floatChannelData {
            for ch in 0..<channels {
                memcpy(dst[ch], src[ch], frames * MemoryLayout<Float>.size)
            }
        } else if let src = buffer.int16ChannelData, let dst = out.int16ChannelData {
            for ch in 0..<channels {
                memcpy(dst[ch], src[ch], frames * MemoryLayout<Int16>.size)
            }
        }
        return out
    }
}
