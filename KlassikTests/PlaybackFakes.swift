import Foundation

@testable import Klassik

/// A server that lives in memory. It answers with addresses and holds no audio.
struct InMemoryServer: ServerPort {
    func streamURL(songID: String) -> URL {
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
