import Foundation
import SwiftUI
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
        #expect(page.header.map(\.label) == ["conductor", "album"])
        #expect(page.facts == "Recorded in 1972. 2\u{00A0}minutes, 2\u{00A0}movements.")
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
        // One movement gives no count.
        #expect(page.facts == "Recorded in 1972. 1\u{00A0}minute.")
    }

    @Test func recordingWithMixedYearsShowsNone() {
        let page = PlayerPage(
            recording: Self.recording([Self.song("a", 1, year: 1972), Self.song("b", 2, year: 1973)], year: 2005))
        #expect(page.facts == "2\u{00A0}minutes, 2\u{00A0}movements.")
    }

    @Test func albumShowsItsOwnYearAndNoAlbumLine() {
        let page = PlayerPage(
            recording: Self.recording(
                [Self.song("a", 1, year: 1972), Self.song("b", 2, year: 1973)], year: 1973, isAlbum: true))
        #expect(page.header.isEmpty)
        #expect(page.facts == "Recorded in 1973. 2\u{00A0}minutes, 2\u{00A0}tracks.")
    }

    @Test func factsGiveNoYearWhenNoneIsTagged() {
        let page = PlayerPage(recording: Self.recording([Self.song("a", 1), Self.song("b", 2)]))
        #expect(page.facts == "2\u{00A0}minutes, 2\u{00A0}movements.")
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

    @Test func aLongTouchHoldsTheRowsUntilThePageIsStill() {
        var spell = QuietSpell()
        spell.touching(true, at: start)
        #expect(spell.wait(at: start.advanced(by: .seconds(60))) != nil)
        spell.touching(false, at: start.advanced(by: .seconds(60)))
        #expect(spell.wait(at: start.advanced(by: .seconds(61))) != nil)
        #expect(spell.wait(at: start.advanced(by: .seconds(60) + QuietSpell.length)) == nil)
    }

    @Test func theSpellLastsEightSeconds() {
        #expect(QuietSpell.length == .seconds(8))
    }

    @Test func retriesFollowingUntilAnotherTouch() {
        var spell = QuietSpell()
        spell.touch(at: start)
        let follow1 = spell.follow(at: start.advanced(by: .seconds(7)))
        #expect(!follow1)
        let follow2 = spell.follow(at: start.advanced(by: .seconds(8)))
        #expect(follow2)
        let follow3 = spell.follow(at: start.advanced(by: .seconds(9)))
        #expect(follow3)
        let follow4 = spell.follow(at: start.advanced(by: .seconds(10)))
        #expect(follow4)
        spell.touch(at: start.advanced(by: .seconds(11)))
        let follow5 = spell.follow(at: start.advanced(by: .seconds(12)))
        #expect(!follow5)
        let follow6 = spell.follow(at: start.advanced(by: .seconds(19)))
        #expect(follow6)
    }

    @Test func neverFollowsDuringATouch() {
        var spell = QuietSpell()
        spell.touching(true, at: start)
        let early = spell.follow(at: start.advanced(by: .seconds(60)))
        #expect(!early)
        spell.touching(false, at: start.advanced(by: .seconds(60)))
        let late = spell.follow(at: start.advanced(by: .seconds(68)))
        #expect(late)
    }

    @Test func aNoteHoldsTheRowsUntilASpellAfterItCloses() {
        var spell = QuietSpell()
        spell.writing(true, at: start)
        let writing = spell.follow(at: start.advanced(by: .seconds(60)))
        #expect(!writing)
        spell.hold(true, at: start.advanced(by: .seconds(61)))
        spell.hold(false, at: start.advanced(by: .seconds(62)))
        let afterScrub = spell.follow(at: start.advanced(by: .seconds(70)))
        #expect(!afterScrub)
        spell.writing(false, at: start.advanced(by: .seconds(80)))
        let justSaved = spell.follow(at: start.advanced(by: .seconds(81)))
        #expect(!justSaved)
        let later = spell.follow(at: start.advanced(by: .seconds(80) + QuietSpell.length))
        #expect(later)
    }

    @Test func aScrollByTheAppStartsNoSpell() {
        var spell = QuietSpell()
        spell.touching(false, at: start)
        #expect(spell.wait(at: start.advanced(by: .seconds(1))) == nil)
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

struct PageLinkTests {
    @Test(arguments: [
        Page.composer("Felix Mendelssohn"), .performer("Anne-Sophie Mutter & Friends"), .album("al-1|disc 2?x=1"),
    ])
    func aPageGoesThroughItsURL(_ page: Page) throws {
        let url = try #require(PageLink.url(page))
        #expect(url.scheme == PageLink.scheme)
        #expect(PageLink.page(url) == page)
    }

    @Test func otherPagesHaveNoURL() {
        #expect(PageLink.url(.settings) == nil)
        #expect(PageLink.url(.work("w")) == nil)
    }

    @Test func otherURLsHaveNoPage() throws {
        #expect(PageLink.page(try #require(URL(string: "https://example.org/composer?id=x"))) == nil)
        #expect(PageLink.page(try #require(URL(string: "klassik-page://work?id=x"))) == nil)
    }
}

struct LinkedNamesTests {
    static func links(_ text: AttributedString) -> [String: URL] {
        var found: [String: URL] = [:]
        for run in text.runs {
            if let url = run.link { found[String(text[run.range].characters)] = url }
        }
        return found
    }

    @Test func onlyNamesWithAPageAreLinks() {
        let text = LinkedNames.text(
            "Kurt Masur and Gewandhausorchester", names: ["Kurt Masur", "Gewandhausorchester"],
            link: { $0 == "Kurt Masur" ? .performer($0) : nil }, tint: .red, underline: false)
        #expect(String(text.characters) == "Kurt Masur and Gewandhausorchester")
        #expect(Self.links(text) == ["Kurt Masur": PageLink.url(.performer("Kurt Masur"))!])
    }

    /// A name inside an earlier name links the later occurrence, so each name links once in its place.
    @Test func eachNameLinksInItsPlace() {
        let text = LinkedNames.text(
            "Anna Berg and Berg", names: ["Anna Berg", "Berg"], link: { .performer($0) }, tint: .red,
            underline: true)
        #expect(Self.links(text).count == 2)
        #expect(Self.links(text)["Berg"] == PageLink.url(.performer("Berg")))
    }
}
