import Foundation
import Testing

@testable import Klassik

/// Automatic music stays inside the Music limit (ADR 0060). Old files go first, then speculative transfers, and
/// current playback stops last. A track larger than the limit plays from a rolling window. Explicit downloads
/// stay outside the limit.
@Suite(.serialized)
@MainActor
struct MusicStorageTests {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    let client = InMemoryServer()

    @MainActor final class Started {
        var ids: [String] = []
    }

    func makeStore(limit: Int64, _ started: Started = Started(), fetched: Data = Data()) throws -> TrackStore {
        let defaults = try #require(UserDefaults(suiteName: UUID().uuidString))
        defaults.set(limit, forKey: "store.cacheLimit")
        return TrackStore(
            cacheFolder: root.appending(path: "cache"), downloadFolder: root.appending(path: "downloads"),
            defaults: defaults,
            fetch: { _, _ in
                let file = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
                try fetched.write(to: file)
                return file
            },
            transport: { song, _, _ in started.ids.append(song.id) })
    }

    func song(_ id: String, suffix: String = "flac") -> Song { Song(id: id, title: id, suffix: suffix) }

    /// Writes a complete cache file. A larger `age` means an older file.
    func cached(_ id: String, bytes: Int, age: TimeInterval) throws {
        let folder = root.appending(path: "cache")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appending(path: "\(id).flac")
        try Data(count: bytes).write(to: file)
        try FileManager.default.setAttributes([.modificationDate: Date.now - age], ofItemAtPath: file.path())
    }

    func exists(_ id: String) -> Bool {
        FileManager.default.fileExists(atPath: root.appending(path: "cache/\(id).flac").path())
    }

