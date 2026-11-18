import Foundation
import Observation

#if canImport(Network)
    import Network
#endif

protocol FavouriteServer: Sendable {
    func star(_ ids: [String]) async throws
    func unstar(_ ids: [String]) async throws
    func starAlbum(_ id: String) async throws
    func unstarAlbum(_ id: String) async throws
    func getStarred() async throws -> Starred
}

struct Starred: Decodable, Sendable {
    var song: [Song]?
    var artist: [Song.Artist]?
    var album: [Album]?
}

extension SubsonicClient: FavouriteServer {
    func getStarred() async throws -> Starred {
        guard let stars = try await get("getStarred2").starred2 else { throw SubsonicError.notSubsonic }
        return stars
    }
}

/// Owns favourite state and every choice of a work's reference recording (ADR 0013).
@MainActor @Observable
final class RecordingOrder {
    struct Row: Identifiable {
        var recording: WorkIndex.Recording
        var reason: String?
        var isFavourite: Bool
        var id: String { recording.id }
    }

    struct Favourite: Identifiable {
        var work: WorkIndex.Work
        var recording: WorkIndex.Recording
        var id: String { recording.id }
    }

    var favouriteWorks: [WorkIndex.Work] {
        library.index.composers.flatMap(\.works).filter { isFavourite($0) }
    }

    var favouriteRecordings: [Favourite] {
        library.index.composers.flatMap(\.works).flatMap { work in
            rows(of: work).filter(\.isFavourite).map { Favourite(work: work, recording: $0.recording) }
        }
    }

    var favouriteCount: Int { favouriteWorks.count + favouriteRecordings.count }

    private let library: Library
    private let store: DeviceStore?
    private let server: (any FavouriteServer)?
    private var data = DeviceStore.Data()
    private var artists: [Song.Artist] = []
    private var albums: Set<String> = []
    private(set) var isSaving = false
    var error: String?
    private(set) var loadError: String?
    private(set) var refreshError: String?
    @ObservationIgnored private var syncTask: Task<Void, Never>?
    #if canImport(Network)
        @ObservationIgnored private let monitor = NWPathMonitor()
    #endif

    init(
        library: Library, store: DeviceStore? = nil, server: (any FavouriteServer)? = nil,
        monitorConnection: Bool = true
    ) {
        self.library = library
        self.store = store
        self.server = server
        do { data = try store?.load() ?? DeviceStore.Data() } catch { loadError = error.localizedDescription }
        albums = data.favouriteAlbums
        #if canImport(Network)
            guard monitorConnection, server != nil else { return }
            monitor.pathUpdateHandler = { [weak self] path in
                guard path.status == .satisfied else { return }
                Task { @MainActor [weak self] in await self?.synchronize() }
            }
            monitor.start(queue: DispatchQueue(label: "de.whnr.klassik.favourites"))
        #endif
    }

    func isFavourite(_ work: WorkIndex.Work) -> Bool { data.favouriteWorks.contains(work.id) }

    func isFavourite(_ recording: WorkIndex.Recording, of work: WorkIndex.Work) -> Bool {
        let live = library.current(work: work, recording: recording).recording
        return !live.songs.isEmpty
            && live.songs.allSatisfy { song in
                data.pendingFavourites.last { $0.songs.contains(song.id) }?.isSet ?? data.trackFavourites[song.id]
                    ?? (song.starred != nil)
            }
    }

    func rows(of work: WorkIndex.Work) -> [Row] {
        let live = library.index.work(work.id) ?? work
        let order = data.recordingOrder[work.id] ?? []
        return live.recordings.map { recording in
            var reason: String?
            let isSet = isFavourite(recording, of: live)
            if !isSet {
                let names = recording.performerNames.filter { name in artists.contains { $0.name == name } }
                let ids = recording.songs.flatMap { $0.contributors ?? [] }
                    .filter {
                        ["conductor", "performer"].contains($0.role.trimmingCharacters(in: .whitespaces).lowercased())
                    }
                    .map(\.artist.id)
                let performer = artists.first { ids.contains($0.id) }?.name ?? names.first
                if let performer {
                    reason = "Favourite performer: \(performer)"
                } else if recording.songs.contains(where: { $0.albumId.map(albums.contains) == true }) {
                    reason = "Favourite album: \(recording.album)"
                }
            }
            return Row(recording: recording, reason: reason, isFavourite: isSet)
        }.sorted { left, right in
            func tier(_ row: Row) -> Int {
                if row.isFavourite { return 0 }
                if row.reason?.hasPrefix("Favourite performer:") == true { return 1 }
                return row.reason == nil ? 3 : 2
            }
            let a = tier(left)
            let b = tier(right)
            if a != b { return a < b }
            if a == 0 {
                let x = order.firstIndex(of: left.id) ?? .max
                let y = order.firstIndex(of: right.id) ?? .max
                if x != y { return x < y }
            }
            let x = left.recording.year ?? Int.min
            let y = right.recording.year ?? Int.min
            if x != y { return x > y }
            return left.id < right.id
        }
    }

    func reference(of work: WorkIndex.Work) -> WorkIndex.Recording? { rows(of: work).first?.recording }

    func toggle(_ work: WorkIndex.Work) {
        var changed = data
        if !changed.favouriteWorks.insert(work.id).inserted { changed.favouriteWorks.remove(work.id) }
        save(changed)
    }

    func toggle(_ recording: WorkIndex.Recording, of work: WorkIndex.Work) async {
        await begin(recording, of: work)?()
    }

