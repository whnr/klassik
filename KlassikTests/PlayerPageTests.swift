import Foundation
import Testing

@testable import Klassik

struct PlayerPageTests {
    static func who(_ role: String, _ name: String, _ sub: String? = nil) -> Song.Contributor {
        RolesTests.who(role, name, sub)
    }

    static func song(
        _ id: String, _ number: Int, year: Int? = nil, composer: String = "Ludwig van Beethoven",
        _ people: [Song.Contributor] = []
    ) -> Song {
        Song(
            id: id, title: "Track \(number)", album: "Album", albumId: "album", track: number, discNumber: 1,
            year: year, duration: 60, displayComposer: composer, contributors: people)
    }

    static func recording(_ songs: [Song], year: Int? = nil, isAlbum: Bool = false) -> WorkIndex.Recording {
        WorkIndex.Recording(id: "r", album: "Symphonies", year: year, songs: songs, isAlbum: isAlbum)
    }

    static let conductor = who("conductor", "Kurt Masur")

    @Test func headerHoldsWhatEveryTrackShares() {
        let page = PlayerPage(
            recording: Self.recording([
                Self.song("a", 1, year: 1972, [Self.conductor]), Self.song("b", 2, year: 1972, [Self.conductor]),
            ]))
        #expect(page.composer == "Ludwig van Beethoven")
        #expect(page.header.map(\.label) == ["conductor", "album", "year"])
        #expect(page.header.last?.names == ["1972"])
        #expect(page.differing.allSatisfy { $0.isEmpty })
    }

    @Test func aRowWithNothingDoesNotOpen() {
        let page = PlayerPage(
            recording: Self.recording([Self.song("a", 1, [Self.conductor]), Self.song("b", 2, [Self.conductor])]))
        #expect(!page.opens(0))
        #expect(!page.opens(1))
        #expect(!page.opens(5))
    }

    @Test func aRowOpensOnlyWithNamesThatDiffer() {
        let soloist = Self.who("performer", "Anne Sophie", "violin")
        let page = PlayerPage(
            recording: Self.recording([
                Self.song("a", 1, [Self.conductor]), Self.song("b", 2, [Self.conductor, soloist]),
            ]))
        #expect(!page.opens(0))
        #expect(page.opens(1))
        #expect(page.differing[1].flatMap(\.names) == ["Anne Sophie"])
        #expect(!page.header.flatMap(\.names).contains("Anne Sophie"))
    }

    @Test func composersThatDifferGiveNoHeaderComposer() {
        let page = PlayerPage(
            recording: Self.recording([Self.song("a", 1), Self.song("b", 2, composer: "Johannes Brahms")]))
        #expect(page.composer == nil)
    }

    @Test func recordingShowsTheYearItsTracksCarry() {
        let page = PlayerPage(recording: Self.recording([Self.song("a", 1, year: 1972)], year: 2005))
        #expect(page.header.last?.names == ["1972"])
    }

    @Test func recordingWithMixedYearsShowsNone() {
        let page = PlayerPage(
            recording: Self.recording([Self.song("a", 1, year: 1972), Self.song("b", 2, year: 1973)], year: 2005))
        #expect(!page.header.map(\.label).contains("year"))
    }

    @Test func albumShowsItsOwnYearAndNoAlbumLine() {
        let page = PlayerPage(
            recording: Self.recording(
                [Self.song("a", 1, year: 1972), Self.song("b", 2, year: 1973)], year: 1973, isAlbum: true))
        #expect(page.header.map(\.label) == ["year"])
        #expect(page.header.first?.names == ["1973"])
    }
}

struct QuietSpellTests {
    let start = ContinuousClock.now

    @Test func scrollsAtOnceWhenNothingTouched() {
        #expect(QuietSpell().wait(at: start) == nil)
    }

    @Test func waitsForTheRestOfTheSpellAfterATouch() {
        var spell = QuietSpell()
        spell.touch(at: start)
        #expect(spell.wait(at: start.advanced(by: .seconds(1))) == QuietSpell.length - .seconds(1))
        #expect(spell.wait(at: start.advanced(by: QuietSpell.length)) == nil)
    }

    @Test func aScrubHoldsTheRowsUntilTheFingerLiftsAndTheSpellEnds() {
        var spell = QuietSpell()
        spell.hold(true, at: start)
        #expect(spell.wait(at: start.advanced(by: .seconds(60))) != nil)
        spell.hold(false, at: start.advanced(by: .seconds(60)))
        #expect(spell.wait(at: start.advanced(by: .seconds(61))) != nil)
        #expect(spell.wait(at: start.advanced(by: .seconds(60) + QuietSpell.length)) == nil)
    }
}
