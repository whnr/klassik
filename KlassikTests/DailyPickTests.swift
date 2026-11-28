import Foundation
import Testing

@testable import Klassik

@MainActor
struct DailyPickTests {
    /// One track of a work. `movement` is its number and the total that the tags give, or nil for no movement tags.
    private static func song(
        _ id: String, work: String, album: String, movement: (number: Int, total: Int?)? = nil,
        composer: String = "Frédéric Chopin", conductor: String? = "Conductor"
    ) -> Song {
        var song = LibraryPageTests.song(
            id, composer: composer, work: work, album: album, conductor: conductor)
        song.movements = movement.map { [Song.Movement(name: "M", number: $0.number, count: $0.total)] }
        return song
    }

    private func row(_ id: String = "pick") -> LibraryRowSetup { LibraryRowSetup(kind: .pick, id: id) }

    private func drawn(_ index: WorkIndex, day: Int = 10) -> LibraryPage.Pick? {
        LibraryPageTests.page(rows: [row()], day: day, index: index).sections.first?.pick
    }

    /// Four complete albums, one work and one track each.
    private static let whole = WorkIndex(
        songs: (1...4).map { song("w\($0)", work: "Work \($0)", album: "Whole \($0)") })

    // MARK: Complete

    @Test func oneTrackWithoutMovementTagsIsComplete() {
        let index = WorkIndex(songs: [Self.song("a", work: "W", album: "A")])
        #expect(index.composers[0].works[0].recordings[0].isComplete)
    }

    @Test func aTotalWithEveryMovementIsComplete() {
        let songs = (1...3).map { Self.song("m\($0)", work: "W", album: "A", movement: ($0, 3)) }
        #expect(WorkIndex(songs: songs).composers[0].works[0].recordings[0].isComplete)
    }

    @Test func aMissingMovementIsNotComplete() {
        let songs = [1, 3].map { Self.song("m\($0)", work: "W", album: "A", movement: ($0, 3)) }
        #expect(!WorkIndex(songs: songs).composers[0].works[0].recordings[0].isComplete)
    }

    @Test func movementTagsWithoutATotalGiveNoProof() {
        let songs = (1...2).map { Self.song("m\($0)", work: "W", album: "A", movement: ($0, nil)) }
        #expect(!WorkIndex(songs: songs).composers[0].works[0].recordings[0].isComplete)
    }

    @Test func trackNumbersDoNotDecideAnAlbum() {
        // Track 2 and 3 only: the tags prove nothing is missing, the numbers are not read.
        var first = Self.song("a", work: "W", album: "A")
        first.track = 2
        var second = Self.song("b", work: "V", album: "A")
        second.track = 3
        #expect(WorkIndex(songs: [first, second]).albums[0].isComplete)
    }

    @Test func anAlbumWithAMissingMovementIsNotComplete() {
        let songs = [1, 3].map { Self.song("m\($0)", work: "W", album: "A", movement: ($0, 3)) }
        #expect(!WorkIndex(songs: songs).albums[0].isComplete)
    }

    @Test func anAlbumTrackWithoutAWorkTagGivesNoProof() {
        var bare = Self.song("b", work: "W", album: "A")
        bare.works = nil
        #expect(!WorkIndex(songs: [Self.song("a", work: "W", album: "A"), bare]).albums[0].isComplete)
    }

    // MARK: The draw

    @Test func theSameDateGivesTheSamePick() {
        #expect(drawn(Self.whole)?.title == drawn(Self.whole)?.title)
        #expect(drawn(Self.whole, day: 10)?.page == drawn(Self.whole, day: 10)?.page)
    }

    @Test func aLaterDateCanDrawAnotherPick() {
        let pages = Set((1...20).compactMap { drawn(Self.whole, day: $0)?.page })
        #expect(pages.count > 1)
    }

    @Test func onlyCompleteItemsAreDrawn() {
        var songs = [1, 3].map { Self.song("m\($0)", work: "Partial", album: "Partial", movement: ($0, 3)) }
        songs.append(Self.song("c", work: "Complete", album: "Complete"))
        let index = WorkIndex(songs: songs)
        for day in 1...28 {
            #expect(drawn(index, day: day)?.title == "Complete")
        }
    }

    @Test func aLibraryWithNothingCompleteHidesTheRow() {
        let songs = [1, 3].map { Self.song("m\($0)", work: "W", album: "A", movement: ($0, 3)) }
        #expect(LibraryPageTests.page(rows: [row()], index: WorkIndex(songs: songs)).sections.isEmpty)
        #expect(LibraryPageTests.page(rows: [row()], index: WorkIndex()).sections.isEmpty)
    }

    // MARK: The sentence

    @Test func theSentenceNamesTitleComposerAndLead() throws {
        let pick = try #require(drawn(Self.whole))
        #expect(pick.composer == "Frédéric Chopin")
        #expect(pick.lead == "Conductor")
        let names = pick.sentence.compactMap { piece -> String? in
            if case .name(let text, _) = piece { text } else { nil }
        }
        #expect(names == [pick.title, "Frédéric Chopin", "Conductor"])
        #expect(pick.sentence.map(\.text).joined().contains(pick.title))
    }

    @Test func aMissingLeadLeavesItOutOfTheSentence() throws {
        let index = WorkIndex(songs: [Self.song("a", work: "W", album: "A", conductor: nil)])
        let pick = try #require(drawn(index))
        #expect(pick.lead == nil)
        #expect(!pick.sentence.map(\.text).joined().contains("with"))
    }

    @Test func theTitleOpensTheItemAndNamesOpenPeople() throws {
        let pick = try #require(drawn(WorkIndex(songs: [Self.song("a", work: "W", album: "A")])))
        let targets = pick.sentence.compactMap { piece -> Page? in
            if case .name(_, let page) = piece { page } else { nil }
        }
        #expect(targets.count == 3)
        #expect(targets[0] == pick.page)
        #expect(targets[1] == .composer("Frédéric Chopin"))
        #expect(targets[2] == .performer("Conductor"))
    }

    @Test func theDefaultRowsStartWithTheDailyPick() {
        #expect(LibraryRows.standard.first?.kind == .pick)
        #expect(LibraryPageTests.page(index: Self.whole).sections.first?.kindName == "pick")
    }
}
