import Foundation

#if canImport(CryptoKit)
    import CryptoKit
#else
    import Crypto
#endif
#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

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
            ["http", "https"].contains(scheme), parsed.host()?.isEmpty == false
        else { return nil }
        while text.hasSuffix("/") { text.removeLast() }
        return URL(string: text)
    }
}

/// What the server reports about itself.
struct ServerInfo: Equatable, Sendable, Codable {
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
        case .server(let code, let message): L("\(message) (Subsonic error \(code))")
        case .http(let status): L("The server answered with HTTP \(status).")
        case .notSubsonic: L("The server did not answer like a Subsonic server.")
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
        /// The sort form of the name, such as "Kubelík, Rafael", where the server sends it.
        var sortName: String?
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
    /// The album artist as the server shows it (OpenSubsonic).
    var displayAlbumArtist: String?
    var track: Int?
    var discNumber: Int?
    var year: Int?
    var duration: Int?
    var suffix: String?
    /// The ID of the cover for `getCoverArt`.
    var coverArt: String?
    var genre: String?
    var genres: [Genre]?
    var displayComposer: String?
    var contributors: [Contributor]?
    var works: [Work]?
    var movements: [Movement]?
    /// The GROUPING tag: the set that a piece belongs to, such as "Nocturnes, Op. 9".
    var groupings: [String]?
    var replayGain: ReplayGain?
    /// The date when the user starred the track. The server omits it for other tracks.
    var starred: String?
    var playCount: Int?
    /// When the track entered the server library, as an ISO 8601 date. Recently added sorts by it.
    var created: String?
    /// When the listener last played the track, as the server sends it (OpenSubsonic `played`).
    var played: String?
    /// Kilobits per second, as the server declares it. The start threshold reads it (ADR 0060).
    var bitRate: Int?
    var samplingRate: Int?
    var bitDepth: Int?
    var channelCount: Int?
    /// The file size in bytes.
    var size: Int64?
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
    var song: Song?
    var playQueue: ServerPlayQueue?
    var indexes: Indexes?
    var scanStatus: ScanStatus?
    var starred2: Starred?

    struct Indexes: Decodable, Sendable {
        /// Milliseconds since 1970 of the last change to the artist index.
        var lastModified: Int64?
    }

    struct ScanStatus: Decodable, Sendable {
        var lastScan: String?
    }

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
    /// The start-up reads (ping, change marker) fail after this long, because a stalled connection to a local
    /// server otherwise holds them past the point where the listener sees the library. Song pages and writes keep
    /// the session's own timeout: a large library or a slow server needs longer than this to answer.
    static let quickReadTimeout: TimeInterval = 8

    var session: URLSession = .shared

    func ping() async throws -> ServerInfo {
        let response = try await retried { try await get("ping", timeout: Self.quickReadTimeout) }
        var info = ServerInfo(
            apiVersion: response.version, type: response.type,
            serverVersion: response.serverVersion, openSubsonic: response.openSubsonic ?? false)
        if info.openSubsonic {
            let extensions = try await retried {
                try await get("getOpenSubsonicExtensions", timeout: Self.quickReadTimeout)
            }
            info.extensions = extensions.openSubsonicExtensions?.map(\.name) ?? []
        }
        return info
    }

    func searchAlbums(_ query: String) async throws -> [Album] {
        try await get(
            "search3",
            [
                URLQueryItem(name: "query", value: query),
                URLQueryItem(name: "artistCount", value: "0"),
                URLQueryItem(name: "albumCount", value: "50"),
                URLQueryItem(name: "songCount", value: "0"),
            ]
        ).searchResult3?.album ?? []
    }

    /// One page of all tracks. OpenSubsonic servers return the whole library for an empty query.
    func songs(offset: Int, count: Int) async throws -> [Song] {
        try await retried(onTimeout: false) {
            try await get(
                "search3",
                [
                    URLQueryItem(name: "query", value: ""),
                    URLQueryItem(name: "artistCount", value: "0"),
                    URLQueryItem(name: "albumCount", value: "0"),
                    URLQueryItem(name: "songCount", value: String(count)),
                    URLQueryItem(name: "songOffset", value: String(offset)),
                ]
            )
        }.searchResult3?.song ?? []
    }

