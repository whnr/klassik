import Foundation
import KlassikEngine

/// One test case: the two movements of one work. The Lab album holds each case as its own disc.
struct LabCase: Identifiable, Hashable, Sendable {
    var id: Int
    var title: String
    var songs: [LabSong]

    /// Formats that iOS cannot decode. The Lab lists them and refuses to play them.
    private static let unsupportedSuffixes: Set<String> = ["opus", "ogg", "oga"]

    var tracks: [PlaybackTrack] { songs.map(\.playbackTrack) }

    var unsupportedReason: String? {
        guard let suffix = songs.first?.suffix?.lowercased(), Self.unsupportedSuffixes.contains(suffix) else {
            return nil
        }
        return "\(suffix.uppercased()) is not supported on iOS"
    }

    /// A gap that this case has by design. An MP3 file without the LAME or Xing header has no record of its encoder
    /// delay, so the engine plays it whole and the join is approximate (ADR 0005).
    var gapNote: String? {
        guard songs.first?.suffix?.lowercased() == "mp3", title.lowercased().contains("without header") else {
            return nil
        }
        return "This MP3 has no gapless header: the file carries no delay and padding data. A gap at the join is expected."
    }

    /// The source format of the case, such as "FLAC 24-bit 96 kHz". A rate change inside the case shows both rates.
    var sourceLine: String {
        guard let first = songs.first else { return "" }
        var parts = [(first.suffix ?? "?").uppercased()]
        if let depth = first.bitDepth, depth > 0 { parts.append("\(depth)-bit") }
        let rates = songs.compactMap(\.samplingRate).filter { $0 > 0 }
        var distinct: [Int] = []
        for rate in rates where !distinct.contains(rate) { distinct.append(rate) }
        if !distinct.isEmpty { parts.append(distinct.map(Self.kilohertz).joined(separator: " then ") + " kHz") }
        if let rate = first.bitRate, rate > 0, (first.bitDepth ?? 0) == 0 { parts.append("\(rate) kbit/s") }
        return parts.joined(separator: " ")
    }

    /// 44100 is "44.1", 96000 is "96".
    static func kilohertz(_ hertz: Int) -> String {
        let value = Double(hertz) / 1000
        return value == value.rounded() ? String(Int(value)) : String(format: "%g", value)
    }

    /// The cases of the album, in disc order. A song without a disc number joins disc 1.
    static func cases(from songs: [LabSong]) -> [LabCase] {
        let discs = Dictionary(grouping: songs) { $0.discNumber ?? 1 }
        return discs.keys.sorted().map { disc in
            let ordered = (discs[disc] ?? []).enumerated()
                .sorted { ($0.element.track ?? $0.offset, $0.offset) < ($1.element.track ?? $1.offset, $1.offset) }
                .map(\.element)
            return LabCase(id: disc, title: title(of: ordered, disc: disc), songs: ordered)
        }
    }

    /// The work tag, else the folder name without its number, else the disc number.
    private static func title(of songs: [LabSong], disc: Int) -> String {
        if let work = songs.lazy.compactMap({ $0.works?.first?.name }).first, !work.isEmpty { return work }
        let folder = songs.lazy.compactMap { $0.path }.compactMap { path -> String? in
            let parts = path.split(separator: "/")
            return parts.count >= 2 ? String(parts[parts.count - 2]) : nil
        }.first
        if let folder {
            let name = folder.replacing(/^\d+\s+/, with: "")
            if !name.isEmpty { return name }
        }
        return "Case \(disc)"
    }
}
