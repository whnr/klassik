import Foundation

/// Stores encoded bytes in source coordinates. A finite store retains metadata and a reclaimable circular window.
/// The transfer lock owns this object; callers must serialize every operation.
final class PartialAudioFile {
    enum Failure: Error, Equatable {
        case storage
        case invalidRange
        case full
        case incomplete
    }

    static let metadataBytes: Int64 = 65_536
    static let copyBytes = 65_536

    private let descriptor: Int32
    let url: URL
    let capacity: Int64?
    private let prefix: Int64
    private let window: Int64
    private let reservation: AudioStorageBudget.Reservation?
    private(set) var received: Int64 = 0
    private(set) var reclaimed: Int64 = 0

    init(url: URL, capacity: Int64? = nil, budget: AudioStorageBudget? = nil) throws {
        if let capacity, capacity < 2 { throw Failure.storage }
        self.url = url
        self.capacity = capacity
        reservation = budget?.reserve(url)
        let prefix = capacity.map { min(Self.metadataBytes, $0 / 4) } ?? 0
        self.prefix = prefix
        window = capacity.map { $0 - prefix } ?? .max
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        descriptor = open(url.path(percentEncoded: false), O_CREAT | O_TRUNC | O_RDWR, 0o600)
        guard descriptor >= 0 else { throw Failure.storage }
    }

    deinit { close(descriptor) }

    var storedBytes: Int64 { min(received, capacity ?? .max) }
    var isWhole: Bool { reclaimed <= prefix }

    /// These ranges contain bytes, rather than holes or samples that a decoder may treat as silence.
    var ranges: [Range<Int64>] {
        let head = 0..<min(prefix, received)
        let body = max(prefix, reclaimed)..<max(prefix, received)
        return [head, body].filter { !$0.isEmpty }
    }

    /// Reclaims only bytes that the decoder has released. Metadata remains readable after every wrap.
    func discard(before position: Int64) {
        guard capacity != nil else { return }
        reclaimed = max(reclaimed, min(max(position, prefix), received))
    }

    var writableBytes: Int64 {
        guard let capacity else { return .max - received }
        let head = max(prefix - received, 0)
        let used = received - max(prefix, reclaimed)
        return min(capacity - received + max(reclaimed - prefix, 0), head + window - max(used, 0))
    }

    func append(_ data: Data) throws {
        guard Int64(data.count) <= writableBytes else { throw Failure.full }
        let size = min(received + Int64(data.count), capacity ?? .max)
        guard reservation?.resize(to: size) != false else { throw Failure.full }
        var cursor = received
        try data.withUnsafeBytes { bytes in
            var copied = 0
            while copied < bytes.count {
                let (offset, span) = location(cursor)
                let count = min(bytes.count - copied, Int(min(span, Int64(Int.max))))
                try Self.write(descriptor, at: offset, bytes: bytes.baseAddress!.advanced(by: copied), count: count)
                cursor += Int64(count)
                copied += count
            }
        }
        received = cursor
    }

    /// A discarded range fails. Its caller can request validated server bytes, but cannot read stale disk slots.
    func read(at position: Int64, count: Int, into destination: UnsafeMutableRawPointer) throws -> Int {
        guard position >= 0, count >= 0, position <= .max - Int64(count) else { throw Failure.invalidRange }
        let end = position + Int64(count)
        guard end <= received, position >= reclaimed || end <= prefix || isWhole else {
            throw Failure.invalidRange
        }
        var cursor = position
        var copied = 0
        while copied < count {
            let (offset, span) = location(cursor)
            let length = min(count - copied, Int(min(span, Int64(Int.max))))
            var done = 0
            while done < length {
                let actual = pread(
                    descriptor, destination.advanced(by: copied + done), length - done, off_t(offset) + off_t(done))
                guard actual > 0 else { throw Failure.storage }
                done += actual
            }
            copied += length
            cursor += Int64(length)
        }
        return copied
    }

    /// A persistent download reuses every retained byte. Only discarded ranges need another validated server read.
    func copy(to destination: PartialAudioFile, missing: (Int64, Int) throws -> Data) throws {
        guard destination.received == 0, destination.capacity == nil else { throw Failure.invalidRange }
        var cursor: Int64 = 0
        while cursor < received {
            let retained = ranges.first { $0.contains(cursor) }
            let boundary =
                retained?.upperBound ?? ranges.first(where: { $0.lowerBound > cursor })?.lowerBound ?? received
            let count = Int(min(Int64(Self.copyBytes), boundary - cursor))
            let data: Data
            if retained != nil {
                var bytes = Data(count: count)
                _ = try bytes.withUnsafeMutableBytes {
                    try read(at: cursor, count: count, into: $0.baseAddress!)
                }
                data = bytes
            } else {
                data = try missing(cursor, count)
                guard data.count == count else { throw Failure.incomplete }
            }
            try destination.append(data)
            cursor += Int64(count)
        }
    }

    /// Publishing requires every source byte. A rolling window never becomes an offline cache entry.
    func publish(to target: URL) throws {
        guard isWhole else { throw Failure.incomplete }
        try FileManager.default.createDirectory(
            at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard rename(url.path(percentEncoded: false), target.path(percentEncoded: false)) == 0 else {
            throw Failure.storage
        }
        reservation?.publish(to: target)
    }

    private func location(_ position: Int64) -> (offset: Int64, span: Int64) {
        guard capacity != nil else { return (position, .max - position) }
        if position < prefix { return (position, prefix - position) }
        let slot = (position - prefix) % window
        return (prefix + slot, window - slot)
    }

    private static func write(_ descriptor: Int32, at position: Int64, bytes: UnsafeRawPointer, count: Int) throws {
        var copied = 0
        while copied < count {
            let written = pwrite(
                descriptor, bytes.advanced(by: copied), count - copied, off_t(position) + off_t(copied))
            guard written > 0 else { throw Failure.storage }
            copied += written
        }
    }
}
