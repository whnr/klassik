import Foundation
import Observation

protocol FavouriteServer: Sendable {
    func star(_ ids: [String]) async throws
    func unstar(_ ids: [String]) async throws
    func starAlbum(_ id: String) async throws
    func unstarAlbum(_ id: String) async throws
    func starArtist(_ id: String) async throws
    func unstarArtist(_ id: String) async throws
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

    var favouriteAlbums: [WorkIndex.Album] {
        library.index.albums.filter { $0.tracks.first?.albumId.map(albums.contains) == true }
    }

    var favouriteComposers: [WorkIndex.Composer] {
        library.index.composers.filter { isFavourite(person: $0.name) }
    }

    var favouritePerformers: [WorkIndex.Performer] {
        library.index.performers.filter { isFavourite(person: $0.name) }
    }

    var favouriteCount: Int {
        favouriteWorks.count + favouriteRecordings.count + favouriteAlbums.count
            + favouriteComposers.count + favouritePerformers.count
    }

    var pendingChanges: [DeviceStore.FavouriteChange] { data.pendingFavourites }

    func title(of change: DeviceStore.FavouriteChange) -> String {
        if let artist = change.artist { return artist.name }
        if let album = change.album {
            return library.index.albums.first { $0.tracks.first?.albumId == album }?.title ?? album
        }
        return change.songs.map { id in library.songs.first { $0.id == id }?.title ?? id }.joined(separator: ", ")
    }

    private let library: Library
    private let file: ListenerFile
    private let server: (any FavouriteServer)?
    private var data: DeviceStore.Data { file.data }
    private var artists: [Song.Artist] = []
    private var albums: Set<String> = []
    /// A tap never waits for the server (ADR 0052), so no favourite control is ever disabled.
    let isSaving = false
    /// A failure of the device file. Server failures never show here: they set `serverTrouble`.
    var error: String?
    var loadError: String? { file.loadError }
    private(set) var refreshError: String?
    /// Why changes wait, after the last call to the server. It is nil when the server took every change.
    private(set) var serverTrouble: ServerTrouble?
    @ObservationIgnored private var syncTask: Task<Void, Never>?

    convenience init(library: Library, store: DeviceStore? = nil, server: (any FavouriteServer)? = nil) {
        self.init(library: library, file: ListenerFile(store: store), server: server)
    }

    init(library: Library, file: ListenerFile, server: (any FavouriteServer)? = nil) {
        self.library = library
        self.file = file
        self.server = server
        albums = data.favouriteAlbums
        artists = data.favouriteArtists
        library.project(data.pendingFavourites)
    }

    func isFavourite(_ work: WorkIndex.Work) -> Bool { data.favouriteWorks.contains(work.id) }

    func isFavourite(_ recording: WorkIndex.Recording, of work: WorkIndex.Work) -> Bool {
        library.isFavourite(library.current(work: work, recording: recording).recording)
    }

