import Foundation
import Observation

/// Keeps track files on the device in two places. The cache holds what played and drops the oldest files when it
/// is full. A download stays until the listener removes it, and the cache limit does not count it.
@MainActor @Observable
final class TrackStore {
    /// A recording or an album that the listener downloaded.
    struct Download: Codable, Identifiable, Sendable, Hashable {
        var id: String
        var title: String
        var detail: String
        var songIDs: [String]
        var bytes: Int64
        var date: Date
    }

    static let limits: [Int64] = [512, 1024, 2048, 5120, 10240].map { $0 * 1_000_000 }
    static let defaultLimit = limits[2]

    private(set) var downloads: [Download] = []
    /// The tracks that play without the server, downloaded or cached.
    private(set) var offline: Set<String> = []
    private(set) var cacheBytes: Int64 = 0
    /// Share of a running download, by recording ID.
    private(set) var progress: [String: Double] = [:]
    private(set) var failures: [String: String] = [:]

    var cacheLimit: Int64 {
        didSet {
            defaults.set(cacheLimit, forKey: Self.limitKey)
            evict()
        }
    }

    var downloadBytes: Int64 { downloads.reduce(0) { $0 + $1.bytes } }

    private let cacheFolder: URL
    private let downloadFolder: URL
    private let manifestURL: URL
    private let defaults: UserDefaults
    private var tasks: [String: Task<Void, Never>] = [:]
    private static let limitKey = "store.cacheLimit"

    init(
        cacheFolder: URL = .cachesDirectory.appending(path: "tracks"),
        downloadFolder: URL = .applicationSupportDirectory.appending(path: "downloads"),
        defaults: UserDefaults = .standard
    ) {
        self.cacheFolder = cacheFolder
        self.downloadFolder = downloadFolder
        self.manifestURL = downloadFolder.deletingLastPathComponent().appending(path: "downloads.json")
        self.defaults = defaults
        let stored = defaults.object(forKey: Self.limitKey) as? Int64
        cacheLimit = stored ?? Self.defaultLimit
        downloads = (try? JSONDecoder().decode([Download].self, from: Data(contentsOf: manifestURL))) ?? []
        rescan()
    }

    func isOffline(_ song: Song) -> Bool { offline.contains(song.id) }

    func isOffline(_ recording: WorkIndex.Recording) -> Bool {
        !recording.songs.isEmpty && recording.songs.allSatisfy { offline.contains($0.id) }
    }

    func isDownloaded(_ recording: WorkIndex.Recording) -> Bool {
        downloads.contains { $0.id == recording.id }
    }

    /// The local file of a track. A track that is not on the device downloads into the cache first.
    func file(for song: Song, client: SubsonicClient) async throws -> URL {
        let name = Self.fileName(song)
        let kept = downloadFolder.appending(path: name)
        if FileManager.default.fileExists(atPath: kept.path()) { return kept }
        let cached = cacheFolder.appending(path: name)
        if FileManager.default.fileExists(atPath: cached.path()) {
            // The modification date tells the cache which file was played last.
            try? FileManager.default.setAttributes([.modificationDate: Date.now], ofItemAtPath: cached.path())
            return cached
        }
        try await fetch(song, to: cached, client: client)
        rescan()
        evict(keeping: cached)
        return cached
    }

    /// Downloads every track of a recording. It runs in the background; `progress` shows how far it is.
    func download(_ recording: WorkIndex.Recording, title: String, client: SubsonicClient) {
        guard tasks[recording.id] == nil, !isDownloaded(recording) else { return }
        failures[recording.id] = nil
        progress[recording.id] = 0
        tasks[recording.id] = Task {
            var added: [String] = []
            do {
                var bytes: Int64 = 0
                for (index, song) in recording.songs.enumerated() {
                    try Task.checkCancellation()
                    let target = downloadFolder.appending(path: Self.fileName(song))
                    if !FileManager.default.fileExists(atPath: target.path()) {
                        let cached = cacheFolder.appending(path: Self.fileName(song))
                        if FileManager.default.fileExists(atPath: cached.path()) {
                            try FileManager.default.createDirectory(
                                at: downloadFolder, withIntermediateDirectories: true)
                            try FileManager.default.moveItem(at: cached, to: target)
                        } else {
                            try await fetch(song, to: target, client: client)
                        }
                        added.append(song.id)
                    }
                    bytes += Self.size(of: target)
                    progress[recording.id] = Double(index + 1) / Double(recording.songs.count)
                }
                downloads.append(
                    Download(
                        id: recording.id, title: title, detail: recording.performers,
                        songIDs: recording.songs.map(\.id), bytes: bytes, date: .now))
                saveManifest()
            } catch {
                // A part of a recording is of no use offline, so a failed run keeps nothing.
                for id in added { removeFiles(of: id, in: downloadFolder) }
                if !(error is CancellationError) { failures[recording.id] = error.localizedDescription }
            }
            progress[recording.id] = nil
            tasks[recording.id] = nil
            rescan()
        }
    }

