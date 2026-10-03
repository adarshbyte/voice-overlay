import Foundation

public protocol AudioPreparing: Sendable {
    func prepare(url: URL) throws -> URL
}

public struct IdentityAudioPrep: AudioPreparing {
    public init() {}
    public func prepare(url: URL) throws -> URL { url }
}

public struct SilenceTrimError: Error, Equatable, LocalizedError {
    public let message: String
    public var errorDescription: String? { message }
    public init(_ message: String) { self.message = message }
}

public enum SampleTrim {
    /// Drops quiet head/tail, keeping `padSamples` around the first/last loud frame.
    public static func trim(
        _ samples: [Int16],
        frameSize: Int = 320,
        threshold: Int16 = 800,
        padSamples: Int = 3200
    ) -> [Int16] {
        guard !samples.isEmpty else { return [] }
        var first: Int?
        var last: Int?
        var index = 0
        while index < samples.count {
            let end = min(index + frameSize, samples.count)
            var peak = 0
            for i in index..<end {
                let a = abs(Int(samples[i]))
                if a > peak { peak = a }
            }
            if peak >= Int(threshold) {
                if first == nil { first = index }
                last = end
            }
            index = end
        }
        guard let startFrame = first, let endFrame = last else { return [] }
        let start = max(0, startFrame - padSamples)
        let end = min(samples.count, endFrame + padSamples)
        return Array(samples[start..<end])
    }

    public static func normalize(_ samples: [Int16], targetPeak: Int16 = 28000) -> [Int16] {
        guard let peak = samples.map({ abs(Int($0)) }).max(), peak > 0 else { return samples }
        if peak >= Int(targetPeak) / 3 { return samples }
        let scale = Float(targetPeak) / Float(peak)
        return samples.map { sample in
            let boosted = Float(sample) * scale
            let clamped = max(Float(Int16.min), min(Float(Int16.max), boosted))
            return Int16(clamped)
        }
    }
}

public struct PcmWav: Equatable {
    public var sampleRate: Int
    public var channels: Int
    public var samples: [Int16]

    public init(sampleRate: Int, channels: Int, samples: [Int16]) {
        self.sampleRate = sampleRate
        self.channels = channels
        self.samples = samples
    }

    public static func load(url: URL) throws -> PcmWav {
        let data = try Data(contentsOf: url)
        return try decode(data)
    }

    public func write(to url: URL) throws {
        try encode().write(to: url, options: .atomic)
    }

    public static func decode(_ data: Data) throws -> PcmWav {
        guard data.count >= 12 else { throw SilenceTrimError("WAV too small.") }
        func le16(_ i: Int) -> UInt16 {
            UInt16(data[i]) | UInt16(data[i + 1]) << 8
        }
        func le32(_ i: Int) -> UInt32 {
            UInt32(data[i])
                | UInt32(data[i + 1]) << 8
                | UInt32(data[i + 2]) << 16
                | UInt32(data[i + 3]) << 24
        }
        guard String(bytes: data[0..<4], encoding: .ascii) == "RIFF",
              String(bytes: data[8..<12], encoding: .ascii) == "WAVE"
        else { throw SilenceTrimError("Not a WAV file.") }

        var offset = 12
        var sampleRate = 16000
        var channels = 1
        var bits = 16
        var pcm: [Int16]?
        while offset + 8 <= data.count {
            let id = String(bytes: data[offset..<(offset + 4)], encoding: .ascii) ?? ""
            let size = Int(le32(offset + 4))
            let start = offset + 8
            let end = min(data.count, start + size)
            if id == "fmt ", size >= 16 {
                let format = le16(start)
                channels = Int(le16(start + 2))
                sampleRate = Int(le32(start + 4))
                bits = Int(le16(start + 14))
                if format != 1 || bits != 16 {
                    throw SilenceTrimError("Need 16-bit PCM WAV.")
                }
            } else if id == "data" {
                let count = (end - start) / 2
                var samples: [Int16] = []
                samples.reserveCapacity(count)
                var i = start
                while i + 1 < end {
                    let value = Int16(bitPattern: UInt16(data[i]) | UInt16(data[i + 1]) << 8)
                    samples.append(value)
                    i += 2
                }
                pcm = samples
            }
            offset = start + size
            if size % 2 == 1 { offset += 1 }
        }
        guard let samples = pcm else { throw SilenceTrimError("WAV has no audio data.") }
        return PcmWav(sampleRate: sampleRate, channels: channels, samples: samples)
    }

    public func encode() -> Data {
        let dataBytes = samples.count * 2
        var data = Data(capacity: 44 + dataBytes)
        func appendASCII(_ s: String) { data.append(contentsOf: s.utf8) }
        func append16(_ v: UInt16) {
            var x = v.littleEndian
            Swift.withUnsafeBytes(of: &x) { data.append(contentsOf: $0) }
        }
        func append32(_ v: UInt32) {
            var x = v.littleEndian
            Swift.withUnsafeBytes(of: &x) { data.append(contentsOf: $0) }
        }
        appendASCII("RIFF")
        append32(UInt32(36 + dataBytes))
        appendASCII("WAVE")
        appendASCII("fmt ")
        append32(16)
        append16(1)
        append16(UInt16(channels))
        append32(UInt32(sampleRate))
        append32(UInt32(sampleRate * channels * 2))
        append16(UInt16(channels * 2))
        append16(16)
        appendASCII("data")
        append32(UInt32(dataBytes))
        for sample in samples {
            append16(UInt16(bitPattern: sample))
        }
        return data
    }
}

public struct WavSilencePrep: AudioPreparing {
    public init() {}

    public func prepare(url: URL) throws -> URL {
        var wav = try PcmWav.load(url: url)
        let trimmed = SampleTrim.trim(wav.samples)
        guard !trimmed.isEmpty else {
            throw SilenceTrimError("Heard silence. Try again.")
        }
        wav.samples = SampleTrim.normalize(trimmed)
        let out = url.deletingLastPathComponent()
            .appendingPathComponent(url.deletingPathExtension().lastPathComponent + "-prep.wav")
        try wav.write(to: out)
        return out
    }
}
