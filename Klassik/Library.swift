import Foundation
import Observation

/// The whole library of one server, cached on the device. Klassik builds its own index from this copy.
@MainActor @Observable
final class Library {
    private(set) var songs: [Song] = [] {
        didSet { artworkIndex = nil }
    }
    private(set) var classical: [Song] = [] {
        didSet {
            index = WorkIndex(songs: classical)
            otherAlbumCache = nil
        }
    }
    private(set) var index = WorkIndex()
    @ObservationIgnored private var otherAlbumCache: [WorkIndex.Album]?
    /// Positions in `songs` by album key and by cover ID. Cover views read it once per row, so a lookup must not scan
    /// the library.
    @ObservationIgnored private var artworkIndex: [ArtworkKey: [Int]]?
    private(set) var syncedAt: Date?
    private(set) var isSyncing = false
    /// Tracks received so far in the running sync.
    private(set) var received = 0
    private(set) var syncError: String?
    /// What the server reported at the last sync. If it is the same at the next start, nothing changed.
    private var marker: String?

    var filter: ClassicalFilter {
        didSet {
            guard filter != oldValue else { return }
            if let data = try? JSONEncoder().encode(filter) { defaults.set(data, forKey: Self.filterKey) }
            classical = filter.classical(songs)
        }
    }

    /// The albums that the filter keeps out of the index. Built when first read, because few pages need them.
    var otherAlbums: [WorkIndex.Album] {
        if let otherAlbumCache { return otherAlbumCache }
        let classicalKeys = Set(index.albums.flatMap(\.keys))
        let built = WorkIndex.albums(of: songs.filter { !classicalKeys.contains($0.albumKey) })
        otherAlbumCache = built
        return built
    }

    /// An album of the index, else one that the filter keeps out of it.
    func album(_ key: String) -> WorkIndex.Album? {
        index.album(key) ?? otherAlbums.first { $0.keys.contains(key) }
    }

    /// The song first, then every other track of its album or with its cover ID, in library order. Another movement
    /// on the device can hold the album art when the song itself is not on the device.
    func artworkSources(for song: Song) -> [Song] {
        let index = artworkIndex ?? buildArtworkIndex()
        var positions = Set(index[.album(song.albumKey)] ?? [])
        if let cover = song.coverArt { positions.formUnion(index[.cover(cover)] ?? []) }
        return [song] + positions.sorted().map { songs[$0] }.filter { $0.id != song.id }
    }

    private enum ArtworkKey: Hashable {
        case album(String)
        case cover(String)
    }

    private func buildArtworkIndex() -> [ArtworkKey: [Int]] {
        var index: [ArtworkKey: [Int]] = [:]
        for (position, song) in songs.enumerated() {
            index[.album(song.albumKey), default: []].append(position)
            if let cover = song.coverArt { index[.cover(cover), default: []].append(position) }
        }
        artworkIndex = index
        return index
    }

    var albumCount: Int { Set(songs.map(\.albumKey)).count }
    var classicalAlbumCount: Int { Set(classical.map(\.albumKey)).count }

    private var owner: (server: URL, username: String)?
    private let cacheURL: URL
    private let defaults: UserDefaults
    private static let filterKey = "library.filter.rules"
    static let pageSize = 500

    init(
        cacheURL: URL = .applicationSupportDirectory.appending(path: "library.json"), defaults: UserDefaults = .standard
    ) {
        self.cacheURL = cacheURL
        self.defaults = defaults
        filter =
            defaults.data(forKey: Self.filterKey).flatMap { try? JSONDecoder().decode(ClassicalFilter.self, from: $0) }
            ?? ClassicalFilter()
    }

    /// Loads the cache if it belongs to this server and user.
    func load(for credentials: ServerCredentials) async {
        let url = cacheURL
        let cache = await Task.detached { try? LibraryCache.read(from: url) }.value
        guard let cache, cache.server == credentials.url, cache.username == credentials.username, songs.isEmpty else {
            return
        }
        owner = (cache.server, cache.username)
        // An older cache lacks fields that a sync fills, so it syncs even when the server did not change.
        marker = cache.isCurrent ? cache.marker : nil
        show(cache.songs, syncedAt: cache.syncedAt)
    }

    /// Syncs only if the server changed since the last sync. A star by another app does not count as a change.
    func syncIfChanged(with client: SubsonicClient) async {
        guard !songs.isEmpty, let known = marker, let current = try? await client.changeMarker(), current == known
        else { return await sync(with: client) }
    }