    func cancelDownload(_ id: String) {
        tasks[id]?.cancel()
    }

    /// Removes a download. A track that another download also holds stays.
    func remove(_ download: Download) {
        downloads.removeAll { $0.id == download.id }
        let kept = Set(downloads.flatMap(\.songIDs))
        for id in download.songIDs where !kept.contains(id) { removeFiles(of: id, in: downloadFolder) }
        saveManifest()
        rescan()
    }

    func clearCache() {
        try? FileManager.default.removeItem(at: cacheFolder)
        rescan()
    }

    /// Signing out removes everything the account stored.
    func clearAll() {
        for task in tasks.values { task.cancel() }
        downloads = []
        try? FileManager.default.removeItem(at: downloadFolder)
        try? FileManager.default.removeItem(at: manifestURL)
        clearCache()
    }

    /// Reads both folders again. The sets in this object follow the files, not the other way round.
    func rescan() {
        let cached = Self.files(in: cacheFolder)
        let kept = Self.files(in: downloadFolder)
        cacheBytes = cached.reduce(0) { $0 + $1.size }
        offline = Set((cached + kept).map(\.id))
    }

    /// Deletes the least recently played cache files until the cache fits its limit.
    func evict(keeping keep: URL? = nil) {
        var files = Self.files(in: cacheFolder).sorted { $0.date < $1.date }
        var total = files.reduce(0) { $0 + $1.size }
        while total > cacheLimit, let oldest = files.first {
            files.removeFirst()
            if oldest.url == keep { continue }
            try? FileManager.default.removeItem(at: oldest.url)
            total -= oldest.size
        }
        rescan()
    }

    private func fetch(_ song: Song, to target: URL, client: SubsonicClient) async throws {
        let (temporary, response) = try await URLSession.shared.download(from: client.streamURL(songID: song.id))
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw SubsonicError.http(status: http.statusCode)
        }
        try FileManager.default.createDirectory(
            at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: target)
        try FileManager.default.moveItem(at: temporary, to: target)
    }

    private func saveManifest() {
        try? FileManager.default.createDirectory(at: downloadFolder, withIntermediateDirectories: true)
        // A download can load again from the server, so it does not belong in the device backup.
        var folder = downloadFolder
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? folder.setResourceValues(values)
        if let data = try? JSONEncoder().encode(downloads) { try? data.write(to: manifestURL, options: .atomic) }
    }

    private func removeFiles(of songID: String, in folder: URL) {
        for file in Self.files(in: folder) where file.id == songID { try? FileManager.default.removeItem(at: file.url) }
    }

    private struct StoredFile {
        var url: URL
        var id: String
        var size: Int64
        var date: Date
    }

    private static func files(in folder: URL) -> [StoredFile] {
        let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey]
        let urls = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys)) ?? []
        return urls.map { url in
            let values = try? url.resourceValues(forKeys: Set(keys))
            return StoredFile(
                url: url, id: url.deletingPathExtension().lastPathComponent, size: Int64(values?.fileSize ?? 0),
                date: values?.contentModificationDate ?? .distantPast)
        }
    }

    private static func size(of url: URL) -> Int64 {
        Int64((try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
    }

    private static func fileName(_ song: Song) -> String { "\(song.id).\(song.suffix ?? "mp3")" }
}
