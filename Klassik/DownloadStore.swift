import Foundation
import Observation

/// How much of a set of tracks sits on the device.
enum DownloadState: Equatable, Sendable {
    case none
    case partial(done: Int, total: Int)
    case downloading(done: Int, total: Int)
    case complete

    /// A track can appear twice, in a recording and in its album, so ids count once.
    init(songIDs: [String], downloaded: Set<String>, pending: Set<String>) {
        let ids = Set(songIDs)
        let done = ids.intersection(downloaded).count
        if ids.isEmpty {
            self = .none
        } else if done == ids.count {
            self = .complete
        } else if !ids.isDisjoint(with: pending) {
            self = .downloading(done: done, total: ids.count)
        } else if done > 0 {
            self = .partial(done: done, total: ids.count)
        } else {
            self = .none
        }
    }

    var label: String {
        switch self {
        case .none: "Not downloaded"
        case .partial(let done, let total): "\(done) of \(total) tracks downloaded"
        case .downloading(let done, let total): "Downloading, \(done) of \(total) tracks"
        case .complete: "Downloaded"
        }
    }

    var isDownloading: Bool {
        if case .downloading = self { return true }
        return false
    }
}

/// Tracks that stay on the device for listening without the server.
/// They live in Application Support, because the system may empty the caches folder.
@MainActor @Observable
final class DownloadStore {
    /// Returns a temporary file that holds the original track.
    typealias Fetch = @Sendable (Song, SubsonicClient) async throws -> URL

    /// File name by song id.
    private(set) var files: [String: String]
    /// Tracks that wait for download or load now.
    private(set) var pending: Set<String> = []
    private(set) var error: String?
    var downloaded: Set<String> { Set(files.keys) }

    let folder: URL
    private let cache: TrackCache
    private let fetch: Fetch
    private var queue: [Song] = []
    private var worker: Task<Void, Never>?

    init(
        folder: URL = URL.applicationSupportDirectory.appending(path: "downloads"),
        cache: TrackCache,
        fetch: @escaping Fetch = DownloadStore.fetchTrack
    ) {
        self.folder = folder
        self.cache = cache
        self.fetch = fetch
        var found: [String: String] = [:]
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path())) ?? []
        for name in names where !name.hasPrefix(".") {
            found[URL(fileURLWithPath: name).deletingPathExtension().lastPathComponent] = name
        }
        files = found
    }

    nonisolated static func fileName(for song: Song) -> String {
        "\(song.id).\(song.suffix ?? "mp3")"
    }

    func localURL(for song: Song) -> URL? {
        files[song.id].map { folder.appending(path: $0) }
    }

    func state(of songs: [Song]) -> DownloadState {
        DownloadState(songIDs: songs.map(\.id), downloaded: downloaded, pending: pending)
    }

    /// Loads the tracks one after the other, so a slow connection does not spread over many files.
    func download(_ songs: [Song], client: SubsonicClient) {
        error = nil
        for song in songs where files[song.id] == nil && !pending.contains(song.id) {
            pending.insert(song.id)
            queue.append(song)
        }
        guard worker == nil, !queue.isEmpty else { return }
        worker = Task { await run(client: client) }
    }

    /// Stops the tracks that have not finished. Finished tracks stay.
    func cancel(_ songs: [Song]) {
        let ids = Set(songs.map(\.id))
        queue.removeAll { ids.contains($0.id) }
        pending.subtract(ids)
    }

    func remove(_ songs: [Song]) {
        cancel(songs)
        for song in songs {
            guard let name = files.removeValue(forKey: song.id) else { continue }
            try? FileManager.default.removeItem(at: folder.appending(path: name))
        }
    }

    /// Bytes of all downloaded tracks, also those that no recording in the library claims.
    var totalSize: Int64 {
        files.values.reduce(0) { total, name in
            let size = try? folder.appending(path: name).resourceValues(forKeys: [.fileSizeKey]).fileSize
            return total + Int64(size ?? 0)
        }
    }

    /// Bytes on disk for the downloaded tracks among these songs.
    func size(of songs: [Song]) -> Int64 {
        songs.reduce(0) { total, song in
            guard let url = localURL(for: song) else { return total }
            return total + Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
    }

    func removeAll() {
        worker?.cancel()
        worker = nil
        queue = []
        pending = []
        files = [:]
        error = nil
        try? FileManager.default.removeItem(at: folder)
    }

    private func run(client: SubsonicClient) async {
        while !queue.isEmpty {
            let song = queue.removeFirst()
            do {
                // A cached track moves into the downloads, so it needs no second download.
                let temporary: URL
                if let cached = cache.take(song) {
                    temporary = cached
                } else {
                    temporary = try await fetch(song, client)
                }
                if Task.isCancelled { return }
                // The person may have cancelled this track while it loaded.
                if pending.contains(song.id) {
                    try store(temporary, for: song)
                } else {
                    try? FileManager.default.removeItem(at: temporary)
                }
            } catch {
                if Task.isCancelled { return }
                self.error = error.localizedDescription
                queue = []
                pending = []
            }
            pending.remove(song.id)
        }
        worker = nil
    }

    private func store(_ temporary: URL, for song: Song) throws {
        var folder = folder
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        // The tracks can be loaded again, so they do not belong in the backup.
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? folder.setResourceValues(values)
        let name = Self.fileName(for: song)
        let target = folder.appending(path: name)
        try? FileManager.default.removeItem(at: target)
        try FileManager.default.moveItem(at: temporary, to: target)
        files[song.id] = name
    }

    /// `format=raw` keeps the MP3 gapless header, as for streaming.
    nonisolated static func fetchTrack(_ song: Song, client: SubsonicClient) async throws -> URL {
        let (temporary, response) = try await client.session.download(from: client.streamURL(songID: song.id))
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw SubsonicError.http(status: http.statusCode)
        }
        return temporary
    }
}
