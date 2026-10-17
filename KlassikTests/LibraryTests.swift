import Foundation
import Testing
@testable import Klassik

struct LibraryTests {
    static func song(
        _ id: String, album: String = "a1", genre: String? = nil, work: String? = nil, movement: String? = nil,
        composer: String? = nil
    ) -> Song {
        Song(
            id: id, title: id, albumId: album, genre: genre, genres: genre.map { [Song.Genre(name: $0)] },
            contributors: composer.map { [Song.Contributor(role: "composer", artist: Song.Artist(id: "c", name: $0))] },
            works: work.map { [Song.Work(name: $0)] }, movements: movement.map { [Song.Movement(name: $0)] })
    }

    static func rule(_ conditions: ClassicalFilter.Condition...) -> ClassicalFilter.Rule {
        ClassicalFilter.Rule(conditions: conditions)
    }

    @Test(arguments: ["Classical > Orchestral", "classical", "Neoclassical"])
    func genreMatchesAnywhereIgnoringCase(genre: String) {
        #expect(ClassicalFilter().matches(Self.song("t", genre: genre)))
    }

    /// Work and composer tags also occur on pop albums.
    @Test func defaultNeedsWorkAndMovementTogether() {
        let filter = ClassicalFilter()
        #expect(filter.matches(Self.song("t", genre: "Pop", work: "Symphony No. 5", movement: "Allegro con brio")))
        #expect(!filter.matches(Self.song("t", genre: "Proll", work: "Helga", composer: "Helga")))
        #expect(!filter.matches(Self.song("t", genre: "Jazz", composer: "Mozart")))
    }

    @Test func allConditionsOfARuleMustMatch() {
        let filter = ClassicalFilter(rules: [Self.rule(.init(kind: .hasComposer), .init(kind: .genreDoesNotContain, text: "Pop"))])
        #expect(filter.matches(Self.song("t", genre: "Jazz", composer: "Mozart")))
        #expect(!filter.matches(Self.song("t", genre: "Pop", composer: "Mozart")))
        #expect(!filter.matches(Self.song("t", genre: "Jazz")))
    }

    /// A condition the listener is still typing must not let the whole library in.
    @Test func emptyRulesAndEmptyTextMatchNothing() {
        let song = Self.song("t", genre: "Classical", work: "W", movement: "M", composer: "C")
        #expect(!ClassicalFilter(rules: []).matches(song))
        #expect(!ClassicalFilter(rules: [Self.rule()]).matches(song))
        #expect(!ClassicalFilter(rules: [Self.rule(.init(kind: .genreContains, text: " "))]).matches(song))
        #expect(!ClassicalFilter(rules: [Self.rule(.init(kind: .genreDoesNotContain))]).matches(song))
    }

    @Test func albumCountsWhenMostTracksMatch() {
        let songs = [
            Self.song("c1", album: "classical", genre: "Classical"),
            Self.song("c2", album: "classical", genre: "Classical"),
            Self.song("c3", album: "classical", genre: "Soundtrack"),
            Self.song("p1", album: "pop", genre: "Pop"),
            Self.song("p2", album: "pop", genre: "Classical"),
        ]
        #expect(ClassicalFilter().classical(songs).map(\.id) == ["c1", "c2", "c3"])
    }

    /// The tags of the fixture concerto as Navidrome 0.64.2 returns them.
    @Test func decodesOpenSubsonicClassicalFields() throws {
        let json = #"""
        {"subsonic-response":{"status":"ok","version":"1.16.1","openSubsonic":true,"searchResult3":{"song":[
        {"id":"s1","title":"Piano Concerto No. 21 in C major, K. 467: III. Allegro vivace assai","album":"Mozart: Piano Concertos 21 & 23",
        "albumId":"a1","track":3,"discNumber":1,"year":1999,"duration":4,"suffix":"mp3","genre":"Classical > Concerto",
        "genres":[{"name":"Classical > Concerto"}],"displayComposer":"Wolfgang Amadeus Mozart",
        "contributors":[{"role":"composer","artist":{"id":"c1","name":"Wolfgang Amadeus Mozart"}},
        {"role":"performer","subRole":"Piano","artist":{"id":"p1","name":"Daniel Keys"}}],
        "works":[{"name":"Piano Concerto No. 21 in C major, K. 467"}],
        "movements":[{"name":"Allegro vivace assai","number":3,"count":3}],"musicBrainzId":"","isrc":[]}]}}}
        """#
        let song = try #require(SubsonicClient.decode(Data(json.utf8)).searchResult3?.song?.first)
        #expect(song.works?.first?.name == "Piano Concerto No. 21 in C major, K. 467")
        #expect(song.movements?.first == Song.Movement(name: "Allegro vivace assai", number: 3, count: 3))
        #expect(song.contributors?.last?.subRole == "Piano")
        #expect(song.displayComposer == "Wolfgang Amadeus Mozart")
    }

    @MainActor @Test func fetchesPagesUntilShortPage() async throws {
        var offsets: [Int] = []
        let songs = try await Library.fetchAll(pageSize: 2) { offset in
            offsets.append(offset)
            return Array((0..<5).map { Self.song("t\($0)") }[offset..<min(offset + 2, 5)])
        }
        #expect(songs.count == 5)
        #expect(offsets == [0, 2, 4])
    }

    @Test func cacheRoundTrip() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString)/library.json")
        let cache = LibraryCache(
            server: URL(string: "https://music.example.org")!, username: "joe", syncedAt: Date(timeIntervalSince1970: 0),
            songs: [Self.song("t1", genre: "Classical", work: "W")])
        try cache.write(to: url)
        let read = try LibraryCache.read(from: url)
        #expect(read.songs == cache.songs)
        #expect(read.server == cache.server)
    }

    @MainActor @Test func filterIsKeptOnDevice() throws {
        let defaults = try #require(UserDefaults(suiteName: UUID().uuidString))
        let url = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).json")
        let filter = ClassicalFilter(rules: [Self.rule(.init(kind: .genreContains, text: "Oper"))])
        Library(cacheURL: url, defaults: defaults).filter = filter
        #expect(Library(cacheURL: url, defaults: defaults).filter == filter)
    }
}
