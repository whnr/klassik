import Foundation

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
        /// Star changes that the server did not confirm yet, oldest first (ADR 0052).
        var pendingFavourites: [FavouriteChange] = []

        /// Keeps one change for each song and album: the newest choice is the one that the server must get.
        mutating func queue(_ change: FavouriteChange) {
            if let album = change.album {
                pendingFavourites.removeAll { $0.album == album }
            } else {
                for index in pendingFavourites.indices where pendingFavourites[index].album == nil {
                    pendingFavourites[index].songs.removeAll { change.songs.contains($0) }
                }
                pendingFavourites.removeAll { $0.album == nil && $0.songs.isEmpty }
            }
            pendingFavourites.append(change)
        }
    }

    /// A star or unstar of songs, or of one album.
    struct FavouriteChange: Codable, Equatable, Identifiable {
        var id = UUID()
        var songs: [String] = []
        var album: String?
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
    /// A file from an older build has no album stars and no queue.
    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        favouriteWorks = try values.decode(Set<String>.self, forKey: .favouriteWorks)
        recordingOrder = try values.decode([String: [String]].self, forKey: .recordingOrder)
        favouriteAlbums = try values.decodeIfPresent(Set<String>.self, forKey: .favouriteAlbums) ?? []
        pendingFavourites =
            try values.decodeIfPresent([DeviceStore.FavouriteChange].self, forKey: .pendingFavourites) ?? []
    }
}
