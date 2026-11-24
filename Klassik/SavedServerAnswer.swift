import Foundation

/// The last answer of the server, kept on the device with the address that gave it. The Server Connection page
/// shows it at launch. An answer counts only for the address that gave it, so another server never shows it.
struct SavedServerAnswer {
    private static let key = "server.info"

    private struct Entry: Codable {
        var url: URL
        var info: ServerInfo
    }

    let defaults: UserDefaults

    func save(_ info: ServerInfo?, for url: URL?) {
        guard let info, let url, let data = try? JSONEncoder().encode(Entry(url: url, info: info))
        else { return clear() }
        defaults.set(data, forKey: Self.key)
    }

    func load(for url: URL?) -> ServerInfo? {
        guard let url, let data = defaults.data(forKey: Self.key),
            let entry = try? JSONDecoder().decode(Entry.self, from: data), entry.url == url
        else { return nil }
        return entry.info
    }

    func clear() {
        defaults.removeObject(forKey: Self.key)
    }
}
