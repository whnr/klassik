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
    /// A visible picture reloads after replacement bytes reach disk, even when its URL stays the same.
    private(set) var revision = 0

    /// Nil keeps every file.
    var limit: Int64? {
        didSet {
            defaults.set(limit ?? 0, forKey: limitKey)
            evict()
        }
    }

    /// True when no file fits under the limit.
    var isFull: Bool { limit.map { bytes >= $0 } ?? false }

    /// False when the room under the limit is smaller than the mean kept file. A fetch would then most likely end
    /// in a file that does not fit, and on a cellular connection that costs data for nothing.
    var hasRoomForTypicalFile: Bool { fits(bytes / Int64(max(1, entries.count))) }

    /// True when a file of `size` bytes fits under the limit without pushing out an older one.
    func fits(_ size: Int64) -> Bool { limit.map { bytes + size <= $0 } ?? true }

    @ObservationIgnored private var entries: [String: Entry] = [:]
    @ObservationIgnored private var scan: Task<Void, Never>?
    /// Removals run off the main actor, and every later disk access waits for them, so a removal never deletes a
    /// file written after it.
    @ObservationIgnored private var removal: Task<Void, Never>?
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
    func loaded() async {
        await scan?.value
        await removal?.value
    }

    func contains(_ key: String) -> Bool { contains(named: Self.name(key)) }

    func contains(named name: String) -> Bool { entries[name] != nil }

    /// The file of a key, or nil. A read marks the file as shown now.
    func data(for key: String) async -> Data? { await data(named: Self.name(key)) }

    /// The file of a name, as `name(_:)` or `contentName(_:)` gives it, or nil.
    func data(named name: String) async -> Data? {
        let file = folder.appending(path: name)
        let removal = removal
        let data = await Task.detached(priority: .userInitiated) { () -> Data? in
            await removal?.value
            guard let data = try? Data(contentsOf: file) else { return nil }
            try? FileManager.default.setAttributes([.modificationDate: Date.now], ofItemAtPath: file.path())
            return data
        }.value
        if data != nil { entries[name]?.date = .now }
        return data
    }

    /// False when the file could not be written, for example on a full disk.
    @discardableResult func store(_ data: Data, for key: String) async -> Bool {
        await write(data, named: Self.name(key))
    }

    /// Keeps the bytes under their content name and returns it, or nil when the write fails. Identical bytes share
    /// one file, so a file never changes after the write (ADR 0059).
    func store(content data: Data) async -> String? {
        let name = Self.contentName(data)
        if entries[name] != nil {
            entries[name]?.date = .now
            return name
        }
        return await write(data, named: name) ? name : nil
    }

    /// Removes one file. Links to it are then invalid.
    func remove(named name: String) {
        guard entries.removeValue(forKey: name) != nil else { return }
        total()
        let file = folder.appending(path: name)
        remove { try? FileManager.default.removeItem(at: file) }
    }

    private func write(_ data: Data, named name: String) async -> Bool {
        let folder = folder
        let removal = removal
        let written = await Task.detached(priority: .utility) { () -> Bool in
            await removal?.value
            do {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                try data.write(to: folder.appending(path: name), options: .atomic)
                return true
            } catch {
                return false
            }
        }.value
        guard written else { return false }
        entries[name] = Entry(size: Int64(data.count), date: .now)
        revision += 1
        total()
        evict(keeping: name)
        return true
    }

    func clear() {
        entries = [:]
        revision += 1
        total()
        let folder = folder
        remove { try? FileManager.default.removeItem(at: folder) }
    }

    /// A large folder can take long to delete, so the main actor only waits for the totals.
    private func remove(_ work: @escaping @Sendable () -> Void) {
        let previous = removal
        removal = Task.detached(priority: .utility) {
            await previous?.value
            work()
        }
    }

    /// Reads the folder again. The entries follow the files, not the other way round.
    func rescan() async {
        let folder = folder
        let removal = removal
        let found = await Task.detached(priority: .utility) { () -> [String: Entry] in
            await removal?.value
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
        var files: [URL] = []
        while bytes > limit, let entry = oldest.first {
            oldest.removeFirst()
            if entry.key == keep { continue }
            files.append(folder.appending(path: entry.key))
            entries[entry.key] = nil
            bytes -= entry.value.size
        }
        let doomed = files
        remove {
            for file in doomed { try? FileManager.default.removeItem(at: file) }
        }
    }

    /// A key can hold a URL with a query, so the file name is its hash.
    nonisolated static func name(_ key: String) -> String { hex(SHA256.hash(data: Data(key.utf8))) }

    /// The SHA-256 of the bytes themselves.
    nonisolated static func contentName(_ data: Data) -> String { hex(SHA256.hash(data: data)) }

    nonisolated private static func hex(_ digest: SHA256.Digest) -> String {
        digest.map { String(format: "%02x", $0) }.joined()
    }
}
