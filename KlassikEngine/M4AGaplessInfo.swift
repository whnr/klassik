import Foundation

/// The gapless data of an MP4 audio file (AAC or ALAC in an M4A container).
/// An encoder prepends priming frames and appends remainder frames. Apple writes both in an `iTunSMPB` tag.
/// ffmpeg writes an edit list instead: its first entry starts after the priming, and the last packet is short.
public struct M4AGaplessInfo: Equatable, Sendable {
    /// Frames before the recording.
    public var priming: Int64
    /// Frames of the recording.
    public var valid: Int64
    /// Every frame that the packets hold.
    public var total: Int64

    public init(priming: Int64, valid: Int64, total: Int64) {
        self.priming = priming
        self.valid = valid
        self.total = total
    }

    /// The frames of a decoded file that belong to the recording. Some iOS decoders apply the file's own data
    /// and some return every packet, so the length of the decoded file tells which frames to cut.
    public func playableRange(decodedLength: Int64) -> Range<Int64> {
        guard decodedLength > valid else { return 0..<decodedLength }
        // The decoder removed the priming and kept the remainder.
        if decodedLength == total - priming { return 0..<valid }
        guard decodedLength == total else { return 0..<decodedLength }
        return priming..<(priming + valid)
    }

    /// The moov box is a few hundred kilobytes at most, also with cover art; a larger one is not read.
    static let moovLimit: Int64 = 16 << 20

