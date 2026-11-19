import Foundation

enum FLACArtwork {
    /// Lossless downloads need artwork even when AVFoundation supplies no common artwork item.
    static func data(in file: URL) -> Data? {
        guard let handle = try? FileHandle(forReadingFrom: file) else { return nil }
        defer { try? handle.close() }
        guard (try? handle.read(upToCount: 4)) == Data("fLaC".utf8) else { return nil }
        while let header = try? handle.read(upToCount: 4), header.count == 4 {
            let length = header.dropFirst().reduce(0) { ($0 << 8) | Int($1) }
            if header[0] & 0x7f == 6 {
                guard let block = try? handle.read(upToCount: length), block.count == length else { return nil }
                if let picture = picture(in: block) { return picture }
            } else {
                guard let position = try? handle.offset(),
                    (try? handle.seek(toOffset: position + UInt64(length))) != nil
                else { return nil }
            }
            if header[0] & 0x80 != 0 { return nil }
        }
        return nil
    }

    private static func picture(in block: Data) -> Data? {
        var offset = 0
        func integer() -> Int? {
            guard offset <= block.count - 4 else { return nil }
            defer { offset += 4 }
            return block[offset..<offset + 4].reduce(0) { ($0 << 8) | Int($1) }
        }
        func skip(_ count: Int) -> Bool {
            guard count <= block.count - offset else { return false }
            offset += count
            return true
        }
        guard integer() != nil,
            let mimeLength = integer(), skip(mimeLength),
            let descriptionLength = integer(), skip(descriptionLength),
            skip(16), let imageLength = integer(), imageLength <= block.count - offset
        else { return nil }
        return block.subdata(in: offset..<offset + imageLength)
    }
}
