import Foundation
import Testing

@testable import Klassik

@MainActor
struct LiveSearchTests {
    static func find(_ text: String) -> Search.Results { SearchTests.search.results(for: text) }

    /// Fast typing: the search of "s" ends after the search of "sym". The page keeps the results of "sym".
    @Test func anOlderTextNeverReplacesTheResultsOfANewerOne() async {
        let live = LiveSearch()
        let (started, start) = AsyncStream.makeStream(of: Void.self)
        let (released, release) = AsyncStream.makeStream(of: Void.self)
        let slow = Task {
            await live.show("s", version: 0) { text in
                start.yield()
                for await _ in released { break }
                return Self.find(text)
            }
        }
        for await _ in started { break }
        await live.show("sym", version: 0) { Self.find($0) }
        #expect(live.isShowing("sym"))
        release.yield()
        await slow.value
        #expect(live.isShowing("sym"))
        #expect(live.results.works.count == 2)
        #expect(!live.isShowing("s"))
    }

    /// Back to a text searched before shows its results without a new search.
    @Test func aTextSearchedBeforeShowsAtOnce() async {
        let live = LiveSearch()
        var searches: [String] = []
        let find: @MainActor (String) async -> Search.Results = { text in
            searches.append(text)
            return Self.find(text)
        }
        await live.show("sy", version: 0, find: find)
        await live.show("sym", version: 0, find: find)
        await live.show("sy", version: 0, find: find)
        #expect(searches == ["sy", "sym"])
        #expect(live.isShowing("sy"))
        #expect(live.results.works.count == 2)
    }

    /// A new index searches again: the results of the old index are no longer true.
    @Test func aNewIndexSearchesAgain() async {
        let live = LiveSearch()
        await live.show("sym", version: 0) { _ in Search.Results() }
        #expect(live.results.isEmpty)
        await live.show("sym", version: 1) { Self.find($0) }
        #expect(live.results.works.count == 2)
    }

    /// A text without words shows no results and runs no search.
    @Test func noWordsRunNoSearch() async {
        let live = LiveSearch()
        await live.show(" ,", version: 0) { _ in
            Issue.record("searched")
            return Search.Results()
        }
        #expect(live.isShowing(" ,"))
        #expect(live.results.isEmpty)
    }
}
