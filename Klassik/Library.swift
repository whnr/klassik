import Foundation
import Observation

/// The whole library of one server, cached on the device. Klassik builds its own index from this copy.
@MainActor @Observable
final class Library {
    private(set) var songs: [Song] = []
    private(set) var classical: [Song] = [] {
        didSet { index = WorkIndex(songs: classical) }
    }
    private(set) var index = WorkIndex()
    private(set) var syncedAt: Date?
    private(set) var isSyncing = false
    /// Tracks received so far in the running sync.
    private(set) var received = 0
    private(set) var syncError: String?

    var filter: ClassicalFilter {
        didSet {
            guard filter != oldValue else { return }
            if let data = try? JSONEncoder().encode(filter) { defaults.set(data, forKey: Self.filterKey) }
            classical = filter.classical(songs)
        }
    }

    var albumCount: Int { Set(songs.map(\.albumKey)).count }
    var classicalAlbumCount: Int { Set(classical.map(\.albumKey)).count }

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
        show(cache.songs, syncedAt: cache.syncedAt)
    }

    func sync(with client: SubsonicClient) async {
        guard !isSyncing else { return }
        isSyncing = true
        received = 0
        defer { isSyncing = false }
        do {
            let songs = try await Self.fetchAll { offset in
                let page = try await client.songs(offset: offset, count: Self.pageSize)
                self.received += page.count
                return page
            }
            let cache = LibraryCache(
                server: client.credentials.url, username: client.credentials.username, syncedAt: .now, songs: songs)
            show(songs, syncedAt: cache.syncedAt)
            syncError = nil
            let url = cacheURL
            try await Task.detached { try cache.write(to: url) }.value
        } catch {
            syncError = error.localizedDescription
        }
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
    var server: URL
    var username: String
    var syncedAt: Date
    var songs: [Song]

    static func read(from url: URL) throws -> LibraryCache {
        try JSONDecoder().decode(LibraryCache.self, from: Data(contentsOf: url))
    }

    func write(to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(self).write(to: url, options: .atomic)
    }
}
