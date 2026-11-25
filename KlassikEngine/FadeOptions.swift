import Foundation

/// The shape of a fade. Each curve gives the level of a fade-in as a function of the fraction of its length that has
/// passed. A fade-out is the same curve run backwards, so the two ends of a fade-out and a fade-in always match.
public enum FadeCurve: String, CaseIterable, Identifiable, Sendable {
    /// Half a cosine wave on linear gain. The curve of the app.
    case raisedCosine
    /// Sine up and cosine down: the powers of a fade-out and a fade-in at the same time add up to one.
    case equalPower
    /// An even fall in decibels down to `floorDecibels`, then silence.
    case decibelLinear
    /// The fifth-order smoothstep: flat slope at both ends.
    case smootherstep

    public var id: String { rawValue }

    /// The lowest level of `decibelLinear`, below which it cuts to silence.
    public static let floorDecibels = -60.0

    /// The level of a fade-in after `progress` of its length. It is exactly 0 at the start and exactly 1 at the end,
    /// and it never falls in between.
    public func rise(_ progress: Double) -> Double {
        if progress <= 0 { return 0 }
        if progress >= 1 { return 1 }
        switch self {
        case .raisedCosine: return 0.5 - 0.5 * cos(Double.pi * progress)
        case .equalPower: return sin(Double.pi / 2 * progress)
        case .decibelLinear: return pow(10, Self.floorDecibels * (1 - progress) / 20)
        case .smootherstep: return progress * progress * progress * (progress * (progress * 6 - 15) + 10)
        }
    }

    /// The level of a fade-out after `progress` of its length: exactly 1 at the start, exactly 0 at the end.
    public func fall(_ progress: Double) -> Double { rise(1 - progress) }
}

/// What a load does with the sound that still plays when it starts: a seek, or a skip.
public enum SeekMode: Sendable, Equatable {
    /// Fade the old sound out and load the new one at the same time. The two can overlap by a short time.
    case today
    /// Fade the old sound out, stay silent for `seconds`, then fade the new sound in. The two never overlap.
    case silence(seconds: Double)
    /// Keep the old sound until the new one is ready, then cross over with equal-power curves for the length of
    /// the fade-out.
    case crossfade

    /// The silence after the fade-out, in seconds.
    var gap: Double {
        guard case .silence(let seconds) = self else { return 0 }
        return max(seconds, 0)
    }
}

/// The fade settings of an engine. The defaults are the sound of the app.
public struct FadeOptions: Sendable, Equatable {
    public var outCurve: FadeCurve
    public var inCurve: FadeCurve
    public var outSeconds: Double
    public var inSeconds: Double
    public var seek: SeekMode

    public init(
        outCurve: FadeCurve = .raisedCosine, inCurve: FadeCurve = .raisedCosine, outSeconds: Double = 0.1,
        inSeconds: Double = 0.1, seek: SeekMode = .today
    ) {
        self.outCurve = outCurve
        self.inCurve = inCurve
        self.outSeconds = outSeconds
        self.inSeconds = inSeconds
        self.seek = seek
    }

    /// How long a node keeps running after its fade-out ends, so that the output latency of the device cannot cut
    /// the tail of the fade.
    static let stopMargin = 0.03

    /// The seconds that a load waits before it builds the new graph, when the old sound needs `stopWait` seconds to
    /// fade out and stop. Only the silence mode waits: the new sound starts `gap` seconds after the fade-out ends.
    /// The stop margin only keeps the old node alive, so it is silence that the set gap must not count twice.
    /// A load over a silent graph never waits.
    func newSoundDelay(stopWait: Double) -> Double {
        guard case .silence = seek, stopWait > 0 else { return 0 }
        return max(stopWait - Self.stopMargin, 0) + seek.gap
    }
}
