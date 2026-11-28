import Foundation
import Testing

@testable import Klassik

/// Row titles come whole from the string table, in every language the app holds (sz-augz.10).
@MainActor
struct LibraryTitlesTests {
    private func row(
        _ kind: LibraryRowKind, sort: LibrarySort? = nil, _ conditions: [[RecentSearch.Term]] = []
    ) -> LibraryRowSetup {
        var row = LibraryRowSetup(kind: kind)
        if let sort { row.sort = sort }
        row.conditions = conditions
        return row
    }

    private func title(_ row: LibraryRowSetup, _ language: AppLanguage) -> String {
        LibraryTitles.title(of: row, in: language)
    }

    private let chopin = RecentSearch.Term(kind: .composer, name: "Frédéric Chopin")
    private let strauss = RecentSearch.Term(kind: .composer, name: "Richard Strauss")
    private let song = RecentSearch.Term(kind: .genre, name: "Song")

    @Test func aNaturalTitleIsOneWholeStringOfTheCatalog() {
        #expect(title(row(.composers, sort: .best), .english) == "Best known composers")
        #expect(title(row(.composers, sort: .best), .german) == "Bekannteste Komponisten")
        #expect(title(row(.albums, sort: .random), .english) == "Random albums")
        #expect(title(row(.albums, sort: .random), .german) == "Zufällige Alben")
        #expect(title(row(.recordings, sort: .newest), .english) == "Newest recordings")
        #expect(title(row(.recordings, sort: .newest), .german) == "Neueste Aufnahmen")
        #expect(title(row(.composers, sort: .az), .german) == "Komponisten von A bis Z")
    }

    @Test func aRowWithoutQualifierKeepsItsKindTitle() {
        #expect(title(row(.composers), .english) == "Composers")
        #expect(title(row(.composers), .german) == "Komponisten")
        #expect(title(row(.heard), .german) == "Kürzlich gehört")
        #expect(title(row(.pick), .german) == "Tipp des Tages")
    }

    @Test func aCombinationWithoutNaturalTitleUsesTheFallbackFormat() {
        #expect(title(row(.added, sort: .az), .english) == "Recently added, A to Z")
        #expect(title(row(.added, sort: .az), .german) == "Kürzlich hinzugefügt, A bis Z")
        #expect(title(row(.heard, sort: .random), .german) == "Kürzlich gehört, zufällig")
    }

    @Test func oneTermNamesItselfAndSeveralMakeTheRowFiltered() {
        #expect(title(row(.composers, [[chopin]]), .english) == "Composers, Frédéric Chopin")
        #expect(title(row(.composers, [[chopin]]), .german) == "Komponisten, Frédéric Chopin")
        #expect(title(row(.composers, [[chopin, strauss], [song]]), .english) == "Composers, filtered")
        #expect(title(row(.composers, [[chopin, strauss], [song]]), .german) == "Komponisten, gefiltert")
    }

    @Test func aNaturalSortTitleTakesTheFilterQualifier() {
        #expect(title(row(.composers, sort: .best, [[chopin]]), .english) == "Best known composers, Frédéric Chopin")
        #expect(title(row(.composers, sort: .best, [[chopin]]), .german) == "Bekannteste Komponisten, Frédéric Chopin")
    }

    @Test func aRoleKeepsItsTagValueWithTheAmpersand() {
        let role = RecentSearch.Term(kind: .performer, name: "Harpsichord & Organ")
        #expect(title(row(.performers, [[role]]), .english) == "Performers, Harpsichord & Organ")
        #expect(title(row(.performers, [[role]]), .german) == "Interpreten, Harpsichord & Organ")
    }

    @Test func aSavedSearchNamesItsConditionsWithTheListFormatterOfTheLanguage() {
        let saved = row(.saved, [[chopin, strauss], [song]])
        #expect(title(saved, .english) == "Saved search, Frédéric Chopin or Richard Strauss, Song")
        #expect(title(saved, .german) == "Gespeicherte Suche, Frédéric Chopin oder Richard Strauss, Song")
        #expect(title(row(.saved), .german) == "Gespeicherte Suche")
    }

    @Test func titlesCarryNoCountAndNoUnresolvedFormat() {
        for kind in LibraryRowKind.allCases {
            var setup = row(kind, [[chopin]])
            setup.count = 12
            for sort in [LibrarySort.random, .best, .newest, .heard, .az] {
                setup.sort = sort
                for language in [AppLanguage.english, .german] {
                    let text = title(setup, language)
                    #expect(!text.isEmpty)
                    #expect(!text.contains("%"))
                    #expect(text.rangeOfCharacter(from: .decimalDigits) == nil)
                }
            }
        }
    }

    @Test func theSortIsNamedInTheTitleOrTheSubtitleNeverBoth() {
        let named = row(.composers, sort: .az)
        #expect(LibraryTitles.namesSort(of: named))
        #expect(!named.subtitle.contains("A to Z"))
        // The start sort is no qualifier, so the subtitle says it.
        #expect(!LibraryTitles.namesSort(of: row(.composers)))
        #expect(row(.composers).subtitle == "Random, 9 faces")
        // The qualifier slot goes to the filter, so the title leaves the sort to the subtitle.
        let filtered = row(.added, sort: .az, [[chopin]])
        #expect(title(filtered, .english) == "Recently added, Frédéric Chopin")
        #expect(!LibraryTitles.namesSort(of: filtered))
        #expect(filtered.subtitle == "Albums, A to Z, 9 covers")
        let fallback = row(.added, sort: .az)
        #expect(LibraryTitles.namesSort(of: fallback))
        #expect(fallback.subtitle == "Albums, 9 covers")
    }
}
