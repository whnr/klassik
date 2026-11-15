import Foundation
import Testing

@testable import Klassik

struct NowPlayingTextTests {
    private func text(_ people: [Song.Contributor], artist: String? = nil) -> NowPlayingText {
        let song = Song(
            id: "one", title: "Symphony: I. Allegro", artist: artist, displayComposer: "Composer",
            contributors: people, works: [.init(name: "Symphony")], movements: [.init(name: "I. Allegro")])
        let work = WorkIndex.Work(
            id: "work", title: "Album", composer: "Another Composer", isTagged: false, recordings: [])
        return NowPlayingText(song: song, work: work)
    }

    @Test func conductorAndTaggedOrchestraTakeTheArtistField() {
        let result = text([
            RolesTests.who("conductor", "Carl Fixture"),
            RolesTests.who("performer", "Sine Orchestra", "orchestra"),
            RolesTests.who("performer", "Daniel Keys", "piano"),
            RolesTests.who("producer", "Pat Booth"),
        ])
        #expect(result.title == "I. Allegro")
        #expect(result.artist.contains("Carl Fixture"))
        #expect(result.artist.contains("Sine Orchestra"))
        #expect(!result.artist.contains("Daniel Keys"))
        #expect(!result.artist.contains("Pat Booth"))
        #expect(result.album == "Composer, Symphony")
    }

    @Test func soleTaggedSoloistShowsWithoutGuessingTheArtistTag() {
        let result = text([RolesTests.who("performer", "Daniel Keys", "piano")], artist: "Unsorted Names")
        #expect(result.artist == "Daniel Keys")
        #expect(text([], artist: "Unsorted Names").artist.isEmpty)
    }

    @Test(arguments: [4, 6])
    func manyNamesShowThreeAndTheRemainingCount(count: Int) {
        let result = text((1...count).map { RolesTests.who("performer", "Player \($0)", "violin") })
        for number in 1...3 { #expect(result.artist.contains("Player \(number)")) }
        for number in 4...count { #expect(!result.artist.contains("Player \(number)")) }
        #expect(result.artist.contains(count == 4 ? "1 other" : "3 others"))
    }

    @Test func namesFollowTheCurrentMovementAndAppearOnce() {
        let one = RolesTests.who("conductor", "Carl Fixture")
        #expect(text([one, one]).artist == "Carl Fixture")
        #expect(text([RolesTests.who("conductor", "Clara Fixture")]).artist == "Clara Fixture")
    }

    @Test func albumMovementKeepsItsOwnComposerAndWork() {
        let song = Song(id: "a", title: "Allegro", displayComposer: "Bach", works: [.init(name: "Concerto")])
        let work = WorkIndex.Work(id: "album", title: "Recital", composer: "Mozart", isTagged: false, recordings: [])
        #expect(NowPlayingText(song: song, work: work).album == "Bach, Concerto")
    }

    @Test func albumTrackWithoutWorkTagKeepsItsFullTitle() {
        let song = Song(
            id: "b", title: "Sonata in A: I. Allegro", displayComposer: "Bach", movements: [.init(name: "I. Allegro")])
        let work = WorkIndex.Work(id: "album", title: "Recital", composer: "Bach", isTagged: false, recordings: [])
        let result = NowPlayingText(song: song, work: work)
        #expect(result.title == "Sonata in A: I. Allegro")
        #expect(result.album == "Bach")
    }
}
