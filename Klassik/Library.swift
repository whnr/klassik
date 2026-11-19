import Foundation
import Observation

/// The whole library of one server, cached on the device. Klassik builds its own index from this copy.
@MainActor @Observable
final class Library {
    private(set) var songs: [Song] = []
    private(set) var classical: [Song] = [] {
        didSet {
            index = WorkIndex(songs: classical)
            otherAlbumCache = nil
            searchCache = nil
            classicalChanged?()
        }
    }
    /// The covers follow the classical part of the library (ADR 0059).
    @ObservationIgnored var classicalChanged: (@MainActor () -> Void)?
    private(set) var index = WorkIndex()
    /// The songs with a star: the server's stars with the changes that wait over them. A star change sets only this
    /// and `songs`, because a rebuild of the index holds the main actor under the tap (ADR 0052). The songs inside
    /// the index keep the stars of the last rebuild, so favourite state reads this set.
    private(set) var starredSongs: Set<String> = []
    @ObservationIgnored private var otherAlbumCache: [WorkIndex.Album]?
    @ObservationIgnored private var searchCache: Search?
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

    /// The search over the index. Built when first read, and again after the index changes.
    var search: Search {
        // Reading the index lets a view that searches follow a rebuild.
        let index = index
        if let searchCache { return searchCache }
        let built = Search(index: index)
        searchCache = built
        return built
    }

    /// An album of the index, else one that the filter keeps out of it.
    func album(_ key: String) -> WorkIndex.Album? {
        index.album(key) ?? otherAlbums.first { $0.keys.contains(key) }
    }

    var albumCount: Int { Set(songs.map(\.albumKey)).count }
    var classicalAlbumCount: Int { Set(classical.map(\.albumKey)).count }

    private var owner: (server: URL, username: String)?
    private let cacheURL: URL
    private let defaults: UserDefaults
    @ObservationIgnored private(set) var cacheWrite: Task<Void, Never>?
    @ObservationIgnored private var pendingStars: [String: Bool] = [:]
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
            self.marker = marker
            owner = (client.credentials.url, client.credentials.username)
            let syncedAt = Date.now
            show(songs, syncedAt: syncedAt)
            let cache = LibraryCache(
                server: client.credentials.url, username: client.credentials.username, syncedAt: syncedAt,
                songs: self.songs, marker: marker)
            syncError = nil
            await enqueueCache(cache).value
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
            let isSet = pendingStars[changed[index].id] ?? ids.contains(changed[index].id)
            changed[index].starred = isSet ? (changed[index].starred ?? stamp) : nil
        }
        // An unchanged refresh must not rebuild the index: the rebuild re-renders every page under a tap.
        guard changed.map(\.starred) != songs.map(\.starred) else { return }
        saveStars(changed, owner: owner, syncedAt: syncedAt)
    }

    /// Pending device choices take priority over every server snapshot (ADR 0052).
    func project(_ changes: [DeviceStore.FavouriteChange]) {
        pendingStars = [:]
        for change in changes where change.album == nil {
            for id in change.songs { pendingStars[id] = change.isSet }
        }
        replaceStars(Set(songs.filter { $0.starred != nil }.map(\.id)))
    }

    private func saveStars(_ songs: [Song], owner: (server: URL, username: String), syncedAt: Date) {
        self.songs = songs
        starredSongs = Self.starred(songs)
        let cache = LibraryCache(
            server: owner.server, username: owner.username, syncedAt: syncedAt, songs: self.songs, marker: marker)
        enqueueCache(cache)
    }

    /// Cache writes and deletion follow the listener's actions without blocking the main actor.
    @discardableResult private func enqueueCache(_ cache: LibraryCache?) -> Task<Void, Never> {
        let previous = cacheWrite
        let url = cacheURL
        let task = Task {
            await previous?.value
            let failure = await Task.detached {
                do {
                    if let cache {
                        try cache.write(to: url)
                    } else if FileManager.default.fileExists(atPath: url.path) {
                        try FileManager.default.removeItem(at: url)
                    }
                    return nil as String?
                } catch { return error.localizedDescription }
            }.value
            if let failure { syncError = failure }
        }
        cacheWrite = task
        return task
    }

    func clear() {
        enqueueCache(nil)
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
        var songs = songs
        let stamp = ISO8601DateFormatter().string(from: .now)
        for index in songs.indices {
            if let isSet = pendingStars[songs[index].id] {
                songs[index].starred = isSet ? (songs[index].starred ?? stamp) : nil
            }
        }
        self.songs = songs
        starredSongs = Self.starred(songs)
        self.syncedAt = syncedAt
        classical = filter.classical(songs)
    }

    private static func starred(_ songs: [Song]) -> Set<String> {
        Set(songs.lazy.filter { $0.starred != nil }.map(\.id))
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
    /// A work and recording as the library holds them now. A queue copy can lack movements or other recordings, so
    /// favourite changes must not read it.
    func current(work: WorkIndex.Work, recording: WorkIndex.Recording) -> (
        work: WorkIndex.Work, recording: WorkIndex.Recording
    ) {
        if let live = index.work(work.id), let found = live.recordings.first(where: { $0.id == recording.id }) {
            return (live, found)
        }
        return (work, recording)
    }

    /// A favourite recording has a star on every track.
    func isFavourite(_ recording: WorkIndex.Recording) -> Bool {
        !recording.songs.isEmpty && recording.songs.allSatisfy { starredSongs.contains($0.id) }
    }
}
