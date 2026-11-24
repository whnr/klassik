import Foundation

/// What the engine knows about one track. The app maps its own track model to this value, so the engine needs no
/// server model.
public struct PlaybackTrack: Sendable, Hashable, Identifiable {
    /// Gains in decibels. A peak is the highest sample, where 1 is full scale.
    public struct ReplayGain: Sendable, Hashable {
        public var trackGain: Double?
        public var albumGain: Double?
        public var trackPeak: Double?
        public var albumPeak: Double?
        public var fallbackGain: Double?

        public init(
            trackGain: Double? = nil, albumGain: Double? = nil, trackPeak: Double? = nil, albumPeak: Double? = nil,
            fallbackGain: Double? = nil
        ) {
            self.trackGain = trackGain
            self.albumGain = albumGain
            self.trackPeak = trackPeak
            self.albumPeak = albumPeak
            self.fallbackGain = fallbackGain
        }
    }

    public var id: String
    /// Seconds, as the server declares it.
    public var duration: Int?
    /// The file suffix, such as "flac".
    public var suffix: String?
    /// Kilobits per second, as the server declares it.
    public var bitRate: Int?
    public var samplingRate: Int?
    public var bitDepth: Int?
    public var channelCount: Int?
    public var replayGain: ReplayGain?

    public init(
        id: String, duration: Int? = nil, suffix: String? = nil, bitRate: Int? = nil, samplingRate: Int? = nil,
        bitDepth: Int? = nil, channelCount: Int? = nil, replayGain: ReplayGain? = nil
    ) {
        self.id = id
        self.duration = duration
        self.suffix = suffix
        self.bitRate = bitRate
        self.samplingRate = samplingRate
        self.bitDepth = bitDepth
        self.channelCount = channelCount
        self.replayGain = replayGain
    }

    /// True when the decoder can start from the first bytes of this format.
    public var canStartEarly: Bool { StreamDecoder.canStartEarly(self) }
}

/// The stage that sets the volume of a track. A host that wants no ReplayGain in its signal path passes
/// `NoGainStage` and builds the engine without a gain node.
public protocol GainStage: Sendable {
    /// The volume change of one track, in decibels.
    func gain(for track: PlaybackTrack) -> Float
}

/// A stage that never changes the volume.
public struct NoGainStage: GainStage {
    public init() {}

    public func gain(for track: PlaybackTrack) -> Float { 0 }
}

/// What the engine reports while the listener waits for sound.
public struct PlaybackWait: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        /// No sound yet for this selection.
        case start
        /// Sound stopped because the bytes did not arrive in time.
        case resume
    }

    public var kind: Kind
    /// True when the measured throughput is below the bitrate that the track needs.
    public var slow: Bool

    public init(kind: Kind, slow: Bool) {
        self.kind = kind
        self.slow = slow
    }
}

/// A failure of the server or the network that stops playback. It shows as the one quiet status.
public enum PlaybackServerFailure: Equatable, Sendable {
    /// No answer: no connection, or the server is down.
    case unreachable
    /// The server answered and refused.
    case refused
}

/// Names the server failures of the host. The engine asks it for every error that ends a load.
public protocol PlaybackFailureMapper: Sendable {
    /// Nil when the device failed, not the server.
    func serverFailure(for error: any Error) -> PlaybackServerFailure?
}

/// The failures that the engine itself can name: the network and the transfer.
public struct TransferFailureMapper: PlaybackFailureMapper {
    public init() {}

    public func serverFailure(for error: any Error) -> PlaybackServerFailure? {
        if error is URLError { return .unreachable }
        guard let failure = error as? TrackTransfer.Failure else { return nil }
        switch failure {
        case .timedOut, .truncated: return .unreachable
        case .http: return .refused
        default: return nil
        }
    }
}
