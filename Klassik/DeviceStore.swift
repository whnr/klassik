import Foundation

#if canImport(CryptoKit)
    import CryptoKit
#else
    import Crypto
#endif

/// Listener data belongs to a server and user, even after sign-out (ADR 0013).
struct DeviceStore {
    struct Data: Codable, Equatable {
        struct FavouriteChange: Codable, Equatable, Identifiable {
            var id = UUID()
            var songs: [String] = []
            var album: String?
            var isSet: Bool
        }

        var favouriteWorks: Set<String> = []
        var recordingOrder: [String: [String]] = [:]
        var trackFavourites: [String: Bool] = [:]
        var favouriteAlbums: Set<String> = []
        var pendingFavourites: [FavouriteChange] = []

        enum CodingKeys: String, CodingKey {
            case favouriteWorks, recordingOrder, favouriteAlbums, pendingFavourites, trackFavourites
        }

        init(favouriteWorks: Set<String> = [], recordingOrder: [String: [String]] = [:]) {
            self.favouriteWorks = favouriteWorks
            self.recordingOrder = recordingOrder
        }

        init(from decoder: any Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            favouriteWorks = try values.decode(Set<String>.self, forKey: .favouriteWorks)
            recordingOrder = try values.decode([String: [String]].self, forKey: .recordingOrder)
            trackFavourites = try values.decodeIfPresent([String: Bool].self, forKey: .trackFavourites) ?? [:]
            favouriteAlbums = try values.decodeIfPresent(Set<String>.self, forKey: .favouriteAlbums) ?? []
            pendingFavourites = try values.decodeIfPresent([FavouriteChange].self, forKey: .pendingFavourites) ?? []
        }
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
