import Foundation
import Observation

#if canImport(CryptoKit)
    import CryptoKit
#else
    import Crypto
#endif

/// Listener data belongs to a server and user, even after sign-out (ADR 0013).
struct DeviceStore {
    struct Data: Codable, Equatable {
        var favouriteWorks: Set<String> = []
        var recordingOrder: [String: [String]] = [:]
        /// The album stars as the app shows them, so that they also show without a connection.
        var favouriteAlbums: Set<String> = []
        var favouriteArtists: [Song.Artist] = []
        /// Star changes that the server did not confirm yet, oldest first (ADR 0052).
        var pendingFavourites: [FavouriteChange] = []
        /// Listening notes by recording ID (ADR 0013). The server never sees them.
        var notes: [String: [ListeningNote]] = [:]

        /// Keeps one change for each target: the server must get the newest choice.
        mutating func queue(_ change: FavouriteChange) {
            if let artist = change.artist {
                pendingFavourites.removeAll { $0.artist?.id == artist.id }
            } else if let album = change.album {
                pendingFavourites.removeAll { $0.album == album }
            } else {
                for index in pendingFavourites.indices
                where pendingFavourites[index].album == nil && pendingFavourites[index].artist == nil {
                    pendingFavourites[index].songs.removeAll { change.songs.contains($0) }
                }
                pendingFavourites.removeAll { $0.album == nil && $0.artist == nil && $0.songs.isEmpty }
            }
            pendingFavourites.append(change)
        }
    }

    /// A star or unstar of songs, one album, or one artist.
    struct FavouriteChange: Codable, Equatable, Identifiable {
        var id = UUID()
        var songs: [String] = []
        var album: String?
        var artist: Song.Artist?
        var isSet: Bool
    }

    let url: URL

    init(server: URL, username: String, folder: URL = .applicationSupportDirectory.appending(path: "listeners")) {
        let identity = [server.absoluteString, username]
        let bytes = (try? JSONEncoder().encode(identity)) ?? Foundation.Data()
        let key = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        url = folder.appending(path: "\(key).json")
    }

    func load() throws -> Data {
        guard FileManager.default.fileExists(atPath: url.path) else { return Data() }
        return try JSONDecoder().decode(Data.self, from: Foundation.Data(contentsOf: url))
    }

    func save(_ data: Data) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(data).write(to: url, options: .atomic)
    }

    func delete() throws {
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
    }
}

extension DeviceStore.Data {
    /// A file from an older build has no album stars, no queue and no notes.
    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        favouriteWorks = try values.decode(Set<String>.self, forKey: .favouriteWorks)
        recordingOrder = try values.decode([String: [String]].self, forKey: .recordingOrder)
        favouriteAlbums = try values.decodeIfPresent(Set<String>.self, forKey: .favouriteAlbums) ?? []
        favouriteArtists = try values.decodeIfPresent([Song.Artist].self, forKey: .favouriteArtists) ?? []
        pendingFavourites =
            try values.decodeIfPresent([DeviceStore.FavouriteChange].self, forKey: .pendingFavourites) ?? []
        notes = try values.decodeIfPresent([String: [ListeningNote]].self, forKey: .notes) ?? [:]
    }
}

/// The one copy of the device file in memory. Every module that keeps listener data writes through it, so that no
/// module writes an old copy over the data of another.
@MainActor @Observable
final class ListenerFile {
    private(set) var data = DeviceStore.Data()
    /// A file that does not load refuses every write, so a damaged file is never replaced.
    private(set) var loadError: String?
    private let store: DeviceStore?

    init(store: DeviceStore?) {
        self.store = store
        do { data = try store?.load() ?? DeviceStore.Data() } catch { loadError = error.localizedDescription }
    }

    /// Writes the file, then keeps the change in memory.
    func save(_ changed: DeviceStore.Data) throws {
        if let loadError { throw Unreadable(message: loadError) }
        guard changed != data else { return }
        try store?.save(changed)
        data = changed
    }

    struct Unreadable: LocalizedError {
        var message: String
        var errorDescription: String? { message }
    }
}
