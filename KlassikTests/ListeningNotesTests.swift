import Foundation
import SwiftUI
import Testing
import UIKit

@testable import Klassik

@MainActor
struct ListeningNotesTests {
    private func folder() -> URL {
        FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    }

    private func store(_ root: URL, user: String = "listener") -> DeviceStore {
        DeviceStore(
            server: URL(string: "https://music.example.org")!, username: user,
            folder: root.appending(path: "listeners"))
    }

    private func note(_ at: Double, _ end: Double? = nil) -> ListeningNote {
        ListeningNote(movement: 0, at: at, end: end, text: "\(at)")
    }

    private func song(_ id: String, work: String, track: Int, album: String = "disc") -> Song {
        Song(
            id: id, title: "Track \(track)", album: album, albumId: album, track: track, discNumber: 1,
            duration: 300, genres: [.init(name: "Classical")], displayComposer: "Felix Mendelssohn",
            works: [.init(name: work)])
    }

    @Test func draftStartsAtThePlayingSecondAndMarksAMoment() {
        let draft = NoteDraft(row: 2, at: 92.7)
        #expect(draft.row == 2)
        #expect(draft.at == 92)
        #expect(draft.end == nil)
    }

    @Test func endHereMakesASpanAndAnEarlierEndSwaps() {
        var draft = NoteDraft(row: 0, at: 300)
        draft.end(at: 340.4)
        #expect(draft.at == 300 && draft.end == 340)
        // A scrub back before the start: the end becomes the start.
        draft.end(at: 250)
        #expect(draft.at == 250 && draft.end == 300)
        // An end on the start leaves one moment.
        draft.end(at: 300.9)
        #expect(draft.at == 300 && draft.end == nil)
    }

    @Test func savedNotesStayInTheDeviceFileOnTheirMovement() throws {
        let root = folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let notes = ListeningNotes(store: store(root))
        let place = NotePlace(recording: "work|album", movement: 1)
        var span = NoteDraft(row: 1, at: 300)
        span.end(at: 340)
        span.text = "  Brass fanfare in C major. "
        var moment = NoteDraft(row: 1, at: 92)
        moment.text = "The cellos take the theme."
        #expect(notes.save(span, at: place))
        #expect(notes.save(moment, at: place))
        #expect(notes.notes(at: place).map(\.text) == ["The cellos take the theme.", "Brass fanfare in C major."])
        #expect(notes.notes(at: NotePlace(recording: "work|album", movement: 0)).isEmpty)
        #expect(notes.notes(at: NotePlace(recording: "other", movement: 1)).isEmpty)

        let relaunched = ListeningNotes(store: store(root))
        let kept = relaunched.notes(at: place)
        #expect(kept.map(\.at) == [92, 300])
        #expect(kept.map(\.end) == [nil, 340])
        #expect(kept.allSatisfy { $0.movement == 1 })
        #expect(ListeningNotes(store: store(root, user: "other")).notes(at: place).isEmpty)
    }

    @Test func aDraftWithoutTextKeepsNothing() throws {
        let root = folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let notes = ListeningNotes(store: store(root))
        var draft = NoteDraft(row: 0, at: 10)
        draft.text = " \n "
        #expect(notes.save(draft, at: NotePlace(recording: "r", movement: 0)))
        #expect(try store(root).load().notes.isEmpty)
    }

