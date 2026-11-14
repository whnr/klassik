import Foundation

@testable import Klassik

/// A server that lives in memory. It answers with addresses and holds no audio.
actor InMemoryServer: ServerPort {
    nonisolated let listeningDataKey = "queue.\(UUID().uuidString)"
    var queue: ServerPlayQueue?
    var scrobbles: [String] = []
    var scrobbleTimes: [Date] = []
    var scrobbleFailure = false
    var savedQueues: [[String]] = []
    var failure = false
    var restoreGate: CheckedContinuation<ServerPlayQueue?, Never>?
    var holdRestore = false
    var isRestoring: Bool { restoreGate != nil }

    func getPlayQueue() async throws -> ServerPlayQueue? {
        if holdRestore { return await withCheckedContinuation { restoreGate = $0 } }
        if failure { throw URLError(.notConnectedToInternet) }
        return queue
    }

    func savePlayQueue(ids: [String], current: String?, position: Int64) async throws {
        if failure { throw URLError(.notConnectedToInternet) }
        savedQueues.append(ids)
        let songs = ids.map { Song(id: $0, title: $0, duration: 600) }
        queue = ServerPlayQueue(current: current, position: position, entry: songs)
    }

    func scrobble(id: String, time: Date) async throws {
        if scrobbleFailure { throw URLError(.badServerResponse) }
        if failure { throw URLError(.notConnectedToInternet) }
        scrobbles.append(id)
        scrobbleTimes.append(time)
    }

    func setQueue(_ queue: ServerPlayQueue?) { self.queue = queue }
    func setScrobbleFailure(_ value: Bool) { scrobbleFailure = value }
    func setFailure(_ value: Bool) { failure = value }
    func suspendRestore() { holdRestore = true }
    func releaseRestore(_ queue: ServerPlayQueue?) {
        restoreGate?.resume(returning: queue)
        restoreGate = nil
    }

    nonisolated func streamURL(songID: String) -> URL {
        URL(string: "https://music.example.org/stream/\(songID)")!
    }
}

/// An engine that plays nothing. It records what the session asks for, and a test makes it report positions
/// and movement ends.
@MainActor
final class FakeEngine: PlaybackEngine {
    struct Load: Equatable {
        var songs: [String]
        var movement: Int
        var offset: Double
    }

    enum Call: Equatable {
        case load(Load)
        case pause
        case resume
        case discard
    }

    var onEvent: (@MainActor (PlaybackEngineEvent) -> Void)?
    private(set) var isRunning = false
    private(set) var calls: [Call] = []
    private(set) var gain: Float = 0
    private(set) var file: PlaybackFileSource?
    private var songCount = 0
    /// What `position(from:)` answers. A load sets it to the place that it starts at.
    var playing: (movement: Int, elapsed: Double)?
    /// The exact length of scheduled movements.
    var lengths: [Int: Double] = [:]
    var resumeError: (any Error)?

    var loads: [Load] {
        calls.compactMap { call in
            if case .load(let load) = call { load } else { nil }
        }
    }

    func load(_ songs: [Song], from movement: Int, offset: Double, file: @escaping PlaybackFileSource) {
        calls.append(.load(Load(songs: songs.map(\.id), movement: movement, offset: offset)))
        self.file = file
        songCount = songs.count
        isRunning = true
        playing = (movement, offset)
    }

    func pause() {
        calls.append(.pause)
    }

    func resume() throws {
        calls.append(.resume)
        if let resumeError { throw resumeError }
    }

    func discard() {
        calls.append(.discard)
        isRunning = false
        playing = nil
    }

    func setGain(_ decibels: Float) {
        gain = decibels
    }

    func position(from movement: Int) -> (movement: Int, elapsed: Double)? {
        playing
    }

    func duration(of movement: Int) -> Double? {
        lengths[movement]
    }

    /// A movement plays to its end and the next one begins.
    func end(_ movement: Int) {
        if movement + 1 < songCount { playing = (movement + 1, 0) }
        onEvent?(.movementEnded(movement))
    }

    func report(_ event: PlaybackEngineEvent) {
        onEvent?(event)
    }
}
