import Foundation

/// The gapless data that an MP3 encoder writes into the Xing or Info frame and its LAME extension.
/// LAME and ffmpeg both write it. ffmpeg writes "Lavc" where LAME writes "LAME".
struct MP3GaplessInfo: Equatable, Sendable {
    var frameCount: Int
    var samplesPerFrame: Int
    var encoderDelay: Int
    var padding: Int

    /// The samples of the recording, without encoder delay and padding.
    var validSamples: Int { frameCount * samplesPerFrame - encoderDelay - padding }

    /// The frames of a decoded file that belong to the recording.
    /// iOS ignores this header. Its decoders return every frame and remove only their own decoder delay,
    /// so the recording starts after the encoder delay.
    func playableRange(decodedLength: Int64) -> Range<Int64> {
        let valid = Int64(validSamples)
        guard decodedLength > valid else { return 0..<decodedLength }
        let start = min(Int64(encoderDelay), decodedLength)
        return start..<min(start + valid, decodedLength)
    }

    /// Reads the header from the start of an MP3 file. Embedded cover art makes the ID3v2 tag before the
    /// header large, so `data` must reach 8 KiB past the end of that tag.
    static func parse(_ data: Data) -> MP3GaplessInfo? {
        let bytes = [UInt8](data.prefix(id3Size([UInt8](data.prefix(10))) + 8192))
        guard var start = firstFrame(bytes), start + 4 <= bytes.count else { return nil }
        let isMPEG1 = (bytes[start + 1] >> 3) & 3 == 3
        let isMono = bytes[start + 3] >> 6 == 3
        let sideInfo = isMPEG1 ? (isMono ? 17 : 32) : (isMono ? 9 : 17)
        start += 4 + sideInfo
        guard start + 8 <= bytes.count,
            ["Xing", "Info"].contains(String(decoding: bytes[start..<start + 4], as: UTF8.self))
        else { return nil }
        let flags = uint32(bytes, start + 4)
        var offset = start + 8
        guard flags & 1 != 0, offset + 4 <= bytes.count else { return nil }
        let frames = Int(uint32(bytes, offset))
        offset += 4
        if flags & 2 != 0 { offset += 4 }
        if flags & 4 != 0 { offset += 100 }
        if flags & 8 != 0 { offset += 4 }
        // Encoder name (9), revision, lowpass, peak (4), gains (2 + 2), flags, bitrate: 21 bytes.
        offset += 21
        guard offset + 3 <= bytes.count else { return nil }
        let delay = Int(bytes[offset]) << 4 | Int(bytes[offset + 1]) >> 4
        let padding = Int(bytes[offset + 1] & 0x0F) << 8 | Int(bytes[offset + 2])
        return MP3GaplessInfo(
            frameCount: frames, samplesPerFrame: isMPEG1 ? 1152 : 576, encoderDelay: delay, padding: padding)
    }

    /// The offset of the first MPEG audio layer III frame header, after an ID3v2 tag.
    private static func firstFrame(_ bytes: [UInt8]) -> Int? {
        var offset = id3Size(bytes)
        while offset + 4 <= bytes.count {
            let b1 = bytes[offset + 1]
            if bytes[offset] == 0xFF, b1 & 0xE0 == 0xE0, (b1 >> 3) & 3 != 1, (b1 >> 1) & 3 == 1 {
                return offset
            }
            offset += 1
        }
        return nil
    }

    /// The length of the ID3v2 tag at the start of the file, or 0.
    private static func id3Size(_ bytes: [UInt8]) -> Int {
        guard bytes.count >= 10, bytes[0..<3] == [0x49, 0x44, 0x33] else { return 0 }
        return 10 + bytes[6..<10].reduce(0) { $0 << 7 | Int($1 & 0x7F) } + (bytes[5] & 0x10 != 0 ? 10 : 0)
    }

    private static func uint32(_ bytes: [UInt8], _ offset: Int) -> UInt32 {
        bytes[offset..<offset + 4].reduce(0) { $0 << 8 | UInt32($1) }
    }
}
