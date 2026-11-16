import Foundation
import Observation

protocol FavouriteServer: Sendable {
    func star(_ ids: [String]) async throws
    func unstar(_ ids: [String]) async throws
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

    init(library: Library, store: DeviceStore? = nil, server: (any FavouriteServer)? = nil) {
        self.library = library
        self.store = store
        self.server = server
        do { data = try store?.load() ?? DeviceStore.Data() } catch { self.error = error.localizedDescription }
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
        guard !isSaving, let server else { return }
        isSaving = true
        defer { isSaving = false }
        let live = library.current(work: work, recording: recording).recording
        let ids = live.songs.map(\.id)
        guard !ids.isEmpty else { return }
        do {
            if live.isFavourite { try await server.unstar(ids) } else { try await server.star(ids) }
            library.setStarred(Set(ids), !live.isFavourite)
            var changed = data
            var order = rows(of: work).filter(\.isFavourite).map(\.id)
            order.removeAll { $0 == live.id }
            if !live.isFavourite { order.append(live.id) }
            changed.recordingOrder[work.id] = order
            save(changed)
        } catch { self.error = error.localizedDescription }
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
            artists = stars.artist ?? []
            albums = Set((stars.album ?? []).map(\.id))
            library.replaceStars(Set((stars.song ?? []).map(\.id)))
            var changed = data
            for work in library.index.composers.flatMap(\.works) {
                changed.recordingOrder[work.id] = rows(of: work).filter(\.isFavourite).map(\.id)
            }
            save(changed)
        } catch { self.error = error.localizedDescription }
    }

    private func save(_ changed: DeviceStore.Data) {
        guard changed != data else { return }
        do {
            try store?.save(changed)
            data = changed
        } catch { self.error = error.localizedDescription }
    }
}
