import Foundation
import Observation

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
    /// A tap never waits for the server (ADR 0052), so no favourite control is ever disabled.
    let isSaving = false
    /// A failure of the device file. Server failures never show here: they set `serverTrouble`.
    var error: String?
    private(set) var loadError: String?
    private(set) var refreshError: String?
    /// Why changes wait, after the last call to the server. It is nil when the server took every change.
    private(set) var serverTrouble: ServerTrouble?
    @ObservationIgnored private var syncTask: Task<Void, Never>?

    init(library: Library, store: DeviceStore? = nil, server: (any FavouriteServer)? = nil) {
        self.library = library
        self.store = store
        self.server = server
        do { data = try store?.load() ?? DeviceStore.Data() } catch { loadError = error.localizedDescription }
        albums = data.favouriteAlbums
        library.project(data.pendingFavourites)
    }

    func isFavourite(_ work: WorkIndex.Work) -> Bool { data.favouriteWorks.contains(work.id) }

    func isFavourite(_ recording: WorkIndex.Recording, of work: WorkIndex.Work) -> Bool {
        library.isFavourite(library.current(work: work, recording: recording).recording)
    }

    func rows(of work: WorkIndex.Work) -> [Row] {
        let live = library.index.work(work.id) ?? work
        let order = data.recordingOrder[work.id] ?? []
        return live.recordings.map { recording in
            var reason: String?
            let isFavourite = library.isFavourite(recording)
            if !isFavourite {
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
            return Row(recording: recording, reason: reason, isFavourite: isFavourite)
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

    /// Changes the favourite of a recording at once: its mark and its place among the favourites. The device keeps
    /// the change before the server hears of it, and a failed server call never takes it back (ADR 0052). The
    /// returned call sends it.
    func begin(_ recording: WorkIndex.Recording, of work: WorkIndex.Work) -> (@MainActor () async -> Void)? {
        guard server != nil else { return nil }
        guard loadError == nil else {
            error = loadError
            return nil
        }
        let live = library.current(work: work, recording: recording).recording
        let ids = live.songs.map(\.id)
        guard !ids.isEmpty else { return nil }
        let isSet = !library.isFavourite(live)
        var order = rows(of: work).filter(\.isFavourite).map(\.id)
        order.removeAll { $0 == live.id }
        if isSet { order.append(live.id) }
        var changed = data
        changed.recordingOrder[work.id] = order
        let change = DeviceStore.FavouriteChange(songs: ids, isSet: isSet)
        changed.queue(change)
        guard save(changed) else { return nil }
        return { [self] in await synchronize() }
    }

    func isFavourite(album id: String) -> Bool { albums.contains(id) }

    /// A composer or performer is a favourite when the server stars the artist of that name (ADR 0013).
    func isFavourite(person name: String) -> Bool { artists.contains { $0.name == name } }

    func toggle(album id: String) async {
        await begin(album: id)?()
    }

    /// Changes the favourite of an album at once. It is a star on the album, not on its tracks (ADR 0013). The
    /// device keeps it like a recording favourite (ADR 0052). The returned call sends it.
    func begin(album id: String) -> (@MainActor () async -> Void)? {
        guard server != nil else { return nil }
        guard loadError == nil else {
            error = loadError
            return nil
        }
        let isSet = !albums.contains(id)
        var changed = data
        if isSet { changed.favouriteAlbums.insert(id) } else { changed.favouriteAlbums.remove(id) }
        let change = DeviceStore.FavouriteChange(album: id, isSet: isSet)
        changed.queue(change)
        guard save(changed) else { return nil }
        albums = changed.favouriteAlbums
        return { [self] in await synchronize() }
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

    /// Sends the changes that wait, then reads all stars. The server is right, except for a change that still waits.
    func refresh() async {
        await serially {
            _ = await self.sendQueue()
            await self.readStars()
        }
    }

    /// Sends the changes that wait. A tap calls it, and so does the app when the connection comes back. A failure
    /// shows no notice: the changes wait, and `serverTrouble` says why (ADR 0058).
    func synchronize() async {
        await serially { _ = await self.sendQueue() }
    }

    /// One run at a time, so that a star read cannot overtake a newer change of the listener.
    private func serially(_ run: @escaping @MainActor () async -> Void) async {
        let previous = syncTask
        let task = Task { @MainActor in
            await previous?.value
            await run()
        }
        syncTask = task
        await task.value
    }

    /// A refused change waits while other targets proceed. A connection failure also applies to all unreached changes.
    private func sendQueue() async -> [UUID: any Error] {
        guard loadError == nil, let server else { return [:] }
        var failures: [UUID: any Error] = [:]
        defer { serverTrouble = ServerTrouble(Array(failures.values)) }
        queue: for change in data.pendingFavourites {
            // A later tap on the same target replaces a change while an earlier one is on its way.
            guard data.pendingFavourites.contains(where: { $0.id == change.id }) else { continue }
            do {
                switch (change.album, change.isSet) {
                case (let album?, true): try await server.starAlbum(album)
                case (let album?, false): try await server.unstarAlbum(album)
                case (nil, true): try await server.star(change.songs)
                case (nil, false): try await server.unstar(change.songs)
                }
                var changed = data
                changed.pendingFavourites.removeAll { $0.id == change.id }
                save(changed, quietly: true)
            } catch {
                failures[change.id] = error
                if error is URLError {
                    for pending in data.pendingFavourites where failures[pending.id] == nil {
                        failures[pending.id] = error
                    }
                    break queue
                }
            }
        }
        return failures
    }

    private func readStars() async {
        guard let server else { return }
        do {
            let stars = try await server.getStarred()
            refreshError = nil
            artists = stars.artist ?? []
            var songs = Set((stars.song ?? []).map(\.id))
            var albums = Set((stars.album ?? []).map(\.id))
            for change in data.pendingFavourites {
                switch (change.album, change.isSet) {
                case (let album?, true): albums.insert(album)
                case (let album?, false): albums.remove(album)
                case (nil, true): songs.formUnion(change.songs)
                case (nil, false): songs.subtract(change.songs)
                }
            }
            self.albums = albums
            library.replaceStars(songs)
            var changed = data
            changed.favouriteAlbums = albums
            for work in library.index.composers.flatMap(\.works) {
                changed.recordingOrder[work.id] = rows(of: work).filter(\.isFavourite).map(\.id)
            }
            if loadError == nil { save(changed, quietly: true) }
        } catch { refreshError = error.localizedDescription }
    }

    /// Writes the device file. A failure tells the listener only when a tap caused the write.
    @discardableResult
    private func save(_ changed: DeviceStore.Data, quietly: Bool = false) -> Bool {
        guard loadError == nil else {
            if !quietly { error = loadError }
            return false
        }
        guard changed != data else { return true }
        do {
            try store?.save(changed)
            data = changed
            library.project(changed.pendingFavourites)
            return true
        } catch {
            if !quietly { self.error = error.localizedDescription }
            return false
        }
    }
}

#if DEBUG
    struct OfflineFavourites: FavouriteServer {
        let client: SubsonicClient

        func star(_ ids: [String]) async throws { throw URLError(.notConnectedToInternet) }
        func unstar(_ ids: [String]) async throws { throw URLError(.notConnectedToInternet) }
        func starAlbum(_ id: String) async throws { throw URLError(.notConnectedToInternet) }
        func unstarAlbum(_ id: String) async throws { throw URLError(.notConnectedToInternet) }
        func getStarred() async throws -> Starred { try await client.getStarred() }
    }
#endif
