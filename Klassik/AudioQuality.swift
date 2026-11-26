import Foundation
import KlassikEngine

/// The quality line of the player: what the file is, what the output runs at, and whether anything changes the
/// samples on the way. It states only what the app and iOS report. It never says "bit-perfect" as a fact, because
/// no check of the samples at the output exists (sz-u8f4).
enum AudioQuality {
    private static let lossless: Set<String> = ["flac", "wav", "aiff", "aif"]
    private static let lossy: Set<String> = ["mp3", "aac", "opus", "ogg", "oga"]

    /// The line for the playing track, or nil when there is nothing to say yet.
    static func line(track: PlaybackTrack, path: PlaybackSignalPath?) -> String? {
        if let reason = track.unsupportedFormat { return reason }
        var parts = [source(of: track, path: path)]
        guard let path else { return parts.joined(separator: " · ") }
        let output = outputRate(path)
        parts.append("output \(kilohertz(output)) kHz")
        let processing = self.processing(path, output: output)
        if processing.isEmpty {
            let suffix = track.suffix?.lowercased() ?? ""
            if lossy.contains(suffix) { parts.append("lossy source") }
            parts.append("bit-perfect not verified")
        } else {
            parts.append("processing active: " + processing.joined(separator: ", "))
        }
        return parts.joined(separator: " · ")
    }

    /// The format of the file, such as "FLAC 24-bit 96 kHz". The server's tags give the bit depth; the graph gives
    /// the rate when the server sent none.
    static func source(of track: PlaybackTrack, path: PlaybackSignalPath?) -> String {
        var words: [String] = []
        if let suffix = track.suffix, !suffix.isEmpty { words.append(suffix.uppercased()) }
        if let depth = track.bitDepth, depth > 0 { words.append("\(depth)-bit") }
        let rate = track.samplingRate.map(Double.init) ?? path?.engineRate ?? 0
        if rate > 0 { words.append("\(kilohertz(rate)) kHz") }
        return words.isEmpty ? "unknown format" : words.joined(separator: " ")
    }

    /// The rate of the output hardware, else the rate that the session reported.
    static func outputRate(_ path: PlaybackSignalPath) -> Double {
        path.outputs.hardwareRate > 0 ? path.outputs.hardwareRate : path.sessionRate ?? 0
    }

    /// What changes the samples. The app converts nothing, so a rate or channel difference is iOS at work.
    static func processing(_ path: PlaybackSignalPath, output: Double) -> [String] {
        var found: [String] = []
        if path.gainStage { found.append("ReplayGain stage in the path") }
        if output > 0, output != path.engineRate { found.append("iOS converts to \(kilohertz(output)) kHz") }
        if path.outputs.mixerChannels != path.engineChannels || path.outputs.hardwareChannels != path.engineChannels {
            found.append("iOS changes the channels")
        }
        return found
    }

    /// 44100 gives "44.1", 96000 gives "96".
    static func kilohertz(_ hertz: Double) -> String {
        guard hertz > 0 else { return "unknown" }
        return (hertz / 1000).formatted(.number.precision(.fractionLength(0...1)).locale(Locale(identifier: "en_US")))
    }
}
