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
    private(set) var isSaving = false
    var error: String?
    private(set) var loadError: String?
    private(set) var refreshError: String?
    private var reportedConnectionFailure = false

    init(library: Library, store: DeviceStore? = nil, server: (any FavouriteServer)? = nil) {
        self.library = library
        self.store = store
        self.server = server
        do { data = try store?.load() ?? DeviceStore.Data() } catch { loadError = error.localizedDescription }
    }

    func isFavourite(_ work: WorkIndex.Work) -> Bool { data.favouriteWorks.contains(work.id) }

    func isFavourite(_ recording: WorkIndex.Recording, of work: WorkIndex.Work) -> Bool {
        library.current(work: work, recording: recording).recording.isFavourite
    }

    func rows(of work: WorkIndex.Work) -> [Row] {
        let live = library.index.work(work.id) ?? work
        let order = data.recordingOrder[work.id] ?? []
        return live.recordings.map { recording in
            var reason: String?
            if !recording.isFavourite {
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
            return Row(recording: recording, reason: reason, isFavourite: recording.isFavourite)
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

    /// Changes the favourite of a recording at once: its mark and its place among the favourites. The returned
    /// call tells the server and keeps the change on the device. When the server refuses, it takes the change back.
    func begin(_ recording: WorkIndex.Recording, of work: WorkIndex.Work) -> (@MainActor () async -> Void)? {
        guard !isSaving, let server else { return nil }
        guard loadError == nil else {
            error = loadError
            return nil
        }
        let live = library.current(work: work, recording: recording).recording
        let ids = live.songs.map(\.id)
        guard !ids.isEmpty else { return nil }
        let isSet = !live.isFavourite
        let previous = rows(of: work).filter(\.isFavourite).map(\.id)
        var order = previous
        order.removeAll { $0 == live.id }
        if isSet { order.append(live.id) }
        isSaving = true
        library.setStarred(Set(ids), isSet)
        data.recordingOrder[work.id] = order
        return { [self] in
            defer { isSaving = false }
            do {
                if isSet { try await server.star(ids) } else { try await server.unstar(ids) }
                reportedConnectionFailure = false
            } catch {
                // Other favourite changes can arrive while the server call runs, so only this recording goes back.
                library.setStarred(Set(ids), !isSet)
                var reverted = data.recordingOrder[work.id] ?? []
                reverted.removeAll { $0 == live.id }
                if !isSet, let index = previous.firstIndex(of: live.id) {
                    reverted.insert(live.id, at: min(index, reverted.count))
                }
                data.recordingOrder[work.id] = reverted.isEmpty ? nil : reverted
                report(error)
            }
            // A save while the call ran wrote the unconfirmed order too, so the file always gets the outcome.
            persist()
        }
    }

    func isFavourite(album id: String) -> Bool { albums.contains(id) }

    func toggle(album id: String) async {
        await begin(album: id)?()
    }

    /// Changes the favourite of an album at once. It is a star on the album, not on its tracks (ADR 0013). The
    /// returned call tells the server. When the server refuses, it takes the change back.
    func begin(album id: String) -> (@MainActor () async -> Void)? {
        guard !isSaving, let server else { return nil }
        let isSet = !albums.contains(id)
        isSaving = true
        if isSet { albums.insert(id) } else { albums.remove(id) }
        return { [self] in
            defer { isSaving = false }
            do {
                if isSet { try await server.starAlbum(id) } else { try await server.unstarAlbum(id) }
                reportedConnectionFailure = false
            } catch {
                if isSet { albums.remove(id) } else { albums.insert(id) }
                report(error)
            }
        }
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
        guard !isSaving, let server else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            let stars = try await server.getStarred()
            refreshError = nil
            reportedConnectionFailure = false
            artists = stars.artist ?? []
            albums = Set((stars.album ?? []).map(\.id))
            library.replaceStars(Set((stars.song ?? []).map(\.id)))
            var changed = data
            for work in library.index.composers.flatMap(\.works) {
                changed.recordingOrder[work.id] = rows(of: work).filter(\.isFavourite).map(\.id)
            }
            if loadError == nil { save(changed) }
        } catch { refreshError = error.localizedDescription }
    }

    /// One failed save explains the rollback. Repeated taps need no further notice until the server answers.
    private func report(_ error: any Error) {
        if error is URLError {
            guard !reportedConnectionFailure else { return }
            reportedConnectionFailure = true
        } else if !(error is SubsonicError) {
            return
        }
        self.error = error.localizedDescription
    }

    private func persist() {
        guard loadError == nil else {
            error = loadError
            return
        }
        do { try store?.save(data) } catch { self.error = error.localizedDescription }
    }

    private func save(_ changed: DeviceStore.Data) {
        guard loadError == nil else {
            error = loadError
            return
        }
        guard changed != data else { return }
        do {
            try store?.save(changed)
            data = changed
        } catch { self.error = error.localizedDescription }
    }
}
