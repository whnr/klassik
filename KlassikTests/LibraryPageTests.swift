import Foundation
import Testing

@testable import Klassik

@MainActor
struct LibraryPageTests {
    static func song(
        _ id: String, composer: String = "Frédéric Chopin", work: String? = nil, album: String? = nil,
        conductor: String? = nil, created: String? = nil, track: Int = 1
    ) -> Song {
        var song = Song(
            id: id, title: "Track \(id)", album: album ?? "Album \(id)", albumId: "album-\(album ?? id)",
            displayAlbumArtist: conductor, track: track, discNumber: 1, displayComposer: composer,
            contributors: conductor.map {
                [Song.Contributor(role: "conductor", artist: Song.Artist(id: $0, name: $0))]
            },
            works: work.map { [Song.Work(name: $0)] }, created: created)
        song.year = 2000
        return song
    }

    /// Eleven composers, one work and one album each.
    static let songs: [Song] = (1...11).map {
        song(
            "s\($0)", composer: "Composer \(String(format: "%02d", $0))", work: "Work \($0)",
            conductor: "Conductor \($0)", created: "2026-09-\(String(format: "%02d", $0))T10:00:00Z")
    }
    static let index = WorkIndex(songs: songs)

    static func page(
        rows: [LibraryRowSetup] = LibraryRows.standard, favourites: LibraryPage.Favourites = .init(),
        day: Int = 10, unbuiltLinks: Bool = false, index: WorkIndex = LibraryPageTests.index
    ) -> LibraryPage {
        var parts = DateComponents(year: 2026, month: 11, day: day, hour: 12)
        parts.calendar = Calendar(identifier: .gregorian)
        return LibraryPage(
            index: index, favourites: favourites, rows: rows, date: parts.date!, calendar: parts.calendar!,
            unbuiltLinks: unbuiltLinks)
    }

    private func row(_ kind: LibraryRowKind, id: String = "r", configure: (inout LibraryRowSetup) -> Void = { _ in })
        -> LibraryRowSetup
    {
        var row = LibraryRowSetup(kind: kind, id: id)
        configure(&row)
        return row
    }

    @Test func defaultRowsAreComposersFavouritesLinksAndRecentlyAdded() {
        let index = Self.index
        let favourites = LibraryPage.Favourites(composers: [index.composers[0]])
        let page = Self.page(favourites: favourites)
        #expect(page.sections.map(\.title) == [L("Composers"), L("Favourites"), nil, L("Recently added")])
    }

    @Test func rowsWithNothingToShowHide() {
        let page = Self.page()
        #expect(!page.sections.contains { $0.title == L("Favourites") })
        let bare = Self.page(index: WorkIndex(songs: [Self.song("x")]))
        // No track has a date, so Recently added has nothing; the link list still has Albums.
        #expect(bare.sections.map(\.title) == [L("Composers"), nil])
        // Only the link list stays: it is not empty while it has tiles.
        #expect(Self.page(index: WorkIndex()).sections.map(\.title) == [nil])
    }

    @Test func composerCardsShowWorkCountAndTheNineLimit() throws {
        let page = Self.page(rows: [row(.composers)])
        let cards = try #require(page.sections.first?.cards)
        #expect(cards.count == 9)
        #expect(Set(cards.map(\.fact)) == [L("\(1) works")])
        guard case .composer(let name) = cards[0].page else {
            Issue.record("not a composer page")
            return
        }
        #expect(name == cards[0].name)
    }

    @Test func factLineIsOneKindForTheWholeRow() throws {
        let performers = Self.page(rows: [row(.performers)])
        #expect(Set(try #require(performers.sections.first?.cards).map(\.fact)) == [L("\(1) recordings")])
        let albums = Self.page(rows: [row(.albums)])
        let card = try #require(albums.sections.first?.cards.first)
        #expect(card.fact.hasPrefix("Conductor "))
        let works = Self.page(rows: [row(.works)])
        #expect(try #require(works.sections.first?.cards).allSatisfy { $0.fact.hasPrefix("Composer ") })
    }

