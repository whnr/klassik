import CryptoKit
import Foundation
import KlassikEngine

/// Login data for the Lab server.
struct LabCredentials: Equatable, Sendable {
    var url: URL
    var username: String
    var password: String

    /// Accepts what people type: a bare host gets http, because the Lab server runs on the home network.
    static func normalizedURL(from text: String) -> URL? {
        var text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if !text.contains("://") { text = "http://" + text }
        guard let parsed = URL(string: text), let scheme = parsed.scheme?.lowercased(),
            ["http", "https"].contains(scheme), parsed.host()?.isEmpty == false
        else { return nil }
        while text.hasSuffix("/") { text.removeLast() }
        return URL(string: text)
    }
}

enum LabError: LocalizedError, Equatable {
    case server(String)
    case http(Int)
    case notSubsonic
    case noAlbum

    var errorDescription: String? {
        switch self {
        case .server(let message): message
        case .http(let status): "The server answered with HTTP \(status)."
        case .notSubsonic: "The server did not answer like a Subsonic server."
        case .noAlbum: "The server has no album called \"\(LabClient.albumName)\"."
        }
    }
}

/// One file of the Lab album, as the server describes it.
struct LabSong: Decodable, Sendable, Hashable, Identifiable {
    struct Work: Decodable, Sendable, Hashable {
        var name: String
    }

    struct ReplayGain: Decodable, Sendable, Hashable {
        var trackGain: Double?
        var albumGain: Double?
        var trackPeak: Double?
        var albumPeak: Double?
        var fallbackGain: Double?
    }

    var id: String
    var title: String
    var track: Int?
    var discNumber: Int?
    var duration: Int?
    var suffix: String?
    var bitRate: Int?
    var samplingRate: Int?
    var bitDepth: Int?
    var channelCount: Int?
    /// The path below the music folder. A test case is the folder that holds its files.
    var path: String?
    var works: [Work]?
    var replayGain: ReplayGain?

    var playbackTrack: PlaybackTrack {
        PlaybackTrack(
            id: id, duration: duration, suffix: suffix, bitRate: bitRate, samplingRate: samplingRate,
            bitDepth: bitDepth, channelCount: channelCount,
            replayGain: replayGain.map {
                PlaybackTrack.ReplayGain(
                    trackGain: $0.trackGain, albumGain: $0.albumGain, trackPeak: $0.trackPeak,
                    albumPeak: $0.albumPeak, fallbackGain: $0.fallbackGain)
            })
    }
}

/// The few Subsonic calls that the Lab needs: find its album, list the files, build a stream request.
struct LabClient: Sendable {
    /// `scripts/playback_lab.py` writes this album name.
    static let albumName = "Playback Lab"

    var credentials: LabCredentials

    private struct Envelope: Decodable {
        struct Body: Decodable {
            struct Failure: Decodable {
                var message: String?
            }
            struct Search: Decodable {
                struct Found: Decodable {
                    var id: String
                    var name: String
                }
                var album: [Found]?
            }
            struct Album: Decodable {
                var song: [LabSong]?
            }
            var status: String
            var error: Failure?
            var searchResult3: Search?
            var album: Album?
        }
        var body: Body
        enum CodingKeys: String, CodingKey { case body = "subsonic-response" }
    }

    /// The files of the Lab album. Nothing else of the library is read.
    func albumSongs() async throws -> [LabSong] {
        let search = try await get(
            "search3",
            [
                URLQueryItem(name: "query", value: Self.albumName),
                URLQueryItem(name: "artistCount", value: "0"),
                URLQueryItem(name: "albumCount", value: "20"),
                URLQueryItem(name: "songCount", value: "0"),
            ])
        guard let found = search.searchResult3?.album?.first(where: { $0.name == Self.albumName }) else {
            throw LabError.noAlbum
        }
        let album = try await get("getAlbum", [URLQueryItem(name: "id", value: found.id)])
        return album.album?.song ?? []
    }

    /// The untouched file. `format=raw` stops the server from transcoding.
    func streamRequest(songID: String) -> URLRequest {
        var request = URLRequest(
            url: url("stream", [URLQueryItem(name: "id", value: songID), URLQueryItem(name: "format", value: "raw")]))
        request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        return request
    }

    private func get(_ endpoint: String, _ query: [URLQueryItem]) async throws -> Envelope.Body {
        let (data, response) = try await URLSession.shared.data(from: url(endpoint, query))
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw LabError.http(http.statusCode)
        }
        guard let body = try? JSONDecoder().decode(Envelope.self, from: data).body else { throw LabError.notSubsonic }
        if body.status != "ok" { throw LabError.server(body.error?.message ?? "The server refused the request.") }
        return body
    }

    /// Token authentication: the password itself never goes over the wire.
    private func url(_ endpoint: String, _ query: [URLQueryItem]) -> URL {
        let salt = (0..<6).map { _ in String(format: "%02x", UInt8.random(in: 0...255)) }.joined()
        let token = Insecure.MD5.hash(data: Data((credentials.password + salt).utf8))
            .map { String(format: "%02x", $0) }.joined()
        return credentials.url.appending(path: "rest/\(endpoint)").appending(
            queryItems: [
                URLQueryItem(name: "u", value: credentials.username),
                URLQueryItem(name: "t", value: token),
                URLQueryItem(name: "s", value: salt),
                URLQueryItem(name: "v", value: "1.16.1"),
                URLQueryItem(name: "c", value: "KlassikLab"),
                URLQueryItem(name: "f", value: "json"),
            ] + query)
    }
}