    /// Notes and favourites write one file. Neither may write an old copy over the other.
    @Test func notesAndFavouritesShareTheFile() throws {
        let root = folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = ListenerFile(store: store(root))
        let library = Library(
            cacheURL: root.appending(path: "library.json"),
            defaults: try #require(UserDefaults(suiteName: UUID().uuidString)))
        let order = RecordingOrder(library: library, file: file)
        let notes = ListeningNotes(file: file)
        let work = WorkIndex.Work(id: "w", title: "Work", composer: "Composer", isTagged: true, recordings: [])
        var draft = NoteDraft(row: 0, at: 5)
        draft.text = "Horn call."
        notes.save(draft, at: NotePlace(recording: "r", movement: 0))
        order.toggle(work)
        var later = NoteDraft(row: 0, at: 9)
        later.text = "Answer."
        notes.save(later, at: NotePlace(recording: "r", movement: 0))
        let data = try store(root).load()
        #expect(data.favouriteWorks == ["w"])
        #expect(data.notes["r"]?.map(\.text) == ["Horn call.", "Answer."])
    }

    @Test func aFileWithoutNotesLoads() throws {
        let root = folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let device = store(root)
        try FileManager.default.createDirectory(
            at: device.url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(#"{"favouriteWorks":["w"],"recordingOrder":{}}"#.utf8).write(to: device.url)
        let data = try device.load()
        #expect(data.favouriteWorks == ["w"])
        #expect(data.notes.isEmpty)
    }

    @Test func aFileThatDoesNotLoadRefusesANote() throws {
        let root = folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let device = store(root)
        try FileManager.default.createDirectory(
            at: device.url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: device.url)
        let notes = ListeningNotes(store: device)
        var draft = NoteDraft(row: 0, at: 1)
        draft.text = "Kept in the draft."
        #expect(!notes.save(draft, at: NotePlace(recording: "r", movement: 0)))
        #expect(notes.error != nil)
        #expect(try String(contentsOf: device.url, encoding: .utf8) == "not json")
    }

    @Test func overlappingNotesStackInLanes() {
        let first = note(10, 60)
        let inside = note(30)
        let alsoInside = note(31, 50)
        let after = note(70)
        let close = note(71)
        let lanes = ListeningNotes.lanes([after, inside, first, alsoInside, close], reach: 4)
        #expect(lanes[first.id] == 0)
        #expect(lanes[inside.id] == 1)
        #expect(lanes[alsoInside.id] == 2)
        // The span has ended, so the lowest lane is free again.
        #expect(lanes[after.id] == 0)
        // Two dots closer than one mark overlap.
        #expect(lanes[close.id] == 1)
        #expect(ListeningNotes.lanes([note(10), note(20), note(30)], reach: 4).values.allSatisfy { $0 == 0 })
    }

    @Test func theBarKeepsRoomForEveryLaneAboveTheFirst() {
        // A 600 s movement on a 360 pt bar: a mark is 10 s wide.
        func room(_ notes: [ListeningNote]) -> CGFloat {
            ListeningNotes.room(notes, duration: 600, width: 360)
        }
        let pitch = -Layout.noteDotTop
        // The first lane sits in the gap above the bar, so the first note does not move the bar.
        #expect(room([]) == 0)
        #expect(room([note(10, 60)]) == 0)
        #expect(room([note(10), note(100)]) == 0)
        // A span with two moments inside it uses three lanes.
        #expect(room([note(10, 60), note(30), note(30)]) == 2 * pitch)
        // Two moments 5 s apart overlap at the real width only.
        #expect(room([note(10), note(15)]) == pitch)
        #expect(ListeningNotes.room([note(10), note(15)], duration: 600, width: 0) == 0)
    }

    @Test func theRowHasTheRoomOfItsLanesInTheFirstLayout() {
        // The bar has no width of its own yet; the layout takes the room from the width that it proposes.
        func height(_ notes: [ListeningNote]) -> CGFloat {
            let bar = Color.clear.frame(height: Layout.positionBar).modifier(NoteRoom(notes: notes, duration: 600))
            return UIHostingController(rootView: bar).sizeThatFits(in: CGSize(width: 360, height: 1000)).height
        }
        let pitch = -Layout.noteDotTop
        #expect(height([]) == Layout.positionBar)
        #expect(height([note(10, 60)]) == Layout.positionBar)
        #expect(height([note(10), note(15)]) == Layout.positionBar + pitch)
        #expect(height([note(10, 60), note(30), note(30)]) == Layout.positionBar + 2 * pitch)
    }

    @Test func aTapFindsTheNearestMark() {
        let dot = note(100)
        let span = note(200, 260)
        let notes = [dot, span]
        #expect(ListeningNotes.note(near: 102, in: notes, reach: 3)?.id == dot.id)
        #expect(ListeningNotes.note(near: 230, in: notes, reach: 3)?.id == span.id)
        #expect(ListeningNotes.note(near: 262, in: notes, reach: 3)?.id == span.id)
        #expect(ListeningNotes.note(near: 150, in: notes, reach: 3) == nil)
    }

    @Test func aNoteReadsAsItsTimeOrItsSpan() {
        #expect(ListeningNotes.time(of: note(92)) == "1:32")
        #expect(ListeningNotes.time(of: note(300, 340)) == "5:00–5:40")
    }

    @Test func aRecordingPagePlacesNotesOnItsOwnMovements() {
        let songs = [song("a1", work: "Concerto", track: 1), song("a2", work: "Concerto", track: 2)]
        let index = WorkIndex(songs: songs)
        let recording = index.composers[0].works[0].recordings[0]
        #expect(
            NotePlace.places(in: recording, index: index) == [
                NotePlace(recording: recording.id, movement: 0), NotePlace(recording: recording.id, movement: 1),
            ])
    }

    /// A note written on an album track shows on the recording page of its work, and the other way round.
    @Test func anAlbumTrackPlacesItsNoteOnTheRecordingOfItsWork() throws {
        let songs = [
            song("t1", work: "Concerto", track: 1), song("t2", work: "Concerto", track: 2),
            song("t3", work: "Overture", track: 3),
        ]
        let index = WorkIndex(songs: songs)
        let album = try #require(WorkIndex.album(songs)).recording
        let concerto = try #require(index.composers[0].works.first { $0.title == "Concerto" }?.recordings.first)
        let overture = try #require(index.composers[0].works.first { $0.title == "Overture" }?.recordings.first)
        #expect(
            NotePlace.places(in: album, index: index) == [
                NotePlace(recording: concerto.id, movement: 0), NotePlace(recording: concerto.id, movement: 1),
                NotePlace(recording: overture.id, movement: 0),
            ])
        #expect(NotePlace.places(in: album, index: WorkIndex()) == [nil, nil, nil])
    }
}