    @Test func favouritesMixKindsAndNameTheKindInTheFactLine() throws {
        let index = Self.index
        let work = index.composers[2].works[0]
        let favourites = LibraryPage.Favourites(
            composers: [index.composers[0]], albums: [index.albums[1]],
            recordings: [.init(work: work, recording: work.recordings[0])])
        let page = Self.page(rows: [row(.favourites)], favourites: favourites)
        let cards = try #require(page.sections.first?.cards)
        #expect(Set(cards.map(\.fact)) == [L("Composer"), L("Album"), L("Recording")])
        #expect(page.sections.first?.look == .mixed)
    }

    @Test func randomOrderHoldsForADayAndChangesWithTheDate() throws {
        let names = { (page: LibraryPage) in try #require(page.sections.first?.cards).map(\.name) }
        let today = Self.page(rows: [row(.composers)])
        let again = Self.page(rows: [row(.composers)])
        #expect(try names(today) == names(again))
        let other = (11...14).map { Self.page(rows: [row(.composers)], day: $0) }
        #expect(try other.contains { try names($0) != names(today) })
        let second = Self.page(rows: [row(.composers, id: "other")])
        #expect(try names(second) != names(today))
    }

    @Test func recentlyAddedListsAlbumsNewestFirstAndSkipsUndated() throws {
        var songs = Self.songs
        songs.append(Self.song("undated", composer: "Composer 99"))
        let page = Self.page(rows: [row(.added)], index: WorkIndex(songs: songs))
        let cards = try #require(page.sections.first?.cards)
        #expect(cards.count == 9)
        #expect(cards.first?.name == "Album s11")
        #expect(!cards.contains { $0.name == "Album undated" })
    }

    @Test func titleIsOneWholeStringPerKindWithSortQualifier() {
        let plain = Self.page(rows: [row(.albums)])
        #expect(plain.sections.first?.title == L("Albums"))
        let az = Self.page(rows: [row(.albums) { $0.sort = .az }])
        #expect(az.sections.first?.title == L("\(L("Albums")), \(L("A to Z"))"))
        let composersAZ = Self.page(rows: [row(.composers) { $0.sort = .az }])
        #expect(composersAZ.sections.first?.title == L("\(L("Composers")), \(L("A to Z"))"))
    }

    @Test func linkListShowsOnlyBuiltPagesUntilFlagged() throws {
        let page = Self.page(rows: [row(.links)])
        let links = try #require(page.sections.first?.links)
        #expect(links.map(\.title) == [L("Albums")])
        #expect(links.first?.count == Self.index.albums.count)
        #expect(links.first?.page == .albums(classical: true))
        let flagged = Self.page(rows: [row(.links)], unbuiltLinks: true)
        #expect(try #require(flagged.sections.first?.links).count == LibraryRowSetup.defaultLinks.count)
    }

    @Test func countCutsTheRowAndTilesUseTheirOwnCounts() throws {
        let six = Self.page(rows: [row(.albums) { $0.count = 6 }])
        #expect(six.sections.first?.cards.count == 6)
        let tiles = Self.page(rows: [row(.albums) { ($0.form, $0.count) = (.tiles, 3) }])
        #expect(tiles.sections.first?.cards.count == 3)
        #expect(tiles.sections.first?.isTiles == true)
    }

    @Test func kindsWithoutDrawingYetStayHidden() {
        let page = Self.page(rows: [row(.pick), row(.heard), row(.saved)])
        #expect(page.sections.isEmpty)
    }

    @Test func longNamesBreakAtHyphenationPoints() {
        let german = Hyphenation.soften("Staatskapelle Dresden", locale: Locale(identifier: "de"))
        #expect(german.contains("\u{00AD}"))
        #expect(german.replacingOccurrences(of: "\u{00AD}", with: "") == "Staatskapelle Dresden")
        let english = Hyphenation.soften("Philharmonic Orchestra", locale: Locale(identifier: "en"))
        #expect(english.contains("\u{00AD}"))
        #expect(Hyphenation.soften("Bach", locale: Locale(identifier: "en")) == "Bach")
    }
}