    func sync(with client: SubsonicClient) async {
        guard !isSyncing else { return }
        isSyncing = true
        received = 0
        defer { isSyncing = false }
        do {
            // Read before the pages, so that a change during the sync shows at the next start.
            let marker = try? await client.changeMarker()
            let songs = try await Self.fetchAll { offset in
                let page = try await client.songs(offset: offset, count: Self.pageSize)
                self.received += page.count
                return page
            }
            let cache = LibraryCache(
                server: client.credentials.url, username: client.credentials.username, syncedAt: .now, songs: songs,
                marker: marker)
            self.marker = marker
            owner = (client.credentials.url, client.credentials.username)
            show(songs, syncedAt: cache.syncedAt)
            syncError = nil
            let url = cacheURL
            try await Task.detached { try cache.write(to: url) }.value
        } catch {
            syncError = error.localizedDescription
        }
    }

    /// Follows a star or unstar of the server, so the index changes without a new sync.
    func setStarred(_ ids: Set<String>, _ starred: Bool) {
        guard !ids.isEmpty, let owner, let syncedAt else { return }
        var changed = songs
        for index in changed.indices where ids.contains(changed[index].id) {
            changed[index].starred = starred ? ISO8601DateFormatter().string(from: .now) : nil
        }
        saveStars(changed, owner: owner, syncedAt: syncedAt)
    }

    func replaceStars(_ ids: Set<String>) {
        guard let owner, let syncedAt else { return }
        let stamp = ISO8601DateFormatter().string(from: .now)
        var changed = songs
        for index in changed.indices {
            changed[index].starred = ids.contains(changed[index].id) ? (changed[index].starred ?? stamp) : nil
        }
        // An unchanged refresh must not rebuild the index: the rebuild re-renders every page under a tap.
        guard changed.map(\.starred) != songs.map(\.starred) else { return }
        saveStars(changed, owner: owner, syncedAt: syncedAt)
    }

    private func saveStars(_ songs: [Song], owner: (server: URL, username: String), syncedAt: Date) {
        show(songs, syncedAt: syncedAt)
        let cache = LibraryCache(
            server: owner.server, username: owner.username, syncedAt: syncedAt, songs: songs, marker: marker)
        // Star writes must reach disk in the same order as the listener's actions.
        do { try cache.write(to: cacheURL) } catch { syncError = error.localizedDescription }
    }

    func clear() {
        try? FileManager.default.removeItem(at: cacheURL)
        songs = []
        classical = []
        syncedAt = nil
        syncError = nil
    }

    /// Requests pages until a page comes back short.
    static func fetchAll(pageSize: Int = pageSize, page: (Int) async throws -> [Song]) async throws -> [Song] {
        var songs: [Song] = []
        while true {
            let next = try await page(songs.count)
            songs += next
            if next.count < pageSize { return songs }
        }
    }

    private func show(_ songs: [Song], syncedAt: Date) {
        self.songs = songs
        self.syncedAt = syncedAt
        classical = filter.classical(songs)
    }
}

struct LibraryCache: Codable, Sendable {
    /// Goes up when a sync fills a song field that older caches lack.
    static let currentFormat = 3

    var server: URL
    var username: String
    var syncedAt: Date
    var songs: [Song]
    var marker: String?
    var format: Int? = Self.currentFormat

    var isCurrent: Bool { format == Self.currentFormat }

    static func read(from url: URL) throws -> LibraryCache {
        try JSONDecoder().decode(LibraryCache.self, from: Data(contentsOf: url))
    }

    func write(to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(self).write(to: url, options: .atomic)
    }
}

extension Library {
    /// A work and recording as the library holds them now. A queue copy lacks later stars and can lack movements
    /// or other recordings, so favourite state and changes must not read it.
    func current(work: WorkIndex.Work, recording: WorkIndex.Recording) -> (
        work: WorkIndex.Work, recording: WorkIndex.Recording
    ) {
        if let live = index.work(work.id), let found = live.recordings.first(where: { $0.id == recording.id }) {
            return (live, found)
        }
        // An unindexed work keeps its copy, with the stars of the library.
        let stars = Dictionary(songs.map { ($0.id, $0.starred) }, uniquingKeysWith: { first, _ in first })
        var copy = recording
        for position in copy.songs.indices {
            if let starred = stars[copy.songs[position].id] { copy.songs[position].starred = starred }
        }
        return (work, copy)
    }
}
