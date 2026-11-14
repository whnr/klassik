import Foundation

/// What the page of a recording or album shows (ADR 0015, 0027): the header holds what every track shares, and a
/// row holds only the names that differ for its track.
struct PlayerPage: Sendable {
    /// The composer that every track names, if there is one.
    let composer: String?
    /// The names that every track shares, then the album and the year as labelled lines.
    let header: [Roles.Line]
    /// For each track, the names that differ from the header.
    let differing: [[Roles.Line]]

    init(recording: WorkIndex.Recording) {
        let songs = recording.songs
        let split = Roles.split(songs)
        let composers = Set(songs.map(\.composerName))
        composer = composers.count == 1 ? composers.first.flatMap { $0 == Song.unknownComposer ? nil : $0 } : nil
        var lines = split.shared
        // An album page is named by its album, so the header does not say it twice.
        if !recording.isAlbum, !recording.album.isEmpty {
            lines.append(Roles.Line(kind: .other, label: "album", names: [recording.album]))
        }
        if let year = Self.year(of: recording) {
            lines.append(Roles.Line(kind: .other, label: "year", names: [String(year)]))
        }
        header = lines
        differing = split.tracks
    }

    /// True if the row of a track holds names. A row with nothing does not open.
    func opens(_ index: Int) -> Bool {
        differing.indices.contains(index) && differing[index].contains { !$0.names.isEmpty }
    }

    /// A recording shows the year its tracks carry, because the album year can belong to another recording of a box
    /// set. An album shows its own year.
    static func year(of recording: WorkIndex.Recording) -> Int? {
        let years = Set(recording.songs.compactMap(\.year))
        if years.count == 1 { return years.first }
        return recording.isAlbum ? recording.year : nil
    }
}

/// When the player page may scroll by itself (ADR 0027): only after a quiet spell without touches, and never while
/// a scrub on the timeline holds the rows still.
struct QuietSpell: Sendable {
    static let length = Duration.seconds(3)

    private var lastTouch: ContinuousClock.Instant?
    private(set) var isHeld = false

    mutating func touch(at now: ContinuousClock.Instant = .now) {
        lastTouch = now
    }

    /// A scrub starts a hold. The spell begins when the finger lifts.
    mutating func hold(_ on: Bool, at now: ContinuousClock.Instant = .now) {
        isHeld = on
        lastTouch = now
    }

    /// How long the page must still wait, or nil when it may scroll now.
    func wait(at now: ContinuousClock.Instant = .now) -> Duration? {
        if isHeld { return Self.length }
        guard let lastTouch else { return nil }
        let rest = Self.length - (now - lastTouch)
        return rest > .zero ? rest : nil
    }
}