    /// Reads the data from the file at `url`, or nil when it is no MP4 file or declares no trim.
    public static func parse(fileAt url: URL) -> M4AGaplessInfo? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var offset: UInt64 = 0
        var first = true
        while let head = try? handle.read(upToCount: 16), head.count >= 8 {
            let bytes = [UInt8](head)
            let type = String(decoding: bytes[4..<8], as: UTF8.self)
            if first, type != "ftyp" { return nil }
            first = false
            var size = UInt64(uint32(bytes, 0))
            var headerSize: UInt64 = 8
            if size == 1, bytes.count >= 16 {
                size = UInt64(uint32(bytes, 8)) << 32 | UInt64(uint32(bytes, 12))
                headerSize = 16
            }
            guard size >= headerSize else { return nil }
            if type == "moov" {
                guard size - headerSize <= UInt64(moovLimit) else { return nil }
                try? handle.seek(toOffset: offset + headerSize)
                guard let body = try? handle.read(upToCount: Int(size - headerSize)) else { return nil }
                return parse(moov: [UInt8](body))
            }
            offset += size
            guard (try? handle.seek(toOffset: offset)) != nil else { return nil }
        }
        return nil
    }

    /// `body` is the content of the moov box.
    public static func parse(moov body: [UInt8]) -> M4AGaplessInfo? {
        let moov = Box(type: "moov", body: body[...])
        guard let track = moov.children.first(where: { $0.type == "trak" && $0.find(["mdia", "minf", "smhd"]) != nil }),
            let mdhd = track.find(["mdia", "mdhd"]),
            let stts = track.find(["mdia", "minf", "stbl", "stts"]),
            let mediaScale = timescale(mdhd.body),
            let total = frames(stts.body), total > 0
        else { return nil }
        if let tag = smpb(moov), let info = tag.info(total: total) { return info }
        guard let elst = track.find(["edts", "elst"]), let entry = firstEdit(elst.body) else { return nil }
        let priming = entry.mediaTime
        let remaining = total - priming
        guard remaining > 0 else { return nil }
        var valid = remaining
        if let movieScale = moov.find(["mvhd"]).flatMap({ timescale($0.body) }), entry.duration > 0 {
            let declared = entry.duration * mediaScale / movieScale
            // The duration has the resolution of the movie timescale, one millisecond for ffmpeg. The short last
            // packet gives the exact end.
            let resolution = (mediaScale + movieScale - 1) / movieScale + 1
            if declared + resolution < remaining { valid = declared }
        }
        return M4AGaplessInfo(priming: priming, valid: valid, total: total)
    }

    // MARK: Boxes

    private struct Box {
        var type: String
        var body: ArraySlice<UInt8>

        /// The boxes inside this one. A `meta` box has four bytes of version and flags before them.
        var children: [Box] {
            var result: [Box] = []
            var start = body.startIndex + (type == "meta" ? 4 : 0)
            while start + 8 <= body.endIndex {
                var size = Int(M4AGaplessInfo.uint32(body, start))
                let name = String(decoding: body[(start + 4)..<(start + 8)], as: UTF8.self)
                var header = 8
                if size == 1, start + 16 <= body.endIndex {
                    size = Int(M4AGaplessInfo.uint32(body, start + 12))
                    header = 16
                }
                if size == 0 { size = body.endIndex - start }
                guard size >= header, start + size <= body.endIndex else { break }
                result.append(Box(type: name, body: body[(start + header)..<(start + size)]))
                start += size
            }
            return result
        }

        func find(_ path: [String]) -> Box? {
            guard let name = path.first else { return self }
            return children.first { $0.type == name }?.find(Array(path.dropFirst()))
        }
    }

    // MARK: Fields

    static func uint32<C: Collection<UInt8>>(_ bytes: C, _ index: C.Index) -> UInt32 {
        var value: UInt32 = 0
        var position = index
        for _ in 0..<4 {
            value = value << 8 | UInt32(bytes[position])
            position = bytes.index(after: position)
        }
        return value
    }

    private static func uint64(_ bytes: ArraySlice<UInt8>, _ index: Int) -> UInt64 {
        UInt64(uint32(bytes, index)) << 32 | UInt64(uint32(bytes, index + 4))
    }

    /// The time scale of an mdhd or mvhd box.
    private static func timescale(_ body: ArraySlice<UInt8>) -> Int64? {
        let at = body.startIndex + (body.first == 1 ? 20 : 12)
        guard body.count >= at - body.startIndex + 4 else { return nil }
        let scale = Int64(uint32(body, at))
        return scale > 0 ? scale : nil
    }

    /// The sum of every sample duration in a stts box.
    private static func frames(_ body: ArraySlice<UInt8>) -> Int64? {
        let start = body.startIndex
        guard body.count >= 8 else { return nil }
        let count = Int(uint32(body, start + 4))
        guard count >= 0, body.count >= 8 + count * 8 else { return nil }
        return (0..<count).reduce(Int64(0)) { sum, index in
            let at = start + 8 + index * 8
            return sum + Int64(uint32(body, at)) * Int64(uint32(body, at + 4))
        }
    }

    /// The first edit that plays media: an empty edit (media time -1) only delays the start.
    private static func firstEdit(_ body: ArraySlice<UInt8>) -> (duration: Int64, mediaTime: Int64)? {
        guard body.count >= 8 else { return nil }
        let start = body.startIndex
        let wide = body.first == 1
        let size = wide ? 20 : 12
        let count = Int(uint32(body, start + 4))
        guard count >= 0, body.count >= 8 + count * size else { return nil }
        for index in 0..<count {
            let at = start + 8 + index * size
            let duration = wide ? Int64(bitPattern: uint64(body, at)) : Int64(uint32(body, at))
            let time =
                wide ? Int64(bitPattern: uint64(body, at + 8)) : Int64(Int32(bitPattern: uint32(body, at + 4)))
            if time >= 0 { return (duration, time) }
        }
        return nil
    }

    /// The iTunSMPB tag: eight zeros, then delay, padding and sample count in hexadecimal.
    private struct SMPB {
        var delay: Int64
        var padding: Int64
        var count: Int64

        func info(total: Int64) -> M4AGaplessInfo? {
            let valid = count > 0 ? count : total - delay - padding
            guard delay >= 0, padding >= 0, valid > 0, delay + valid <= total else { return nil }
            return M4AGaplessInfo(priming: delay, valid: valid, total: total)
        }
    }

    private static func smpb(_ moov: Box) -> SMPB? {
        guard let items = moov.find(["udta", "meta", "ilst"]) else { return nil }
        for item in items.children where item.type == "----" {
            let parts = item.children
            guard let name = parts.first(where: { $0.type == "name" }),
                String(decoding: name.body.dropFirst(4), as: UTF8.self) == "iTunSMPB",
                let data = parts.first(where: { $0.type == "data" })
            else { continue }
            // Version, flags and locale precede the text.
            let text = String(decoding: data.body.dropFirst(8), as: UTF8.self)
            let fields = text.split(whereSeparator: \.isWhitespace).compactMap { Int64($0, radix: 16) }
            guard fields.count >= 4 else { return nil }
            return SMPB(delay: fields[1], padding: fields[2], count: fields[3])
        }
        return nil
    }
}
