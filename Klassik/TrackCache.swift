import Foundation
import Observation

/// Every track that played and is not downloaded. The oldest ones leave when the cache grows past its limit.
@MainActor @Observable
final class TrackCache {
    struct Entry: Equatable, Sendable {
        var id: String
        var url: URL
        var size: Int64
        /// The last time the track played.
        var lastUsed: Date
    }

    /// Decimal units, as the system shows file sizes.
    nonisolated static let limits: [Int64] = [500_000_000, 1_000_000_000, 2_000_000_000, 5_000_000_000, 10_000_000_000]
    nonisolated static let defaultLimit: Int64 = 2_000_000_000
    private static let limitKey = "cache.limit"

    var limit: Int64 {
        didSet { defaults.set(Int(limit), forKey: Self.limitKey) }
    }
    /// Bytes of all cached tracks.
    private(set) var size: Int64 = 0
    private(set) var ids: Set<String> = []

    let folder: URL
    private let defaults: UserDefaults

    init(folder: URL = URL.cachesDirectory.appending(path: "tracks"), defaults: UserDefaults = .standard) {
        self.folder = folder
        self.defaults = defaults
        let stored = Int64(defaults.integer(forKey: Self.limitKey))
        limit = stored > 0 ? stored : Self.defaultLimit
        refresh()
    }

    /// The tracks to delete, oldest first, until the rest fits the limit.
    /// Downloaded tracks never leave and do not count toward the limit.
    nonisolated static func evictions(_ entries: [Entry], limit: Int64, protecting downloaded: Set<String>) -> [Entry] {
        let candidates = entries.filter { !downloaded.contains($0.id) }
        var total = candidates.reduce(0) { $0 + $1.size }
        var result: [Entry] = []
        for entry in candidates.sorted(by: { ($0.lastUsed, $0.id) < ($1.lastUsed, $1.id) }) {
            if total <= limit { break }
            result.append(entry)
            total -= entry.size
        }
        return result
    }

    /// Marks the track as just played. Returns nil if it is not cached.
    func url(for song: Song) -> URL? {
        let url = folder.appending(path: DownloadStore.fileName(for: song))
        guard FileManager.default.fileExists(atPath: url.path()) else { return nil }
        try? FileManager.default.setAttributes([.modificationDate: Date.now], ofItemAtPath: url.path())
        return url
    }

    /// Moves a loaded file into the cache and makes room for it.
    func store(_ temporary: URL, for song: Song, protecting downloaded: Set<String>) throws -> URL {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let target = folder.appending(path: DownloadStore.fileName(for: song))
        try? FileManager.default.removeItem(at: target)
        try FileManager.default.moveItem(at: temporary, to: target)
        enforce(protecting: downloaded)
        return target
    }

    /// Hands the cached file of a track over to a download, so the track lives once.
    func take(_ song: Song) -> URL? {
        let url = folder.appending(path: DownloadStore.fileName(for: song))
        guard FileManager.default.fileExists(atPath: url.path()) else { return nil }
        let moved = URL.temporaryDirectory.appending(path: "take-\(UUID().uuidString)")
        do { try FileManager.default.moveItem(at: url, to: moved) } catch { return nil }
        refresh()
        return moved
    }

    func enforce(protecting downloaded: Set<String>) {
        for entry in Self.evictions(entries(), limit: limit, protecting: downloaded) {
            try? FileManager.default.removeItem(at: entry.url)
        }
        refresh()
    }

    func clear() {
        try? FileManager.default.removeItem(at: folder)
        refresh()
    }

    func refresh() {
        let all = entries()
        size = all.reduce(0) { $0 + $1.size }
        ids = Set(all.map(\.id))
    }

    private func entries() -> [Entry] {
        let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey]
        let urls = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys)) ?? []
        return urls.compactMap { url in
            guard !url.lastPathComponent.hasPrefix("."),
                let values = try? url.resourceValues(forKeys: Set(keys))
            else { return nil }
            return Entry(
                id: url.deletingPathExtension().lastPathComponent, url: url,
                size: Int64(values.fileSize ?? 0), lastUsed: values.contentModificationDate ?? .distantPast)
        }
    }
}

/// Whether a set of tracks plays without the server.
enum OfflineStatus: Int, Comparable, Sendable {
    case none
    case cached
    case downloaded

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }

    init(songIDs: [String], downloaded: Set<String>, cached: Set<String>) {
        let ids = Set(songIDs)
        if ids.isEmpty {
            self = .none
        } else if ids.isSubset(of: downloaded) {
            self = .downloaded
        } else if ids.isSubset(of: downloaded.union(cached)) {
            self = .cached
        } else {
            self = .none
        }
    }
}
