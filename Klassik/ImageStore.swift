import CryptoKit
import Foundation
import Observation

/// Pictures on the device in one folder. Every file stays until the listener signs out or the cover pass replaces it.
@MainActor @Observable
final class ImageStore {
    private struct Entry {
        var size: Int64
    }

    private(set) var bytes: Int64 = 0
    /// Writes per file name. A visible picture reloads after its replacement bytes reach disk, even when its URL
    /// stays the same, and a write of another file does not reload it.
    private var writes: [String: Int] = [:]
    private var clears = 0

    func revision(of keys: [String]) -> Int {
        keys.reduce(clears) { $0 + (writes[Self.name($1)] ?? 0) }
    }

    @ObservationIgnored private var entries: [String: Entry] = [:]
    @ObservationIgnored private var scan: Task<Void, Never>?
    /// Removals run off the main actor, and every later disk access waits for them, so a removal never deletes a
    /// file written after it.
    @ObservationIgnored private var removal: Task<Void, Never>?
    private let folder: URL

    init(folder: URL) {
        self.folder = folder
        scan = Task { await rescan() }
    }

    /// Composer and performer pictures from Wikimedia Commons. They belong to no account, so signing out keeps them.
    static let pictures = ImageStore(folder: .cachesDirectory.appending(path: "pictures"))

    /// The art of the albums of the signed-in server.
    static let albumArt = ImageStore(folder: .cachesDirectory.appending(path: "album-art"))

    /// Waits for the first read of the folder, so that `contains` knows every file.
    func loaded() async {
        await scan?.value
        await removal?.value
    }

    func contains(_ key: String) -> Bool { contains(named: Self.name(key)) }

    func contains(named name: String) -> Bool { entries[name] != nil }

    /// The file of a key, or nil.
    func data(for key: String) async -> Data? { await data(named: Self.name(key)) }

    /// The file of a name, as `name(_:)` or `contentName(_:)` gives it, or nil.
    func data(named name: String) async -> Data? {
        let file = folder.appending(path: name)
        let removal = removal
        let data = await Task.detached(priority: .userInitiated) { () -> Data? in
            await removal?.value
            try? Data(contentsOf: file)
        }.value
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
        if entries[name] != nil { return name }
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
        entries[name] = Entry(size: Int64(data.count))
        writes[name, default: 0] += 1
        total()
        return true
    }

    func clear() {
        entries = [:]
        clears += 1
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
            let keys: [URLResourceKey] = [.fileSizeKey]
            let urls =
                (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys)) ?? []
            var found: [String: Entry] = [:]
            for url in urls {
                let values = try? url.resourceValues(forKeys: Set(keys))
                found[url.lastPathComponent] = Entry(size: Int64(values?.fileSize ?? 0))
            }
            return found
        }.value
        entries = found
        total()
    }

    private func total() {
        bytes = entries.values.reduce(0) { $0 + $1.size }
    }

    /// A key can hold a URL with a query, so the file name is its hash.
    nonisolated static func name(_ key: String) -> String { hex(SHA256.hash(data: Data(key.utf8))) }

    /// The SHA-256 of the bytes themselves.
    nonisolated static func contentName(_ data: Data) -> String { hex(SHA256.hash(data: data)) }

    nonisolated private static func hex(_ digest: SHA256.Digest) -> String {
        digest.map { String(format: "%02x", $0) }.joined()
    }
}
