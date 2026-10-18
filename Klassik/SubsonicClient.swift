import CryptoKit
import Foundation

/// Login data for one OpenSubsonic server.
struct ServerCredentials: Equatable, Sendable {
    var url: URL
    var username: String
    var password: String

    /// Accepts what people type: a bare host gets https, a trailing slash is dropped.
    static func normalizedURL(from text: String) -> URL? {
        var text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if !text.contains("://") { text = "https://" + text }
        guard let parsed = URL(string: text), let scheme = parsed.scheme?.lowercased(),
              ["http", "https"].contains(scheme), parsed.host()?.isEmpty == false else { return nil }
        while text.hasSuffix("/") { text.removeLast() }
        return URL(string: text)
    }
}

/// What the server reports about itself.
struct ServerInfo: Equatable, Sendable {
    var apiVersion: String
    var type: String?
    var serverVersion: String?
    var openSubsonic: Bool
    var extensions: [String] = []
}

enum SubsonicError: LocalizedError, Equatable {
    case server(code: Int, message: String)
    case http(status: Int)
    case notSubsonic

    var errorDescription: String? {
        switch self {
        case .server(let code, let message): "\(message) (Subsonic error \(code))"
        case .http(let status): "The server answered with HTTP \(status)."
        case .notSubsonic: "The server did not answer like a Subsonic server."
        }
    }
}

struct Album: Decodable, Sendable, Identifiable, Hashable {
    var id: String
    var name: String
    var artist: String?
    var year: Int?
    var song: [Song]?

    /// Tracks in disc and track order.
    var songs: [Song] {
        (song ?? []).sorted { ($0.discNumber ?? 0, $0.track ?? 0) < ($1.discNumber ?? 0, $1.track ?? 0) }
    }
}

/// A track with the OpenSubsonic fields Klassik reads. The library cache stores it as it is.
struct Song: Codable, Sendable, Identifiable, Hashable {
    struct Genre: Codable, Sendable, Hashable {
        var name: String
    }

    struct Artist: Codable, Sendable, Hashable {
        var id: String
        var name: String
    }

    struct Contributor: Codable, Sendable, Hashable {
        var role: String
        var subRole: String?
        var artist: Artist
    }

    struct Work: Codable, Sendable, Hashable {
        var name: String
        var musicBrainzId: String?
    }

    struct Movement: Codable, Sendable, Hashable {
        var name: String
        var number: Int?
        var count: Int?
    }

    /// Gains in decibels. A peak is the highest sample, where 1 is full scale.
    struct ReplayGain: Codable, Sendable, Hashable {
        var trackGain: Double?
        var albumGain: Double?
        var trackPeak: Double?
        var albumPeak: Double?
        var fallbackGain: Double?
    }

    var id: String
    var title: String
    var album: String?
    var albumId: String?
    var artist: String?
    var track: Int?
    var discNumber: Int?
    var year: Int?
    var duration: Int?
    var suffix: String?
    var genre: String?
    var genres: [Genre]?
    var displayComposer: String?
    var contributors: [Contributor]?
    var works: [Work]?
    var movements: [Movement]?
    var replayGain: ReplayGain?
}

/// The `subsonic-response` object. Fields of all endpoints in use are optional members.
struct SubsonicResponse: Decodable, Sendable {
    struct Failure: Decodable, Sendable {
        var code: Int
        var message: String?
    }

    struct Extension: Decodable, Sendable {
        var name: String
        var versions: [Int]
    }

    var status: String
    var version: String
    var type: String?
    var serverVersion: String?
    var openSubsonic: Bool?
    var error: Failure?
    var openSubsonicExtensions: [Extension]?
    var searchResult3: SearchResult?
    var album: Album?

    struct SearchResult: Decodable, Sendable {
        var album: [Album]?
        var song: [Song]?
    }
}

struct SubsonicClient: Sendable {
    static let clientName = "Klassik"
    /// The highest classic Subsonic API level that OpenSubsonic servers support.
    static let apiVersion = "1.16.1"

    let credentials: ServerCredentials
    var session: URLSession = .shared

    func ping() async throws -> ServerInfo {
        let response = try await get("ping")
        var info = ServerInfo(
            apiVersion: response.version, type: response.type,
            serverVersion: response.serverVersion, openSubsonic: response.openSubsonic ?? false)
        if info.openSubsonic {
            info.extensions = try await get("getOpenSubsonicExtensions").openSubsonicExtensions?.map(\.name) ?? []
        }
        return info
    }

    func searchAlbums(_ query: String) async throws -> [Album] {
        try await get("search3", [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "artistCount", value: "0"),
            URLQueryItem(name: "albumCount", value: "50"),
            URLQueryItem(name: "songCount", value: "0"),
        ]).searchResult3?.album ?? []
    }

    /// One page of all tracks. OpenSubsonic servers return the whole library for an empty query.
    func songs(offset: Int, count: Int) async throws -> [Song] {
        try await get("search3", [
            URLQueryItem(name: "query", value: ""),
            URLQueryItem(name: "artistCount", value: "0"),
            URLQueryItem(name: "albumCount", value: "0"),
            URLQueryItem(name: "songCount", value: String(count)),
            URLQueryItem(name: "songOffset", value: String(offset)),
        ]).searchResult3?.song ?? []
    }

    func album(id: String) async throws -> Album {
        guard let album = try await get("getAlbum", [URLQueryItem(name: "id", value: id)]).album else {
            throw SubsonicError.notSubsonic
        }
        return album
    }

    /// `format=raw` asks for the original file: a transcoded stream loses the MP3 gapless header.
    func streamURL(songID: String) -> URL {
        url("stream", [URLQueryItem(name: "id", value: songID), URLQueryItem(name: "format", value: "raw")])
    }

    func get(_ endpoint: String, _ query: [URLQueryItem] = []) async throws -> SubsonicResponse {
        let (data, response) = try await session.data(from: url(endpoint, query))
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw SubsonicError.http(status: http.statusCode)
        }
        return try Self.decode(data)
    }

    /// Token authentication: the password itself never goes over the wire.
    func url(_ endpoint: String, _ query: [URLQueryItem] = [], salt: String = Self.makeSalt()) -> URL {
        credentials.url.appending(path: "rest/\(endpoint)").appending(queryItems: [
            URLQueryItem(name: "u", value: credentials.username),
            URLQueryItem(name: "t", value: Self.token(password: credentials.password, salt: salt)),
            URLQueryItem(name: "s", value: salt),
            URLQueryItem(name: "v", value: Self.apiVersion),
            URLQueryItem(name: "c", value: Self.clientName),
            URLQueryItem(name: "f", value: "json"),
        ] + query)
    }

    static func decode(_ data: Data) throws -> SubsonicResponse {
        struct Envelope: Decodable {
            var body: SubsonicResponse
            enum CodingKeys: String, CodingKey { case body = "subsonic-response" }
        }
        guard let response = try? JSONDecoder().decode(Envelope.self, from: data).body else {
            throw SubsonicError.notSubsonic
        }
        if let error = response.error {
            throw SubsonicError.server(code: error.code, message: error.message ?? "Unknown error")
        }
        return response
    }

    static func token(password: String, salt: String) -> String {
        Insecure.MD5.hash(data: Data((password + salt).utf8)).map { String(format: "%02x", $0) }.joined()
    }

    static func makeSalt() -> String {
        (0..<6).map { _ in String(format: "%02x", UInt8.random(in: 0...255)) }.joined()
    }
}
