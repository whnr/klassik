import Foundation

/// What the page of a recording or album shows (ADR 0014, 0027): the header holds what every track shares, and a
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

/// When the player may scroll by itself (ADR 0027): only after a quiet spell without touches, and never while
/// a scrub on the timeline holds the rows still.
struct QuietSpell: Sendable {
    /// specimen player.html waits 8000 ms.
    static let length = Duration.seconds(8)

    private var lastTouch: ContinuousClock.Instant?
    /// The movement and the touch of the last follow. The page follows again only when one of them changes,
    /// so a still page does not scroll each second.
    private var followed: (movement: Int, touch: ContinuousClock.Instant?)?
    private(set) var isHeld = false
    private(set) var isTouched = false

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

    /// How long the page must still wait, or nil when it may scroll now.
    func wait(at now: ContinuousClock.Instant = .now) -> Duration? {
        if isHeld || isTouched { return Self.length }
        guard let lastTouch else { return nil }
        let rest = Self.length - (now - lastTouch)
        return rest > .zero ? rest : nil
    }

    /// True when the page should bring the playing row back now. Then the follow counts as done.
    mutating func follow(_ movement: Int, at now: ContinuousClock.Instant = .now) -> Bool {
        guard wait(at: now) == nil else { return false }
        if let followed, followed.movement == movement, followed.touch == lastTouch { return false }
        followed = (movement, lastTouch)
        return true
    }
}

/// What the player shows after its rows (ADR 0014).
enum PlayerTail: Equatable, Sendable {
    /// The row of the next queue item, which becomes the player when the playing item ends.
    case next(UUID)
    /// The item plays, and no item follows it.
    case endsHere
    /// The player shows an item that does not play.
    case nothing

    /// `upNext` holds the queue after the item. The player closes when no item plays (ADR 0053).
    init(isPlaying: Bool, upNext: [UUID]) {
        self = isPlaying ? upNext.first.map(Self.next) ?? .endsHere : .nothing
    }
}
