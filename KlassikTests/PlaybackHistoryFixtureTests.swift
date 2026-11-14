import Foundation
import Testing

@testable import Klassik

@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["KLASSIK_SERVER_URL"] != nil))
struct PlaybackHistoryFixtureTests {
    @Test func queueAndScrobbleRoundTripThroughNavidrome() async throws {
        let env = ProcessInfo.processInfo.environment
        let url = try #require(env["KLASSIK_SERVER_URL"].flatMap(ServerCredentials.normalizedURL))
        let client = SubsonicClient(
            credentials: ServerCredentials(
                url: url, username: env["KLASSIK_USERNAME"] ?? "", password: env["KLASSIK_PASSWORD"] ?? ""))
        let songs = try await client.songs(offset: 0, count: 3)
        let first = try #require(songs.first)
        let before = try await client.get("getSong", [URLQueryItem(name: "id", value: first.id)]).song?.playCount ?? 0
        try await client.savePlayQueue(ids: songs.map(\.id), current: first.id, position: 1234)
        let queue = try #require(try await client.getPlayQueue())
        #expect(queue.entry?.map(\.id) == songs.map(\.id))
        #expect(queue.current == first.id)
        #expect(queue.position == 1234)
        try await client.scrobble(id: first.id, time: .now)
        let after = try await client.get("getSong", [URLQueryItem(name: "id", value: first.id)]).song?.playCount
        #expect(after == before + 1)
        try await client.savePlayQueue(ids: [], current: nil, position: 0)
        #expect(try await client.getPlayQueue()?.entry?.isEmpty != false)
    }
}
