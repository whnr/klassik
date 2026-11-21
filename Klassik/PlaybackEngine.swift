import Foundation

/// What an engine tells the session. The engine sends nothing for a load that a later `load` or `discard` replaced.
enum PlaybackEngineEvent: Sendable {
    /// A track played to its end, indexed across the loaded queue.
    case movementEnded(Int)
    case loading(Bool)
    /// Nothing sounds although the listener wants sound, or nil when sound starts (ADR 0060).
    case waiting(PlaybackWait?)
    /// The engine scheduled a movement, so its exact length is known.
    case scheduled(Int)
    /// The audio hardware changed and the engine stopped.
    case configurationChanged
    /// Playback goes on, but something is wrong.
    case problem(String)
    /// Playback cannot go on.
    case failed(String)
}

/// Where the engine gets the bytes of one track.
enum PlaybackSource: Sendable {
    /// A complete file on the device.
    case file(URL)
    /// A transfer that is still arriving. The engine decodes from its first bytes.
    case stream(TrackTransfer)
}

/// Gets one track: a complete file, or a transfer for a format that can start early.
typealias PlaybackFileSource = @MainActor (Song) async throws -> PlaybackSource

/// The seam under the playback session: it plays the queue on one timeline.
/// `GaplessEngine` is the production engine. A test uses a fake engine that reports ends and positions.
@MainActor
protocol PlaybackEngine: AnyObject {
    /// The session sets it once. The engine calls it on the main actor.
    var onEvent: (@MainActor (PlaybackEngineEvent) -> Void)? { get set }
    /// True while the engine can make sound.
    var isRunning: Bool { get }
    /// Decoded audio that waits ahead of the render position, in seconds, or nil before the first sound.
    var bufferedSeconds: Double? { get }

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
