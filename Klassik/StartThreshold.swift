import Foundation

/// How many playable seconds must be decoded before the first sound (ADR 0060).
enum StartThreshold {
    /// The least decoded audio before sound, unless the track is shorter.
    static let minimum = 0.25
    /// The target before the first delivery window of a network path.
    static let unmeasured = 2.0
    /// A slow start waits for this share of the deficit, at most over this many seconds of the track.
    static let deficitHorizon = 30.0

    /// `bitrate` is the encoded audio rate and `throughput` the delivered rate, both in bits per second.
    /// `remaining` is the rest of the track in seconds. A nil `throughput` means that the path has no window yet.
    /// Returns nil while nothing arrives: the start then waits for delivery.
    static func seconds(bitrate: Double, throughput: Double?, remaining: Double) -> Double? {
        let remaining = max(remaining, 0)
        guard let throughput else { return min(remaining, unmeasured) }
        guard bitrate > 0 else { return min(remaining, minimum) }
        let ratio = throughput / bitrate
        if ratio >= 1 { return min(remaining, max(minimum, 1 / ratio)) }
        if ratio > 0 { return min(remaining, 2 + (1 - ratio) * min(remaining, deficitHorizon)) }
        return nil
    }
}

/// The delivered rate of one transfer. Stalls count, because the windows end at the time of the question.
struct ThroughputMeter: Sendable {
    static let shortWindow = 0.25
    static let longWindow = 2.0

    private struct Arrival: Sendable {
        var time: Double
        var bytes: Int
    }

    private var started: Double?
    private var arrivals: [Arrival] = []

    /// A new network path starts a new measurement.
    mutating func start(at time: Double) {
        started = time
        arrivals = []
    }

    mutating func record(_ bytes: Int, at time: Double) {
        if started == nil { started = time }
        arrivals.append(Arrival(time: time, bytes: bytes))
        arrivals.removeAll { $0.time <= time - Self.longWindow }
    }

    /// The lower of the latest short-window rate and the moving average, in bits per second.
    /// Nil until the first short window has passed.
    func bitsPerSecond(at now: Double) -> Double? {
        guard let started, now - started >= Self.shortWindow else { return nil }
        func rate(_ window: Double) -> Double {
            let span = min(window, now - started)
            let bytes = arrivals.filter { $0.time > now - span }.reduce(0) { $0 + $1.bytes }
            return Double(bytes) * 8 / span
        }
        return min(rate(Self.shortWindow), rate(Self.longWindow))
    }
}

/// The encoded audio rate that the start threshold divides by, in bits per second.
enum AudioBitrate {
    static let mp3Floor = 320_000.0
    static let aacFloor = 512_000.0

    /// The estimate before packet timing: a floor for lossy formats, the PCM rate for lossless ones.
    /// A larger declared rate wins.
    static func initial(_ song: Song) -> Double {
        let declared = Double(song.bitRate ?? 0) * 1000
        let floor: Double
        switch song.suffix?.lowercased() {
        case "mp3": floor = mp3Floor
        case "aac", "m4a", "mp4": floor = aacFloor
        default:
            let rate = Double(song.samplingRate ?? 44_100)
            let channels = Double(song.channelCount ?? 2)
            let depth = Double(song.bitDepth ?? 16)
            floor = rate * channels * depth
        }
        return max(declared, floor)
    }

    /// The estimate after decoding: the greater of the declared rate and the rate that the decoder consumed.
    static func current(_ song: Song, observed: Double?) -> Double {
        guard let observed, observed > 0 else { return initial(song) }
        return max(Double(song.bitRate ?? 0) * 1000, observed)
    }
}