    func album(id: String) async throws -> Album {
        guard let album = try await get("getAlbum", [URLQueryItem(name: "id", value: id)]).album else {
            throw SubsonicError.notSubsonic
        }
        return album
    }

    /// Changes when the server scans new or changed files. The classic `getIndexes` date alone can miss a change
    /// to an existing artist, so the scan date joins it where the server reports one.
    func changeMarker() async throws -> String {
        let indexes = try await retried { try await get("getIndexes", timeout: Self.quickReadTimeout) }
            .indexes?.lastModified
        let scan = try? await get("getScanStatus", timeout: Self.quickReadTimeout).scanStatus?.lastScan
        return "\(indexes.map(String.init) ?? "-")|\(scan ?? "-")"
    }

    var listeningDataKey: String {
        "player.queue.\(credentials.url.absoluteString)|\(credentials.username)"
    }

    func getPlayQueue() async throws -> ServerPlayQueue? {
        try await get("getPlayQueue").playQueue
    }

    func savePlayQueue(ids: [String], current: String?, position: Int64) async throws {
        var query = ids.map { URLQueryItem(name: "id", value: $0) }
        if let current, !ids.isEmpty {
            query.append(URLQueryItem(name: "current", value: current))
            query.append(URLQueryItem(name: "position", value: String(position)))
        }
        _ = try await get("savePlayQueue", query)
    }

    func scrobble(id: String, time: Date) async throws {
        _ = try await get(
            "scrobble",
            [
                URLQueryItem(name: "id", value: id),
                URLQueryItem(name: "time", value: String(Int64(time.timeIntervalSince1970 * 1000))),
                URLQueryItem(name: "submission", value: "true"),
            ])
    }

    func star(_ ids: [String]) async throws {
        _ = try await get("star", ids.map { URLQueryItem(name: "id", value: $0) })
    }

    func unstar(_ ids: [String]) async throws {
        _ = try await get("unstar", ids.map { URLQueryItem(name: "id", value: $0) })
    }

    func starAlbum(_ id: String) async throws {
        _ = try await get("star", [URLQueryItem(name: "albumId", value: id)])
    }

    func unstarAlbum(_ id: String) async throws {
        _ = try await get("unstar", [URLQueryItem(name: "albumId", value: id)])
    }

    func starArtist(_ id: String) async throws {
        _ = try await get("star", [URLQueryItem(name: "artistId", value: id)])
    }

    func unstarArtist(_ id: String) async throws {
        _ = try await get("unstar", [URLQueryItem(name: "artistId", value: id)])
    }

    /// The address of a cover, scaled by the server to `size` pixels on its longer side.
    func coverArtURL(id: String, size: Int) -> URL {
        url("getCoverArt", [URLQueryItem(name: "id", value: id), URLQueryItem(name: "size", value: String(size))])
    }

    /// `format=raw` preserves the original gapless header.
    func streamURL(songID: String) -> URL {
        url("stream", [URLQueryItem(name: "id", value: songID), URLQueryItem(name: "format", value: "raw")])
    }

    /// Runs a read once more when the first try lost its connection, or timed out when `onTimeout` is set. Only
    /// reads may use it: a repeated write could apply twice. A slow query keeps running on the server after the
    /// client gives up, so a long read is not repeated after a timeout.
    func retried(onTimeout: Bool = true, _ read: () async throws -> SubsonicResponse) async throws
        -> SubsonicResponse
    {
        do {
            return try await read()
        } catch let error as URLError
            where error.code == .networkConnectionLost || (onTimeout && error.code == .timedOut)
        {
            return try await read()
        }
    }

    func get(_ endpoint: String, _ query: [URLQueryItem] = [], timeout: TimeInterval? = nil) async throws
        -> SubsonicResponse
    {
        var request = URLRequest(url: url(endpoint, query))
        if let timeout { request.timeoutInterval = timeout }
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw SubsonicError.http(status: http.statusCode)
        }
        return try Self.decode(data)
    }

    /// Token authentication: the password itself never goes over the wire.
    func url(_ endpoint: String, _ query: [URLQueryItem] = [], salt: String = Self.makeSalt()) -> URL {
        credentials.url.appending(path: "rest/\(endpoint)").appending(
            queryItems: [
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
            throw SubsonicError.server(code: error.code, message: error.message ?? L("Unknown error"))
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
