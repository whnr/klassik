import Foundation
import Testing

@testable import Klassik

@MainActor
struct RecentSearchesTests {
    private func store() -> DeviceStore {
        DeviceStore(
            server: URL(string: "https://music.example.org")!, username: "listener",
            folder: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString))
    }

    private let dvorak = RecentSearch.Term(kind: .composer, name: "Antonín Dvořák")
    private let brahms = RecentSearch.Term(kind: .composer, name: "Johannes Brahms")
    private let symphony = RecentSearch.Term(kind: .genre, name: "Symphony")

    @Test func eachCommitOfASessionReplacesItsEntry() {
        let recent = RecentSearches(store: nil)
        recent.commit(text: "cho")
        recent.commit(text: "chopin", conditions: [[dvorak]])
        #expect(recent.entries.map(\.text) == ["chopin"])
        #expect(recent.entries.first?.conditions == [[dvorak]])
    }

    @Test func aNewSessionAddsAnEntryNewestFirst() {
        let recent = RecentSearches(store: nil)
        recent.commit(text: "chopin")
        recent.endSession()
        recent.commit(text: "brahms")
        #expect(recent.entries.map(\.text) == ["brahms", "chopin"])
    }

    @Test func anEmptySearchKeepsNothingAndOpensNoEntry() {
        let recent = RecentSearches(store: nil)
        recent.commit(text: "  ")
        recent.commit(text: "", conditions: [[]])
        #expect(recent.entries.isEmpty)
        #expect(recent.session == nil)
    }

    @Test func aSearchOfConditionsOnlyIsKept() {
        let recent = RecentSearches(store: nil)
        recent.commit(text: "", conditions: [[dvorak, brahms], [symphony]])
        #expect(recent.entries.count == 1)
        #expect(
            recent.entries.first?.conditionLine
                == "Composer Antonín Dvořák or Composer Johannes Brahms and Genre Symphony")
    }

    @Test func theSameSearchInANewSessionMovesToTheTop() {
        let recent = RecentSearches(store: nil)
        recent.commit(text: "Chopin")
        recent.endSession()
        recent.commit(text: "brahms")
        recent.endSession()
        recent.commit(text: "chopin ")
        #expect(recent.entries.map(\.text) == ["chopin", "brahms"])
    }

    @Test func aRestoreMovesTheEntryUpAndContinuesItsSession() throws {
        let recent = RecentSearches(store: nil)
        recent.commit(text: "chopin", conditions: [[symphony]])
        recent.endSession()
        recent.commit(text: "brahms")
        recent.endSession()
        let chopin = try #require(recent.entries.last)
        recent.restore(chopin)
        #expect(recent.entries.map(\.text) == ["chopin", "brahms"])
        #expect(recent.entries.first?.conditions == [[symphony]])
        recent.commit(text: "chopin noct")
        #expect(recent.entries.map(\.text) == ["chopin noct", "brahms"])
    }

    @Test func clearEmptiesTheList() {
        let recent = RecentSearches(store: nil)
        recent.commit(text: "chopin")
        recent.clear()
        #expect(recent.entries.isEmpty)
    }

    @Test func theListKeepsTheNewestEntriesOnly() {
        var list: [RecentSearch] = []
        for number in 0...RecentSearches.limit {
            list = RecentSearches.committing(RecentSearch(text: "\(number)", conditions: []), into: list)
        }
        #expect(list.count == RecentSearches.limit)
        #expect(list.first?.text == "\(RecentSearches.limit)")
        #expect(list.last?.text == "1")
    }

    @Test func recentSearchesStayInTheDeviceFile() throws {
        let store = store()
        RecentSearches(store: store).commit(text: "chopin", conditions: [[dvorak]])
        let again = RecentSearches(store: store)
        #expect(again.entries.map(\.text) == ["chopin"])
        #expect(again.entries.first?.conditions == [[dvorak]])
        // A new launch starts no session: the next search is a new entry.
        again.commit(text: "brahms")
        #expect(again.entries.count == 2)
    }

    @Test func aFileWithoutRecentSearchesLoads() throws {
        let store = store()
        try FileManager.default.createDirectory(
            at: store.url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(#"{"favouriteWorks":[]}"#.utf8).write(to: store.url)
        #expect(try store.load().recentSearches.isEmpty)
    }

    @Test func theConditionsOfTheSheetSurviveTheRoundTrip() {
        let conditions = [
            Search.Condition(terms: [
                Search.Term(scope: .composers, name: "Antonín Dvořák"),
                Search.Term(scope: .composers, name: "Johannes Brahms"),
            ]),
            Search.Condition(terms: [Search.Term(scope: .genres, name: "Symphony")]),
            Search.Condition(terms: [Search.Term(scope: .conductors, name: "Carlos Kleiber")]),
            Search.Condition(terms: [Search.Term(scope: .performers, name: "Martha Argerich")]),
        ]
        let kept = RecentSearch.terms(of: conditions)
        #expect(kept.first == [dvorak, brahms])
        #expect(kept.map { $0.map(\.kind) } == [[.composer, .composer], [.genre], [.conductor], [.performer]])
        #expect(RecentSearch(text: "", conditions: kept).searchConditions == conditions)
    }
}
