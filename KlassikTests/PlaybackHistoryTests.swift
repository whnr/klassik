import Foundation
import Testing

@testable import Klassik

@MainActor
struct PlaybackHistoryTests {
    private func item(_ id: String, count: Int = 2, album: Bool = false) -> QueueItem {
        let songs = (0..<count).map {
            Song(id: "\(id)-\($0)", title: "Movement \($0)", album: id, duration: 600)
        }
        let recording = WorkIndex.Recording(id: id, album: id, songs: songs, isAlbum: album)
        let work = WorkIndex.Work(id: id, title: id, composer: "Fixture", isTagged: false, recordings: [recording])
        return QueueItem(work: work, recording: recording)
    }

    private func defaults() throws -> UserDefaults {
        try #require(UserDefaults(suiteName: UUID().uuidString))
    }

    @Test func savesAndRestoresItemBoundariesAndMilliseconds() async throws {
        let server = InMemoryServer()
        let defaults = try defaults()
        let first = item("first")
        let album = item("album", count: 3, album: true)
        let history = PlaybackHistory(server: server, defaults: defaults)
        history.save(items: [first, album, first], movement: 1, position: 12.345)
        await history.flush()
        let saved = try #require(await server.queue)
        #expect(saved.current == "first-1")
        #expect(saved.position == 12_345)
        #expect(
            saved.entry?.map(\.id) == ["first-0", "first-1", "album-0", "album-1", "album-2", "first-0", "first-1"])
        let nextLaunch = PlaybackHistory(server: server, defaults: defaults)
        let restored = try #require(try await nextLaunch.restore())
        #expect(restored.items.map(\.id) == [first.id, album.id, first.id])
        #expect(restored.items[1].recording.isAlbum)
        #expect(restored.movement == 1)
        #expect(abs(restored.position - 12.345) < 0.001)
    }

    @Test func serverQueueWinsAndKeepsItsOrder() async throws {
        let server = InMemoryServer()
        let defaults = try defaults()
        let history = PlaybackHistory(server: server, defaults: defaults)
        history.save(items: [item("old")], movement: 0, position: 1)
        await history.flush()
        let songs = [
            Song(id: "b", title: "B", album: "Album", duration: 10, works: [.init(name: "Work")]),
            Song(id: "a", title: "A", album: "Album", duration: 10, works: [.init(name: "Work")]),
            Song(id: "c", title: "C", album: "Other", duration: 20),
        ]
        await server.setQueue(ServerPlayQueue(current: "a", position: 3000, entry: songs))
        let restored = try #require(try await history.restore())
        #expect(restored.items.flatMap(\.recording.songs).map(\.id) == ["b", "a", "c"])
        #expect(restored.items.count == 2)
        #expect(restored.movement == 1)
        #expect(restored.position == 3)
    }

    @Test func restoreDropsFinishedItemsAndClampsPosition() async throws {
        let server = InMemoryServer()
        let history = PlaybackHistory(server: server, defaults: try defaults())
        let first = item("first")
        let second = item("second")
        history.save(items: [first, second], movement: 0, position: 0)
        await history.flush()
        let songs = [first, second].flatMap(\.recording.songs)
        await server.setQueue(ServerPlayQueue(current: "second-1", position: 900_000, entry: songs))
        let restored = try #require(try await history.restore())
        #expect(restored.items.map(\.id) == [second.id])
        #expect(restored.movement == 1)
        #expect(restored.position == 600)
    }

    @Test func writesKeepOrderAndAnEmptyQueueClearsTheServer() async throws {
        let server = InMemoryServer()
        let history = PlaybackHistory(server: server, defaults: try defaults())
        history.save(items: [item("first")], movement: 0, position: 0)
        history.save(items: [item("second")], movement: 1, position: 10)
        history.save(items: [], movement: 0, position: 0)
        await history.flush()
        #expect(await server.savedQueues == [["first-0", "first-1"], ["second-0", "second-1"], []])
        #expect(try await history.restore() == nil)
    }

    @Test func accountDataStaysSeparate() async throws {
        let defaults = try defaults()
        let first = InMemoryServer()
        let second = InMemoryServer()
        let history = PlaybackHistory(server: first, defaults: defaults)
        history.save(items: [item("private", album: true)], movement: 0, position: 1)
        await history.flush()
        #expect(try await PlaybackHistory(server: second, defaults: defaults).restore() == nil)
    }

    @Test(arguments: [(10.0, 5.0), (600.0, 240.0)])
    func submitsOnceAtTheThreshold(duration: Double, threshold: Double) async throws {
        let server = InMemoryServer()
        let history = PlaybackHistory(server: server, defaults: try defaults())
        let item = item("first")
        history.begin(item: item, movement: 0, position: 0)
        history.hear(item: item, movement: 0, position: threshold - 1, duration: duration, enabled: true)
        await history.flush()
        #expect(await server.scrobbles.isEmpty)
        history.hear(item: item, movement: 0, position: threshold, duration: duration, enabled: true)
        history.hear(item: item, movement: 0, position: duration, duration: duration, enabled: true)
        await history.flush()
        #expect(await server.scrobbles == ["first-0"])
    }

    @Test func seeksDoNotCountAndEachMovementCanCount() async throws {
        let server = InMemoryServer()
        let history = PlaybackHistory(server: server, defaults: try defaults())
        let item = item("first")
        history.begin(item: item, movement: 0, position: 0)
        history.hear(item: item, movement: 0, position: 10, duration: 600, enabled: true)
        history.begin(item: item, movement: 0, position: 590)
        history.hear(item: item, movement: 0, position: 600, duration: 600, enabled: true)
        await history.flush()
        #expect(await server.scrobbles.isEmpty)
        history.begin(item: item, movement: 1, position: 0)
        history.hear(item: item, movement: 1, position: 240, duration: 600, enabled: true)
        await history.flush()
        #expect(await server.scrobbles == ["first-1"])
    }

    @Test func disabledPlaybackDoesNotCountAfterEnabling() async throws {
        let server = InMemoryServer()
        let history = PlaybackHistory(server: server, defaults: try defaults())
        let item = item("first")
        history.begin(item: item, movement: 0, position: 0)
        history.hear(item: item, movement: 0, position: 400, duration: 600, enabled: false)
        history.hear(item: item, movement: 0, position: 600, duration: 600, enabled: true)
        await history.flush()
        #expect(await server.scrobbles.isEmpty)
    }

    @Test func delayedResumeUsesTheFirstPlaybackAdvance() async throws {
        let server = InMemoryServer()
        var clock = Date(timeIntervalSince1970: 28_800)
        let history = PlaybackHistory(server: server, defaults: try defaults(), now: { clock })
        let item = item("first")
        history.begin(item: item, movement: 0, position: 12)
        clock = Date(timeIntervalSince1970: 64_800)
        history.hear(item: item, movement: 0, position: 12, duration: 600, enabled: true)
        #expect(await server.scrobbleTimes.isEmpty)
        clock.addTimeInterval(1)
        let started = clock
        history.hear(item: item, movement: 0, position: 13, duration: 600, enabled: true)
        history.begin(item: item, movement: 0, position: 30)
        clock.addTimeInterval(300)
        history.hear(item: item, movement: 0, position: 269, duration: 600, enabled: true)
        await history.flush()
        #expect(await server.scrobbleTimes == [started])
    }

    @Test func queueSavesPreserveFailedScrobbles() async throws {
        let server = InMemoryServer()
        let history = PlaybackHistory(server: server, defaults: try defaults())
        let item = item("first")
        var reported: ServerTrouble?
        history.onTrouble = { reported = $0 }
        await server.setScrobbleFailure(true)
        history.begin(item: item, movement: 0, position: 0)
        history.hear(item: item, movement: 0, position: 240, duration: 600, enabled: true)
        history.save(items: [item], movement: 0, position: 240)
        await history.flush()
        #expect(history.trouble != nil)
        #expect(reported == history.trouble)
        #expect(await server.queue?.position == 240_000)
        await server.setScrobbleFailure(false)
        history.hear(item: item, movement: 0, position: 500, duration: 600, enabled: true)
        await history.flush()
        #expect(await server.scrobbles.isEmpty)
        #expect(history.trouble != nil)
        history.begin(item: item, movement: 1, position: 0)
        history.hear(item: item, movement: 1, position: 240, duration: 600, enabled: true)
        await history.flush()
        #expect(history.trouble == nil)
        #expect(reported == nil)
        #expect(await server.scrobbles == ["first-0", "first-1"])
    }

    @Test func successfulScrobblesPreserveFailedQueueSaves() async throws {
        let server = InMemoryServer()
        let history = PlaybackHistory(server: server, defaults: try defaults())
        let item = item("first")
        await server.setFailure(true)
        history.save(items: [item], movement: 0, position: 0)
        await history.flush()
        await server.setFailure(false)
        history.begin(item: item, movement: 0, position: 0)
        history.hear(item: item, movement: 0, position: 240, duration: 600, enabled: true)
        await history.flush()
        #expect(await server.scrobbles == ["first-0"])
        #expect(history.trouble != nil)
        history.save(items: [item], movement: 0, position: 240)
        await history.flush()
        #expect(history.trouble == nil)
    }

    @Test func offlinePlaysPersistBeforeSendingAndReconnectWithOriginalTimes() async throws {
        let server = InMemoryServer()
        let defaults = try defaults()
        var clock = Date(timeIntervalSince1970: 1000)
        let history = PlaybackHistory(server: server, defaults: defaults, now: { clock })
        let first = item("first")
        await server.setFailure(true)
        for _ in 0..<2 {
            history.begin(item: first, movement: 0, position: 0)
            history.hear(item: first, movement: 0, position: 240, duration: 600, enabled: true)
            history.endListening()
            clock.addTimeInterval(600)
        }
        #expect(defaults.data(forKey: server.listeningDataKey + ".scrobbles") != nil)
        await history.flush()
        #expect(await server.scrobbles.isEmpty)
        // A play that cannot reach the server waits quietly: one status, no notice for each play.
        #expect(history.trouble == .unreachable)
        await server.setFailure(false)
        history.retryScrobbles()
        history.retryScrobbles()
        await history.flush()
        #expect(await server.scrobbles == ["first-0", "first-0"])
        #expect(await server.scrobbleTimes == [Date(timeIntervalSince1970: 1000), Date(timeIntervalSince1970: 1600)])
        #expect(history.trouble == nil)
        history.retryScrobbles()
        await history.flush()
        #expect(await server.scrobbles.count == 2)
    }

    @Test func relaunchRetainsPendingPlaysAndSeparatesAccounts() async throws {
        let server = InMemoryServer()
        let defaults = try defaults()
        let history = PlaybackHistory(server: server, defaults: defaults)
        await server.setFailure(true)
        history.hear(item: item("first"), movement: 0, position: 240, duration: 600, enabled: true)
        await history.flush()
        let other = InMemoryServer()
        let otherHistory = PlaybackHistory(server: other, defaults: defaults)
        otherHistory.retryScrobbles()
        await otherHistory.flush()
        #expect(await other.scrobbles.isEmpty)
        await server.setFailure(false)
        let relaunched = PlaybackHistory(server: server, defaults: defaults)
        relaunched.retryScrobbles()
        await relaunched.flush()
        #expect(await server.scrobbles == ["first-0"])
        let thirdLaunch = PlaybackHistory(server: server, defaults: defaults)
        thirdLaunch.retryScrobbles()
        await thirdLaunch.flush()
        #expect(await server.scrobbles == ["first-0"])
    }

    @Test func serverRefusalRetainsOnlyTheRefusedEventAcrossRelaunch() async throws {
        let server = InMemoryServer()
        let defaults = try defaults()
        let history = PlaybackHistory(server: server, defaults: defaults)
        await server.refuseSongs(["first-0"])
        history.hear(item: item("first"), movement: 0, position: 240, duration: 600, enabled: true)
        history.hear(item: item("first"), movement: 1, position: 240, duration: 600, enabled: true)
        await history.flush()
        #expect(history.trouble != nil)
        #expect(await server.scrobbles == ["first-1"])
        let relaunched = PlaybackHistory(server: server, defaults: defaults)
        relaunched.retryScrobbles()
        await relaunched.flush()
        #expect(relaunched.trouble != nil)
        #expect(await server.scrobbles == ["first-1"])
        await server.refuseSongs([])
        relaunched.retryScrobbles()
        await relaunched.flush()
        #expect(relaunched.trouble == nil)
        #expect(await server.scrobbles == ["first-1", "first-0"])
    }

    @Test func playsDuringAnInFlightSendRemainQueued() async throws {
        let server = InMemoryServer()
        let history = PlaybackHistory(server: server, defaults: try defaults())
        await server.suspendScrobble()
        history.hear(item: item("first"), movement: 0, position: 240, duration: 600, enabled: true)
        while !(await server.isScrobbling) { await Task.yield() }
        history.hear(item: item("second"), movement: 0, position: 240, duration: 600, enabled: true)
        history.retryScrobbles()
        await server.releaseScrobble()
        await history.flush()
        #expect(await server.scrobbles == ["first-0", "second-0"])
        #expect(await server.scrobbleAttempts == ["first-0", "second-0"])
    }

    @Test(arguments: [-1, 0, 1])
    func retentionKeepsNewestPlaysThroughLoadingInsertionAndRelaunch(overflow: Int) async throws {
        let server = InMemoryServer()
        let defaults = try defaults()
        let key = server.listeningDataKey + ".scrobbles"
        let limit = PlaybackHistory.scrobbleLimit
        let events = (0..<(limit + overflow)).map { index in
            ["token": UUID().uuidString, "song": "song-\(index)", "started": Double(index)] as [String: Any]
        }
        defaults.set(try JSONSerialization.data(withJSONObject: events), forKey: key)
        let history = PlaybackHistory(server: server, defaults: defaults)
        func savedSongs() throws -> [String] {
            let data = try #require(defaults.data(forKey: key))
            let saved = try #require(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
            return saved.compactMap { $0["song"] as? String }
        }
        #expect(try savedSongs() == (max(0, overflow)..<(limit + overflow)).map { "song-\($0)" })
        await server.setFailure(true)
        history.hear(item: item("new"), movement: 0, position: 240, duration: 600, enabled: true)
        #expect(try savedSongs().count == limit)
        #expect(try savedSongs().first == "song-\(overflow + 1)")
        #expect(try savedSongs().last == "new-0")
        await history.flush()
        let relaunched = PlaybackHistory(server: server, defaults: defaults)
        #expect(try savedSongs().count == limit)
        await server.setFailure(false)
        relaunched.retryScrobbles()
        await relaunched.flush()
        let expected = ((overflow + 1)..<(limit + overflow)).map { "song-\($0)" } + ["new-0"]
        #expect(await server.scrobbles == expected)
        #expect(try savedSongs().isEmpty)
    }

    @Test func reportsFailureAndRecoversOnTheNextSave() async throws {
        let server = InMemoryServer()
        let history = PlaybackHistory(server: server, defaults: try defaults())
        await server.setFailure(true)
        history.save(items: [item("first")], movement: 0, position: 0)
        await history.flush()
        #expect(history.trouble != nil)
        await server.setFailure(false)
        history.save(items: [item("first")], movement: 0, position: 12)
        await history.flush()
        #expect(history.trouble == nil)
        #expect(await server.queue?.position == 12_000)
    }
}
