import Foundation
import Observation

/// A listening note on one recording: a movement, a time, an optional end and text (ADR 0013).
struct ListeningNote: Codable, Equatable, Identifiable, Sendable {
    var id = UUID()
    /// The position of the movement in its recording, from 0.
    var movement: Int
    /// Seconds into the movement.
    var at: Double
    /// The end of a span, always after `at`. A note without an end marks one moment.
    var end: Double?
    var text: String
}

/// Where a note sits: a recording and one of its movements.
struct NotePlace: Hashable, Sendable {
    var recording: String
    var movement: Int

    /// The place of each row of a page. A row of a recording page is a movement of that recording. A track of an
    /// album page belongs to the recording of its work on that album, so its notes show on both pages. A track that
    /// the work index does not hold has no place. One pass over the works, because a page asks for all its rows.
    static func places(in recording: WorkIndex.Recording, index: WorkIndex) -> [NotePlace?] {
        guard recording.isAlbum else {
            return recording.songs.indices.map { NotePlace(recording: recording.id, movement: $0) }
        }
        let ids = recording.songs.map { "\(WorkIndex.workKey($0))|\($0.albumKey)" }
        let wanted = Set(ids)
        var own: [String: WorkIndex.Recording] = [:]
        for work in index.composers.lazy.flatMap(\.works) {
            for candidate in work.recordings where wanted.contains(candidate.id) { own[candidate.id] = candidate }
        }
        return zip(recording.songs, ids).map { song, id -> NotePlace? in
            guard let movement = own[id]?.songs.firstIndex(where: { $0.id == song.id }) else { return nil }
            return NotePlace(recording: id, movement: movement)
        }
    }
}

/// A note while the listener writes it in the playing row (ADR 0027). It starts at the playing time; "End here"
/// marks a second time. The earlier of the two is the start, so a scrub back still gives a span.
struct NoteDraft: Equatable, Sendable {
    /// The row on the page that the draft belongs to.
    let row: Int
    private let start: Double
    private var mark: Double?
    var text = ""

    init(row: Int, at seconds: Double) {
        self.row = row
        start = Self.whole(seconds)
    }

    var at: Double { min(start, mark ?? start) }

    /// Nil while the note marks one moment.
    var end: Double? {
        guard let mark, mark != start else { return nil }
        return max(start, mark)
    }

    mutating func end(at seconds: Double) {
        mark = Self.whole(seconds)
    }

    /// The row shows whole seconds, so the note keeps the second that the listener saw.
    private static func whole(_ seconds: Double) -> Double { max(0, seconds.rounded(.down)) }
}

/// The listening notes of the listener. They stay in the device file (ADR 0013).
@MainActor @Observable
final class ListeningNotes {
    private let file: ListenerFile
    /// A failure of the device file after Save. The draft then stays open.
    private(set) var error: String?

    init(file: ListenerFile) {
        self.file = file
    }

    convenience init(store: DeviceStore?) {
        self.init(file: ListenerFile(store: store))
    }

    /// The notes of one movement, earliest first.
    func notes(at place: NotePlace) -> [ListeningNote] {
        (file.data.notes[place.recording] ?? []).filter { $0.movement == place.movement }
            .sorted { ($0.at, $0.end ?? $0.at) < ($1.at, $1.end ?? $1.at) }
    }

    /// Keeps a draft as a note. A draft without text keeps nothing. False when the device file refused it.
    @discardableResult
    func save(_ draft: NoteDraft, at place: NotePlace) -> Bool {
        let text = draft.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return true }
        var changed = file.data
        changed.notes[place.recording, default: []].append(
            ListeningNote(movement: place.movement, at: draft.at, end: draft.end, text: text))
        do {
            try file.save(changed)
            error = nil
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }

    /// The lane of each note above the movement's bar, 0 next to the bar (ADR 0014). Notes that overlap stack: each
    /// note takes the lowest lane that is free. A mark is `reach` seconds wide at least, so two dots close
    /// together do not cover each other.
    nonisolated static func lanes(_ notes: [ListeningNote], reach: Double) -> [UUID: Int] {
        var ends: [Double] = []
        var lanes: [UUID: Int] = [:]
        let half = max(reach, 0) / 2
        for note in notes.sorted(by: { ($0.at, $0.id.uuidString) < ($1.at, $1.id.uuidString) }) {
            let from = note.at - half
            let to = (note.end ?? note.at) + half
            if let free = ends.firstIndex(where: { $0 < from }) {
                ends[free] = to
                lanes[note.id] = free
            } else {
                lanes[note.id] = ends.count
                ends.append(to)
            }
        }
        return lanes
    }

    /// The seconds that a note mark covers on a bar `width` points wide. A bar without a width has no reach.
    nonisolated static func reach(width: Double, duration: Double) -> Double {
        width > 0 ? Double(Layout.noteDot) / width * duration : 0
    }

    /// The room above a bar `width` points wide for the lanes of `notes`.
    nonisolated static func room(_ notes: [ListeningNote], duration: Double, width: Double) -> CGFloat {
        let reach = reach(width: width, duration: duration)
        return Layout.noteRoom(lanes: laneCount(lanes(notes, reach: reach)))
    }

    /// The number of lanes that `lanes` uses: 0 for no notes.
    nonisolated static func laneCount(_ lanes: [UUID: Int]) -> Int {
        lanes.values.max().map { $0 + 1 } ?? 0
    }

    /// The note whose mark lies under a tap at `seconds`, within `reach` seconds, nearest first. A span counts along
    /// its length.
    nonisolated static func note(near seconds: Double, in notes: [ListeningNote], reach: Double) -> ListeningNote? {
        func distance(_ note: ListeningNote) -> Double {
            if seconds < note.at { return note.at - seconds }
            return max(0, seconds - (note.end ?? note.at))
        }
        return notes.filter { distance($0) <= reach }.min { distance($0) < distance($1) }
    }

    /// "1:32" for a moment, "1:32–2:12" for a span (specimen player.html `.note .at`).
    static func time(of note: ListeningNote) -> String {
        time(at: note.at, end: note.end)
    }

    static func time(at: Double, end: Double?) -> String {
        let start = PlaybackProgress.time(at)
        guard let end else { return start }
        return "\(start)–\(PlaybackProgress.time(end))"
    }
}
