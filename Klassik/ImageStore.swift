import CryptoKit
import Foundation
import Observation

/// Pictures on the device in one folder, under a size limit that the listener sets. When the folder is over the
/// limit, the files shown longest ago go first. Without a limit, every file stays (ADR 0051).
@MainActor @Observable
final class ImageStore {
    private struct Entry {
        var size: Int64
        var date: Date
    }

    private(set) var bytes: Int64 = 0

    /// Nil keeps every file.
    var limit: Int64? {
        didSet {
            defaults.set(limit ?? 0, forKey: limitKey)
            evict()
        }
    }

    /// True when the next file would push out an older one.
    var isFull: Bool { limit.map { bytes >= $0 } ?? false }

    @ObservationIgnored private var entries: [String: Entry] = [:]
    @ObservationIgnored private var scan: Task<Void, Never>?
    private let folder: URL
    private let defaults: UserDefaults
    private let limitKey: String

    /// A stored limit of 0 is no limit, because `UserDefaults` cannot hold nil.
    init(folder: URL, limitKey: String, defaults: UserDefaults = .standard) {
        self.folder = folder
        self.limitKey = limitKey
        self.defaults = defaults
        let stored = defaults.object(forKey: limitKey) as? Int64
        limit = stored.flatMap { $0 > 0 ? $0 : nil }
        scan = Task { await rescan() }
    }

    /// Composer and performer pictures from Wikimedia Commons. They belong to no account, so signing out keeps them.
    static let pictures = ImageStore(
        folder: .cachesDirectory.appending(path: "pictures"), limitKey: "store.picturesLimit")

    /// The art of the albums of the signed-in server.
    static let albumArt = ImageStore(
        folder: .cachesDirectory.appending(path: "album-art"), limitKey: "store.albumArtLimit")

    /// Waits for the first read of the folder, so that `contains` knows every file.
    func loaded() async { await scan?.value }

    func contains(_ key: String) -> Bool { entries[Self.name(key)] != nil }

    /// The file of a key, or nil. A read marks the file as shown now.
    func data(for key: String) async -> Data? {
        let name = Self.name(key)
        let file = folder.appending(path: name)
        let data = await Task.detached(priority: .userInitiated) { () -> Data? in
            guard let data = try? Data(contentsOf: file) else { return nil }
            try? FileManager.default.setAttributes([.modificationDate: Date.now], ofItemAtPath: file.path())
            return data
        }.value
        if data != nil { entries[name]?.date = .now }
        return data
    }

    func store(_ data: Data, for key: String) async {
        let name = Self.name(key)
        let folder = folder
        let written = await Task.detached(priority: .utility) { () -> Bool in
            do {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                try data.write(to: folder.appending(path: name), options: .atomic)
                return true
            } catch {
                return false
            }
        }.value
        guard written else { return }
        entries[name] = Entry(size: Int64(data.count), date: .now)
        total()
        evict(keeping: name)
    }

    func clear() {
        try? FileManager.default.removeItem(at: folder)
        entries = [:]
        total()
    }

    /// Reads the folder again. The entries follow the files, not the other way round.
    func rescan() async {
        let folder = folder
        let found = await Task.detached(priority: .utility) { () -> [String: Entry] in
            let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey]
            let urls =
                (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys)) ?? []
            var found: [String: Entry] = [:]
            for url in urls {
                let values = try? url.resourceValues(forKeys: Set(keys))
                found[url.lastPathComponent] = Entry(
                    size: Int64(values?.fileSize ?? 0), date: values?.contentModificationDate ?? .distantPast)
            }
            return found
        }.value
        entries = found
        total()
        evict()
    }

    private func total() {
        bytes = entries.values.reduce(0) { $0 + $1.size }
    }

    private func evict(keeping keep: String? = nil) {
        guard let limit, bytes > limit else { return }
        var oldest = entries.sorted { $0.value.date < $1.value.date }
        while bytes > limit, let entry = oldest.first {
            oldest.removeFirst()
            if entry.key == keep { continue }
            try? FileManager.default.removeItem(at: folder.appending(path: entry.key))
            entries[entry.key] = nil
            bytes -= entry.value.size
        }
    }

    /// A key can hold a URL with a query, so the file name is its hash.
    nonisolated static func name(_ key: String) -> String {
        SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
