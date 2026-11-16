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