    /// Writes on a dispatch worker. A blocked write waits there, and the main actor stays free for relief.
    nonisolated static func append(_ data: Data, to transfer: TrackTransfer, finish: Bool = true) async {
        await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                transfer.append(data)
                if finish { transfer.finish(nil) }
                continuation.resume()
            }
        }
    }

    func wait(until condition: () -> Bool) async throws {
        for _ in 0..<300 where !condition() { try await Task.sleep(for: .milliseconds(10)) }
    }

    func clean(_ store: TrackStore) {
        store.clearAll()
        try? FileManager.default.removeItem(at: root)
    }

    @Test func aBlockedWriteEvictsTheOldestFiles() async throws {
        try cached("old", bytes: 8, age: 300)
        try cached("recent", bytes: 4, age: 100)
        let store = try makeStore(limit: 16)
        defer { clean(store) }
        let playing = song("playing")
        store.pinned = [playing.id]
        store.playing = playing.id
        let transfer = store.transfer(for: playing, client: client)
        transfer.begin(length: 10, validator: nil)
        await Self.append(Data(0..<10), to: transfer)
        #expect(transfer.hasCompleteFile)
        #expect(!exists("old"))
        #expect(exists("recent"))
        try await wait { store.transfers.isEmpty }
        #expect(store.budget.storedBytes <= 16)
    }

    @Test func aSpeculativeTransferStopsWhenNothingElseCanGo() async throws {
        let store = try makeStore(limit: 8)
        defer { clean(store) }
        let playing = song("playing")
        let later = song("later")
        store.pinned = [playing.id]
        store.playing = playing.id
        store.wanted = [playing.id, later.id]
        let current = store.transfer(for: playing, client: client)
        current.begin(length: 6, validator: nil)
        await Self.append(Data(count: 6), to: current, finish: false)
        let speculative = store.transfer(for: later, client: client)
        speculative.begin(length: 6, validator: nil)
        await Self.append(Data(count: 6), to: speculative)
        await #expect(throws: TrackTransfer.Failure.cancelled) { try await speculative.finished() }
        #expect(store.transfers[later.id] == nil)
        #expect(store.transfers[playing.id] === current)
        #expect(!FileManager.default.fileExists(atPath: speculative.partial.path()))
        #expect(store.budget.storedBytes == 6)
    }

    @Test func currentPlaybackOutranksTheNextOpening() async throws {
        let store = try makeStore(limit: 8)
        defer { clean(store) }
        let playing = song("playing")
        let next = song("next")
        store.pinned = [playing.id, next.id]
        store.playing = playing.id
        let opening = store.transfer(for: next, client: client)
        opening.begin(length: 6, validator: nil)
        await Self.append(Data(count: 6), to: opening, finish: false)
        let current = store.transfer(for: playing, client: client)
        current.begin(length: 6, validator: nil)
        await Self.append(Data(count: 6), to: current)
        #expect(current.hasCompleteFile)
        await #expect(throws: TrackTransfer.Failure.cancelled) { try await opening.finished() }
    }

    /// The next opening waits for the current track to finish playing, rather than being cancelled for it.
    @Test func aBlockedNextOpeningWaitsForTheCurrentTrack() async throws {
        let store = try makeStore(limit: 8)
        defer { clean(store) }
        let playing = song("playing")
        let next = song("next")
        store.pinned = [playing.id, next.id]
        store.playing = playing.id
        do {
            // The decoder of a played track closes its file; this scope stands for that.
            let current = store.transfer(for: playing, client: client)
            current.begin(length: 6, validator: nil)
            await Self.append(Data(count: 6), to: current)
        }
        try await wait { store.transfers.isEmpty }
        let opening = store.transfer(for: next, client: client)
        opening.begin(length: 6, validator: nil)
        let writer = Task { await Self.append(Data(count: 6), to: opening) }
        try await Task.sleep(for: .milliseconds(700))
        #expect(store.transfers[next.id] === opening)
        #expect(opening.snapshot.available == 2)
        #expect(exists(playing.id))
        store.pinned = [next.id]
        store.playing = next.id
        await writer.value
        #expect(opening.hasCompleteFile)
        #expect(!exists(playing.id))
    }

    @Test func currentPlaybackFailsOnlyWhenNothingElseCanGo() async throws {
        let store = try makeStore(limit: 8)
        defer { clean(store) }
        let playing = song("playing")
        store.pinned = [playing.id]
        store.playing = playing.id
        let current = store.transfer(for: playing, client: client)
        // Without a length, the store cannot choose a rolling window, so the limit stops the write.
        current.begin(length: nil, validator: nil)
        await Self.append(Data(count: 10), to: current)
        await #expect(throws: TrackTransfer.Failure.storage) { try await current.finished() }
        #expect(!FileManager.default.fileExists(atPath: current.partial.path()))
        #expect(store.budget.storedBytes == 0)
        #expect(TrackTransfer.Failure.storage.localizedDescription.contains("space"))
    }

    @Test func aTrackLargerThanTheLimitPlaysFromARollingWindow() async throws {
        let store = try makeStore(limit: 32)
        defer { clean(store) }
        let large = song("large")
        let transfer = store.transfer(for: large, client: client)
        transfer.begin(length: 200, validator: nil)
        // A rolling window never becomes a file, so a whole-file consumer learns that at once.
        await #expect(throws: TrackTransfer.Failure.requiresCompleteFile) { try await transfer.finished() }
        let expected = Data(0..<200)
        let producer = Task { await Self.append(expected, to: transfer) }
        var actual = Data()
        for position in stride(from: 0, to: 200, by: 4) {
            let bytes = try await TrackTransferTests.readOnWorker(transfer, at: Int64(position), count: 4)
            actual.append(contentsOf: bytes)
            #expect(store.budget.storedBytes <= 16)
        }
        await producer.value
        #expect(actual == expected)
        #expect(!transfer.hasCompleteFile)
        try await wait { store.transfers.isEmpty }
        #expect(!store.isOffline(large))
        #expect(!FileManager.default.fileExists(atPath: transfer.target.path()))
    }

    @Test func anOversizedTrackThatCannotRollFailsAtItsHead() async throws {
        let store = try makeStore(limit: 32)
        defer { clean(store) }
        let transfer = store.transfer(for: song("large", suffix: "m4a"), client: client)
        transfer.begin(length: 200, validator: nil)
        await #expect(throws: TrackTransfer.Failure.exceedsStorage) { try await transfer.finished() }
        #expect(!FileManager.default.fileExists(atPath: transfer.partial.path()))
        #expect(TrackTransfer.Failure.exceedsStorage.localizedDescription.contains("Local Storage"))
    }

    @Test func anExplicitDownloadTakesPlaybackBytesOutsideTheLimit() async throws {
        let started = Started()
        let store = try makeStore(limit: 32, started)
        defer { clean(store) }
        let large = song("large")
        let playing = store.transfer(for: large, client: client)
        playing.begin(length: 200, validator: nil)
        await Self.append(Data(0..<8), to: playing, finish: false)
        #expect(store.budget.storedBytes == 8)
        let recording = WorkIndex.Recording(id: "recording", album: "Fixture", songs: [large])
        store.download(recording, title: "Fixture", client: client)
        try await wait { store.budget.storedBytes == 0 }
        #expect(store.budget.storedBytes == 0)
        await Self.append(Data(8..<200), to: playing)
        try await wait { store.isDownloaded(recording) }
        #expect(store.isDownloaded(recording))
        #expect(started.ids == [large.id])
        #expect(try Data(contentsOf: root.appending(path: "downloads/large.flac")) == Data(0..<200))
    }

    @Test func aWrappedWindowDownloadsTheTrackWhole() async throws {
        let started = Started()
        let whole = Data(0..<200)
        let store = try makeStore(limit: 32, started, fetched: whole)
        defer { clean(store) }
        let large = song("large")
        let playing = store.transfer(for: large, client: client)
        playing.begin(length: 200, validator: nil)
        let producer = Task { await Self.append(whole, to: playing, finish: false) }
        for position in stride(from: 0, to: 40, by: 4) {
            _ = try await TrackTransferTests.readOnWorker(playing, at: Int64(position), count: 4)
        }
        #expect(!playing.promote())
        let recording = WorkIndex.Recording(id: "recording", album: "Fixture", songs: [large])
        store.download(recording, title: "Fixture", client: client)
        try await wait { store.isDownloaded(recording) }
        #expect(store.isDownloaded(recording))
        #expect(try Data(contentsOf: root.appending(path: "downloads/large.flac")) == whole)
        playing.cancel()
        await producer.value
    }

    /// The rest of the preparation set loads again when needed; only playback's own files resist eviction.
    @Test func evictionKeepsTheCurrentTrackAndTheNextOpeningOnly() throws {
        try cached("current", bytes: 8, age: 300)
        try cached("next", bytes: 8, age: 200)
        try cached("later", bytes: 8, age: 100)
        let store = try makeStore(limit: 100)
        defer { clean(store) }
        store.pinned = ["current", "next"]
        store.wanted = ["current", "next", "later"]
        store.cacheLimit = 16
        #expect(exists("current"))
        #expect(exists("next"))
        #expect(!exists("later"))
    }

    @Test func aHeldTransferKeepsItsBytes() throws {
        let store = try makeStore(limit: 32)
        defer { clean(store) }
        let transfer = store.transfer(for: song("held"), client: client)
        transfer.begin(length: 4, validator: nil)
        transfer.hold(true)
        #expect(transfer.isHeld)
        transfer.append(Data([1, 2]))
        #expect(try TrackTransferTests.read(transfer, at: 0, count: 2) == [1, 2])
        transfer.hold(false)
        #expect(!transfer.isHeld)
    }
}