    /// Saves the mark and its order before the server call, so a failed sync cannot undo a tap.
    func begin(_ recording: WorkIndex.Recording, of work: WorkIndex.Work) -> (@MainActor () async -> Void)? {
        guard loadError == nil else {
            error = loadError
            return nil
        }
        let live = library.current(work: work, recording: recording).recording
        let ids = live.songs.map(\.id)
        guard !ids.isEmpty else { return nil }
        let isSet = !isFavourite(live, of: work)
        var changed = data
        var order = rows(of: work).filter(\.isFavourite).map(\.id)
        order.removeAll { $0 == live.id }
        if isSet { order.append(live.id) }
        changed.recordingOrder[work.id] = order
        for id in ids { changed.trackFavourites[id] = isSet }
        changed.pendingFavourites.append(.init(songs: ids, isSet: isSet))
        guard save(changed) else { return nil }
        library.setStarred(Set(ids), isSet)
        return { [self] in await synchronize(notify: true) }
    }

    func isFavourite(album id: String) -> Bool { albums.contains(id) }

    func toggle(album id: String) async {
        await begin(album: id)?()
    }

    /// Album stars stay separate from track stars, including while they wait for the server.
    func begin(album id: String) -> (@MainActor () async -> Void)? {
        let isSet = !albums.contains(id)
        var changed = data
        if isSet { changed.favouriteAlbums.insert(id) } else { changed.favouriteAlbums.remove(id) }
        changed.pendingFavourites.append(.init(album: id, isSet: isSet))
        guard save(changed) else { return nil }
        albums = data.favouriteAlbums
        return { [self] in await synchronize(notify: true) }
    }

    /// Only favourites move. Other rows keep the server-derived priority.
    func moveFavourites(of work: WorkIndex.Work, from source: IndexSet, to destination: Int) {
        var ids = rows(of: work).filter(\.isFavourite).map(\.id)
        guard source.allSatisfy({ ids.indices.contains($0) }), destination >= 0, destination <= ids.count else {
            return
        }
        let moving = source.sorted().map { ids[$0] }
        for index in source.sorted(by: >) { ids.remove(at: index) }
        ids.insert(contentsOf: moving, at: destination - source.filter { $0 < destination }.count)
        var changed = data
        changed.recordingOrder[work.id] = ids
        save(changed)
    }

    func refresh() async {
        await synchronize(refresh: true)
    }

    /// Serial requests prevent an old server snapshot from replacing a newer local change.
    private func synchronize(notify: Bool = false, refresh: Bool = false) async {
        let previous = syncTask
        let task = Task { @MainActor [self] in
            await previous?.value
            await sendPending(notify: notify)
            if refresh { await readStars() }
        }
        syncTask = task
        await task.value
    }

    private func sendPending(notify: Bool) async {
        guard loadError == nil, let server else { return }
        while let change = data.pendingFavourites.first {
            do {
                if let album = change.album {
                    if change.isSet { try await server.starAlbum(album) } else { try await server.unstarAlbum(album) }
                } else {
                    if change.isSet {
                        try await server.star(change.songs)
                    } else {
                        try await server.unstar(change.songs)
                    }
                }
                var changed = data
                changed.pendingFavourites.removeAll { $0.id == change.id }
                guard save(changed) else { return }
            } catch {
                if notify {
                    self.error =
                        error is URLError
                        ? "No internet connection. This syncs when you are back online."
                        : "Your favourite is saved on this device. Server sync failed: \(error.localizedDescription)"
                }
                return
            }
        }
    }

    private func readStars() async {
        guard let server else { return }
        do {
            let stars = try await server.getStarred()
            refreshError = nil
            artists = stars.artist ?? []
            var songIDs = Set((stars.song ?? []).map(\.id))
            var albumIDs = Set((stars.album ?? []).map(\.id))
            for change in data.pendingFavourites {
                if let album = change.album {
                    if change.isSet { albumIDs.insert(album) } else { albumIDs.remove(album) }
                } else if change.isSet {
                    songIDs.formUnion(change.songs)
                } else {
                    songIDs.subtract(change.songs)
                }
            }
            albums = albumIDs
            library.replaceStars(songIDs)
            var changed = data
            changed.favouriteAlbums = albumIDs
            changed.trackFavourites = Dictionary(
                library.songs.map { ($0.id, songIDs.contains($0.id)) }, uniquingKeysWith: { first, _ in first })
            guard loadError == nil, save(changed) else { return }
            for work in library.index.composers.flatMap(\.works) {
                changed.recordingOrder[work.id] = rows(of: work).filter(\.isFavourite).map(\.id)
            }
            save(changed)
        } catch { refreshError = error.localizedDescription }
    }

    @discardableResult
    private func save(_ changed: DeviceStore.Data) -> Bool {
        guard loadError == nil else {
            error = loadError
            return false
        }
        guard changed != data else { return true }
        do {
            try store?.save(changed)
            data = changed
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }

    deinit {
        #if canImport(Network)
            monitor.cancel()
        #endif
    }
}

#if DEBUG
    /// The UI walk keeps real library reads while favourite writes have no connection.
    struct OfflineFavouriteServer: FavouriteServer {
        let client: SubsonicClient

        func star(_ ids: [String]) async throws { throw URLError(.notConnectedToInternet) }
        func unstar(_ ids: [String]) async throws { throw URLError(.notConnectedToInternet) }
        func starAlbum(_ id: String) async throws { throw URLError(.notConnectedToInternet) }
        func unstarAlbum(_ id: String) async throws { throw URLError(.notConnectedToInternet) }
        func getStarred() async throws -> Starred { try await client.getStarred() }
    }
#endif
