import Foundation

/// What an engine tells the session. The engine sends nothing for a load that a later `load` or `discard` replaced.
public enum PlaybackEngineEvent: Sendable {
    /// A track played to its end, indexed across the loaded queue.
    case movementEnded(Int)
    case loading(Bool)
    /// Nothing sounds although the listener wants sound, or nil when sound starts (ADR 0060).
    case waiting(PlaybackWait?)
    /// The engine scheduled a movement, so its exact length is known.
    case scheduled(Int)
    /// The movement before this one played out, and this one has another sample rate or channel count than the graph.
    /// The engine never converts it (sz-u8f4). The host reloads from this movement, which gives a short gap.
    case formatChanged(Int)
    /// The audio hardware changed and the engine stopped.
    case configurationChanged
    /// Playback goes on, but something is wrong.
    case problem(String)
    /// Playback cannot go on.
    case failed(String)
    /// Playback cannot go on because the server or the network failed. It shows as the one quiet status.
    case serverFailed(PlaybackServerFailure)
}

/// Where the engine gets the bytes of one track.
public enum PlaybackSource: Sendable {
    /// A complete file on the device.
    case file(URL)
    /// A transfer that is still arriving. The engine decodes from its first bytes.
    case stream(TrackTransfer)
}

/// Gets one track: a complete file, or a transfer for a format that can start early.
public typealias PlaybackFileSource = @MainActor (PlaybackTrack) async throws -> PlaybackSource

/// The seam under the playback session: it plays the queue on one timeline.
/// `GaplessEngine` is the production engine. A test uses a fake engine that reports ends and positions.
@MainActor
public protocol PlaybackEngine: AnyObject {
    /// The session sets it once. The engine calls it on the main actor.
    var onEvent: (@MainActor (PlaybackEngineEvent) -> Void)? { get set }
    /// True while the engine can make sound.
    var isRunning: Bool { get }
    /// Playable audio ahead of the render position, in seconds, or nil before the first sound: decoded audio plus
    /// arrived encoded bytes that the decoder has not read (ADR 0060).
    var bufferedSeconds: Double? { get }
    /// The last movement that the load asked a source for, or nil when no load runs. Past the playing movement it
    /// means the engine reads the next track's transfer.
    var requestedMovement: Int? { get }

    /// Drops what plays. Then plays `songs` from a movement and a position, and asks `file` for each track.
    func load(_ songs: [PlaybackTrack], from movement: Int, offset: Double, file: @escaping PlaybackFileSource)
    /// Replaces the tracks of the load that it has not asked for yet, so a queue edit keeps the sound. False when
    /// the edit changes a track that the load already asked for, or when no load runs.
    func replace(_ songs: [PlaybackTrack]) -> Bool
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
    /// What the sound passes on its way to the output, or nil before the first track connects.
    var signalPath: PlaybackSignalPath? { get }
    /// False keeps the gain stage out of the next graph, so nothing scales the samples. The graph that plays keeps
    /// its stage until the host reloads.
    func useGainStage(_ on: Bool)
}

extension PlaybackEngine {
    public var signalPath: PlaybackSignalPath? { nil }
    public func useGainStage(_ on: Bool) {}
}

/// An engine failure for a format that iOS cannot decode.
struct UnsupportedFormat: LocalizedError {
    let reason: String
    var errorDescription: String? { reason }
}

/// What the engine knows of the path from the file to the output: its own graph and the formats that iOS reports.
/// The engine converts nothing, so any difference between the rates is a conversion by iOS.
public struct PlaybackSignalPath: Sendable, Equatable {
    /// The format of the graph: the sample rate and channel count of the file.
    public var engineRate: Double
    public var engineChannels: Int
    public var outputs: PlaybackOutputFormats
    /// The rate that the audio session reported after activation, or nil when it reported none.
    public var sessionRate: Double?
    /// True when a gain stage sits in the graph. With none, no stage scales the samples.
    public var gainStage: Bool

    public init(
        engineRate: Double, engineChannels: Int, outputs: PlaybackOutputFormats, sessionRate: Double? = nil,
        gainStage: Bool
    ) {
        self.engineRate = engineRate
        self.engineChannels = engineChannels
        self.outputs = outputs
        self.sessionRate = sessionRate
        self.gainStage = gainStage
    }
}

/// The sample rate and channel count at the output end of an engine's graph.
public struct PlaybackOutputFormats: Sendable, Equatable {
    /// The format that the mixer feeds the output node.
    public var mixerRate: Double
    public var mixerChannels: Int
    /// The format of the output hardware, as the output node reports it.
    public var hardwareRate: Double
    public var hardwareChannels: Int

    public init(mixerRate: Double, mixerChannels: Int, hardwareRate: Double, hardwareChannels: Int) {
        self.mixerRate = mixerRate
        self.mixerChannels = mixerChannels
        self.hardwareRate = hardwareRate
        self.hardwareChannels = hardwareChannels
    }
}
