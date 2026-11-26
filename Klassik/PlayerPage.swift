import Foundation

/// What the page of a recording or album shows: the header holds what every track shares, and a
/// row holds only the names that differ for its track.
struct PlayerPage: Sendable {
    /// The composer that every track names, if there is one.
    let composer: String?
    /// The names that every track shares, then the album as a labelled line.
    let header: [Roles.Line]
    /// The year and the length in prose, under the names.
    let facts: String
    /// For each track, the names that differ from the header. A composer that the header does not show leads.
    let differing: [[Roles.Line]]

    /// The label of a composer line in a row. A row has no other composer line, so the label marks it.
    static let composerLabel = "composer"

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
        header = lines
        facts = Self.facts(of: recording)
        let shown = composer
        differing = zip(songs, split.tracks).map { song, lines in
            let name = song.composerName
            guard shown == nil, name != Song.unknownComposer else { return lines }
            return [Roles.Line(kind: .other, label: Self.composerLabel, names: [name])] + lines
        }
    }

    /// True if the row of a track holds names. A row with nothing does not open.
    func opens(_ index: Int) -> Bool {
        differing.indices.contains(index) && differing[index].contains { !$0.names.isEmpty }
    }

    /// "Recorded in 1972. 42 minutes, 4 movements." A recording of one movement gives only its length.
    static func facts(of recording: WorkIndex.Recording) -> String {
        var sentences: [String] = []
        if let year = year(of: recording) { sentences.append("Recorded in \(year).") }
        var measures: [String] = []
        let seconds = recording.songs.compactMap(\.duration).reduce(0, +)
        if let length = WorkIndex.Recording.duration(seconds) { measures.append(length) }
        let count = recording.songs.count
        if recording.isAlbum {
            measures.append(WorkIndex.Recording.count(count, "track"))
        } else if let completeness = recording.completeness {
            measures.append(completeness)
        } else if count > 1 {
            measures.append(WorkIndex.Recording.count(count, "movement"))
        }
        if !measures.isEmpty { sentences.append(measures.joined(separator: ", ") + ".") }
        return sentences.joined(separator: " ")
    }

    /// A recording shows the year its tracks carry, because the album year can belong to another recording of a box
    /// set. An album shows its own year.
    static func year(of recording: WorkIndex.Recording) -> Int? {
        let years = Set(recording.songs.compactMap(\.year))
        if years.count == 1 { return years.first }
        return recording.isAlbum ? recording.year : nil
    }
}

/// When the player may scroll by itself: only after a quiet spell without touches, and never while
/// a scrub on the timeline or a note being written holds the rows still.
struct QuietSpell: Sendable {
    /// specimen player.html waits 8000 ms.
    static let length = Duration.seconds(8)

    private var lastTouch: ContinuousClock.Instant?
    private(set) var isHeld = false
    private(set) var isTouched = false
    private(set) var isWriting = false

    mutating func touch(at now: ContinuousClock.Instant = .now) {
        lastTouch = now
    }

    /// A scrub starts a hold. The spell begins when the finger lifts.
    mutating func hold(_ on: Bool, at now: ContinuousClock.Instant = .now) {
        isHeld = on
        lastTouch = now
    }

    /// A finger on the rows, or a scroll that it started, holds them. The spell begins when they are still.
    /// A call with no change does nothing, so a scroll by the app itself starts no spell.
    mutating func touching(_ on: Bool, at now: ContinuousClock.Instant = .now) {
        guard on != isTouched else { return }
        isTouched = on
        lastTouch = now
    }

    /// An open note holds the rows. Its own flag, so a scrub that ends while the note is open keeps the hold.
    /// The spell begins when the note closes: in the specimen, the Save tap is a touch.
    mutating func writing(_ on: Bool, at now: ContinuousClock.Instant = .now) {
        guard on != isWriting else { return }
        isWriting = on
        lastTouch = now
    }

    /// How long the page must still wait, or nil when it may scroll now.
    func wait(at now: ContinuousClock.Instant = .now) -> Duration? {
        if isHeld || isTouched || isWriting { return Self.length }
        guard let lastTouch else { return nil }
        let rest = Self.length - (now - lastTouch)
        return rest > .zero ? rest : nil
    }

    /// A scroll request can miss a lazy row. Keep trying during the quiet spell, as the specimen does.
    func follow(at now: ContinuousClock.Instant = .now) -> Bool {
        wait(at: now) == nil
    }
}

/// What the player shows after its rows.
enum PlayerTail: Equatable, Sendable {
    /// The row of the next queue item, which becomes the player when the playing item ends.
    case next(UUID)
    /// The item plays, and no item follows it.
    case endsHere
    /// The player shows an item that does not play.
    case nothing

    /// `upNext` holds the queue after the item. The player closes when no item plays.
    init(isPlaying: Bool, upNext: [UUID]) {
        self = isPlaying ? upNext.first.map(Self.next) ?? .endsHere : .nothing
    }
}
