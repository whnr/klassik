import Foundation
import Testing

@testable import Klassik

/// Times the search on a library of realistic size. The run prints the numbers; it fails on no time, because the
/// speed of a CI machine varies.
struct SearchSpeedTests {
    static let forms = [
        "Symphony", "Sonata", "Concerto", "Suite", "Quartet", "Nocturne", "Mass", "Prelude", "Serenade",
    ]
    static let keys = ["C major", "E minor", "G major", "B flat major", "D minor", "F sharp minor"]
    static let syllables = ["ba", "do", "ri", "mel", "sor", "kan", "vel", "tra", "lu", "hen", "zar", "pol"]

    static func name(_ number: Int, _ parts: Int) -> String {
        (0..<parts).map { syllables[(number / Int(pow(12, Double($0)))) % 12] }.joined().capitalized
    }

    /// 300 composers with 10 works each, on 4000 albums of 8 tracks, with 200 conductors, 100 orchestras and 600
    /// soloists.
    static func songs() -> [Song] {
        (0..<4000).flatMap { album -> [Song] in
            let work = album % 3000
            let composer = "\(name(work / 10, 2)) \(name(work / 10 + 7, 3))"
            let title = "\(forms[work % forms.count]) No. \(work % 40 + 1) in \(keys[work % keys.count]), Op. \(work)"
            let people: [(role: String, sub: String?, name: String)] = [
                ("conductor", nil, "\(name(album % 200, 2)) \(name(album % 200 + 3, 2))"),
                ("performer", nil, "\(name(album % 100, 3)) Orchestra"),
                ("performer", "piano", "\(name(album % 600, 2)) \(name(album % 600 + 5, 3))"),
            ]
            return (1...8).map { track in
                SearchTests.song(
                    "\(album)-\(track)", album: "\(composer): \(title) (\(album))", track: track,
                    title: "\(title): \(["I.", "II.", "III.", "IV."][track % 4]) \(name(track, 2))",
                    composer: composer, work: title, albumArtist: people[0].name, year: 1950 + album % 70,
                    people: people)
            }
        }
    }

    static func milliseconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds) * 1000 + Double(duration.components.attoseconds) / 1e15
    }

    /// The median of five runs, in milliseconds.
    static func time(_ body: () -> Void) -> Double {
        let clock = ContinuousClock()
        let runs = (0..<5).map { _ in milliseconds(clock.measure(body)) }.sorted()
        return runs[2]
    }

    @Test func timesASearchOnALargeLibrary() {
        let clock = ContinuousClock()
        let songs = Self.songs()
        var index = WorkIndex()
        let indexTime = Self.milliseconds(clock.measure { index = WorkIndex(songs: songs) })
        var search: Search?
        let build = Self.milliseconds(clock.measure { search = Search(index: index) })
        guard let search else { return }
        let works = index.composers.flatMap(\.works).count
        print(
            "SEARCH-SPEED library songs=\(songs.count) works=\(works) albums=\(index.albums.count)"
                + " index=\(String(format: "%.1f", indexTime))ms search-build=\(String(format: "%.1f", build))ms")
        for text in ["s", "sy", "sym", "symphony", "symphony e", "b", "ba", "bado", "orchestra", "zzz"] {
            var results = Search.Results()
            let time = Self.time { results = search.results(for: text) }
            print(
                "SEARCH-SPEED text=\"\(text)\" ms=\(String(format: "%.1f", time)) works=\(results.works.count)"
                    + " people=\(results.people.count) albums=\(results.albums.count)")
        }
        #expect(works > 1000)
    }

    /// The filter sheet builds its terms once per index; then each tap counts every term of a scope.
    @Test func timesTheFiltersOnALargeLibrary() {
        let clock = ContinuousClock()
        let index = WorkIndex(songs: Self.songs())
        var filters: SearchFilters?
        let build = Self.milliseconds(clock.measure { filters = SearchFilters(index: index) })
        guard let filters else { return }
        let found = Search(index: index).results(for: "symphony")
        let all = filters.pool(of: nil)
        let pool = Self.time { _ = filters.pool(of: found) }
        let text = filters.pool(of: found)
        let composer = filters.choices(in: .composers, conditions: [], pool: all)
        #expect(!composer.isEmpty)
        let one = [Search.Condition(terms: [composer[0].term])]
        var timings: [(String, Double)] = [("filters-build", build), ("pool symphony", pool)]
        for scope in Search.Scope.allCases {
            let time = Self.time { _ = filters.choices(in: scope, conditions: [], pool: all) }
            timings.append(("choices \(scope.title)", time))
        }
        let joined = Self.time { _ = filters.choices(in: .performers, conditions: one, pool: all) }
        let either = Self.time { _ = filters.choices(in: .composers, conditions: one, joining: 0, pool: all) }
        let texted = Self.time { _ = filters.choices(in: .performers, conditions: [], pool: text) }
        let narrowAll = Self.time { _ = filters.narrow(nil, by: one) }
        let narrowText = Self.time { _ = filters.narrow(found, by: one) }
        timings += [
            ("choices Performers and", joined), ("choices Composers or", either), ("choices Performers text", texted),
            ("narrow no text", narrowAll), ("narrow symphony", narrowText),
        ]
        for (name, time) in timings {
            print("FILTER-SPEED \(name) ms=\(String(format: "%.1f", time))")
        }
    }
}