    func rows(of work: WorkIndex.Work) -> [Row] {
        let live = library.index.work(work.id) ?? work
        let position = Dictionary(
            (data.recordingOrder[work.id] ?? []).enumerated().map { ($0.element, $0.offset) },
            uniquingKeysWith: { first, _ in first })
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
            // A row the listener placed stands where the listener put it, ahead of rows that no order names.
            switch (position[left.id], position[right.id]) {
            case (let x?, let y?): return x < y
            case (_?, nil): return true
            case (nil, _?): return false
            case (nil, nil): break
            }
            func tier(_ row: Row) -> Int {
                if row.isFavourite { return 0 }
                if row.reason?.hasPrefix("Favourite performer:") == true { return 1 }
                return row.reason == nil ? 3 : 2
            }
            let a = tier(left)
            let b = tier(right)
            if a != b { return a < b }
            let x = left.recording.year ?? Int.min
            let y = right.recording.year ?? Int.min
            if x != y { return x > y }
            return left.id < right.id
        }
    }

    func reference(of work: WorkIndex.Work) -> WorkIndex.Recording? { rows(of: work).first?.recording }

    /// True once the listener has placed a row that is no favourite. The stored order then names the whole list.
    /// Until then it names the favourites only, and the other tiers keep their server-derived order.
    private func isPlaced(_ work: WorkIndex.Work) -> Bool {
        let named = Set(data.recordingOrder[work.id] ?? [])
        return rows(of: work).contains { !$0.isFavourite && named.contains($0.id) }
    }

    private func orderToKeep(of work: WorkIndex.Work, placed: Bool) -> [String] {
        let rows = rows(of: work)
        return (placed ? rows : rows.filter(\.isFavourite)).map(\.id)
    }

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
        let placed = isPlaced(work)
        let favourites = Set(rows(of: work).filter(\.isFavourite).map(\.id))
        var order = orderToKeep(of: work, placed: placed)
        // A listener who placed rows keeps an unstarred row where it stands.
        if isSet || !placed { order.removeAll { $0 == live.id } }
        if isSet { order.insert(live.id, at: order.firstIndex { !favourites.contains($0) } ?? order.count) }
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

    /// A person can be starred only through an ID supplied by the server, never a Wikidata ID.
    func artist(named name: String) -> Song.Artist? {
        library.index.artists[name]
            ?? artists.first { $0.name == name && !$0.id.isEmpty }
    }

    func begin(person name: String) -> (@MainActor () async -> Void)? {
        guard server != nil, let artist = artist(named: name) else { return nil }
        guard loadError == nil else {
            error = loadError
            return nil
        }
        let isSet = !isFavourite(person: name)
        var changed = data
        changed.favouriteArtists.removeAll { $0.id == artist.id }
        if isSet { changed.favouriteArtists.append(artist) }
        changed.queue(DeviceStore.FavouriteChange(artist: artist, isSet: isSet))
        guard save(changed) else { return nil }
        artists = changed.favouriteArtists
        return { [self] in await synchronize() }
    }

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

    /// Any row moves, favourite or not. The device keeps the whole list at once and never waits for the server.
    func move(of work: WorkIndex.Work, from source: IndexSet, to destination: Int) {
        var ids = rows(of: work).map(\.id)
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

    /// A dragged row takes the place of the row it drops on.
    func move(_ id: String, of work: WorkIndex.Work, onto target: String) {
        let ids = rows(of: work).map(\.id)
        guard let from = ids.firstIndex(of: id), let to = ids.firstIndex(of: target), from != to else { return }
        // `move(of:from:to:)` takes an insertion point: after the target when the row moves down.
        move(of: work, from: [from], to: to > from ? to + 1 : to)
    }

    /// Sends the changes that wait, then reads all stars. The server is right, except for a change that still waits.
    func refresh() async {
        await serially {
            _ = await self.sendQueue()
            await self.readStars()
        }
    }

    /// Sends the changes that wait. A tap calls it, and so does the app when the connection comes back. A failure
    /// shows no notice: the changes wait, and `serverTrouble` says why.
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
                if let artist = change.artist {
                    if change.isSet {
                        try await server.starArtist(artist.id)
                    } else {
                        try await server.unstarArtist(artist.id)
                    }
                } else {
                    switch (change.album, change.isSet) {
                    case (let album?, true): try await server.starAlbum(album)
                    case (let album?, false): try await server.unstarAlbum(album)
                    case (nil, true): try await server.star(change.songs)
                    case (nil, false): try await server.unstar(change.songs)
                    }
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
            // The stars decide whether a row is a favourite, so read this before they change.
            let placedWorks = library.index.composers.flatMap(\.works).map { ($0, isPlaced($0)) }
            artists = stars.artist ?? []
            var songs = Set((stars.song ?? []).map(\.id))
            var albums = Set((stars.album ?? []).map(\.id))
            for change in data.pendingFavourites {
                if let artist = change.artist {
                    artists.removeAll { $0.id == artist.id }
                    if change.isSet { artists.append(artist) }
                    continue
                }
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
            changed.favouriteArtists = artists
            for (work, placed) in placedWorks {
                changed.recordingOrder[work.id] = orderToKeep(of: work, placed: placed)
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
            try file.save(changed)
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
        func starArtist(_ id: String) async throws { throw URLError(.notConnectedToInternet) }
        func unstarArtist(_ id: String) async throws { throw URLError(.notConnectedToInternet) }
        func getStarred() async throws -> Starred { try await client.getStarred() }
    }
#endif
