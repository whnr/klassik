import Foundation

/// What an engine tells the session. The engine sends nothing for a load that a later `load` or `discard` replaced.
enum PlaybackEngineEvent: Sendable {
    /// A movement played to its end.
    case movementEnded(Int)
    case loading(Bool)
    /// The engine scheduled a movement, so its exact length is known.
    case scheduled(Int)
    /// The audio hardware changed and the engine stopped.
    case configurationChanged
    /// Playback goes on, but something is wrong.
    case problem(String)
    /// Playback cannot go on.
    case failed(String)
}

/// Loads one track and returns its local file.
typealias PlaybackFileSource = @MainActor (Song) async throws -> URL

/// The seam under the playback session: it plays the movements of one recording, one after the other.
/// `GaplessEngine` is the production engine. A test uses a fake engine that reports ends and positions.
@MainActor
protocol PlaybackEngine: AnyObject {
    /// The session sets it once. The engine calls it on the main actor.
    var onEvent: (@MainActor (PlaybackEngineEvent) -> Void)? { get set }
    /// True while the engine can make sound.
    var isRunning: Bool { get }

    /// Drops what plays. Then plays `songs` from a movement and a position, and asks `file` for each track.
    func load(_ songs: [Song], from movement: Int, offset: Double, file: @escaping PlaybackFileSource)
    func pause()
    /// Plays on after `pause`. It throws if the audio session does not start.
    func resume() throws
    func discard()
    /// The volume change of the movement that plays, in decibels.
    func setGain(_ decibels: Float)
    /// Where playback is, if that movement or a later one has a place on the engine's timeline.
    func position(from movement: Int) -> (movement: Int, elapsed: Double)?
    /// The exact length of a scheduled movement, in seconds.
    func duration(of movement: Int) -> Double?
}
