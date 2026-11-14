import Foundation
import Testing

@testable import Klassik

struct RolesTests {
    static let english = Locale(identifier: "en_US")

    static func who(_ role: String, _ name: String, _ sub: String? = nil, sort: String? = nil) -> Song.Contributor {
        Song.Contributor(role: role, subRole: sub, artist: Song.Artist(id: name, name: name, sortName: sort))
    }

    static func track(
        _ id: String, _ number: Int, artist: String? = nil, _ people: [Song.Contributor] = [], duration: Int? = nil
    ) -> Song {
        Song(
            id: id, title: "Track \(number)", album: "Album", albumId: "album", artist: artist, track: number,
            discNumber: 1, duration: duration, contributors: people)
    }

    /// Flo's tags: conductor, soloists with their instrument, a named ensemble, arranger, lyricist, producer.
    static let house = [
        who("conductor", "Rafael Kubelík", sort: "Kubelík, Rafael"),
        who("performer", "Bavarian Radio Symphony Orchestra", "orchestra"), who("performer", "Anne Sophie", "violin"),
        who("arranger", "Ada Setter"), who("lyricist", "Lou Words"), who("producer", "Pat Booth"),
        who("composer", "Antonín Dvořák"),
    ]

    @Test func houseStyleGivesOneLinePerRoleInPageOrder() {
        let lines = Roles.lines(of: [Self.track("a", 1, Self.house)])
        #expect(lines.map(\.label) == ["conductor", "violin", "orchestra", "arranger", "lyricist"])
        #expect(
            lines.map(\.names) == [
                ["Rafael Kubelík"], ["Anne Sophie"], ["Bavarian Radio Symphony Orchestra"], ["Ada Setter"],
                ["Lou Words"],
            ])
    }

    @Test func technicalRolesAndTheComposerStayOutOfThePage() {
        let names = Roles.lines(of: [Self.track("a", 1, Self.house)]).flatMap(\.names)
        #expect(!names.contains("Pat Booth"))
        #expect(!names.contains("Antonín Dvořák"))
    }

    @Test func namesWithoutRoleComeLastAndOnlyWhenNothingMusicalIsTagged() {
        let weak = Roles.lines(of: [Self.track("a", 1, artist: "Some Quartet")])
        #expect(weak.map(\.kind) == [.unlabelled])
        #expect(weak.first?.label == "")
        #expect(weak.first?.rows(locale: Self.english) == [Roles.Line.Row(label: "", text: "Some Quartet")])
    }

    @Test func aPerformerWithoutAnInstrumentIsASoloistUnlessTheNameIsAGroup() {
        let lines = Roles.lines(of: [
            Self.track("a", 1, [Self.who("performer", "Eva Bogen"), Self.who("performer", "Prague Chamber Orchestra")])
        ])
        #expect(lines.map(\.label) == ["soloist", "ensemble"])
    }

    @Test func orderWithinARoleFollowsTheArtistTag() {
        let people = [Self.who("performer", "Amy Bass", "cello"), Self.who("performer", "Zed Alto", "cello")]
        for contributors in [people, people.reversed()] {
            let song = Self.track("a", 1, artist: "Zed Alto; Amy Bass", contributors)
            #expect(Roles.lines(of: [song]).first?.names == ["Zed Alto", "Amy Bass"])
        }
    }

    @Test func withoutTheTagOrderFallsBackToSortNamesThenNames() {
        let people = [
            Self.who("performer", "Rafael Kubelík", "violin", sort: "Kubelík, Rafael"),
            Self.who("performer", "Zoe Abel", "violin", sort: "Abel, Zoe"),
            Self.who("performer", "Mia Mid", "violin"),
        ]
        for contributors in [people, people.reversed(), [people[1], people[2], people[0]]] {
            #expect(
                Roles.lines(of: [Self.track("a", 1, contributors)]).first?.names
                    == ["Zoe Abel", "Rafael Kubelík", "Mia Mid"])
        }
    }

    @Test func aNameWithACommaTakesItsOwnRowWithTheLabelRepeated() {
        let line = Roles.Line(kind: .soloist, label: "violin", names: ["Kubelík, Rafael", "Eva Bogen"])
        #expect(line.rows(locale: Self.english).map(\.label) == ["violin", "violin"])
        #expect(line.rows(locale: Self.english).map(\.text) == ["Kubelík, Rafael", "Eva Bogen"])
    }

    @Test func namesOfOneRoleJoinWithAnd() {
        let line = Roles.Line(kind: .soloist, label: "violin", names: ["Eva Bogen", "Adam Alto"])
        #expect(line.rows(locale: Self.english) == [Roles.Line.Row(label: "violin", text: "Eva Bogen and Adam Alto")])
    }

    @Test func splitKeepsWhatEveryTrackSharesAndWhatOneTrackAdds() throws {
        let shared = [Self.who("conductor", "Carl Fixture"), Self.who("performer", "Sine Orchestra", "orchestra")]
        let songs = [
            Self.track("a", 1, shared + [Self.who("performer", "Daniel Keys", "piano")]),
            Self.track("b", 2, shared),
        ]
        let split = Roles.split(songs)
        #expect(split.shared.flatMap(\.names) == ["Carl Fixture", "Sine Orchestra"])
        #expect(split.tracks[0].flatMap(\.names) == ["Daniel Keys"])
        #expect(split.tracks[1].isEmpty)
        #expect(Roles.split([]).shared.isEmpty)
    }

    @Test func aSingleTrackSharesEverything() {
        let split = Roles.split([Self.track("a", 1, Self.house)])
        #expect(split.shared.flatMap(\.names).count == 5)
        #expect(split.tracks == [[]])
    }

    @Test func splitIsStableWhateverOrderTheTracksArrive() {
        let a = Self.track("a", 1, [Self.who("conductor", "One"), Self.who("performer", "Solo A", "viola")])
        let b = Self.track("b", 2, [Self.who("conductor", "One"), Self.who("performer", "Solo B", "viola")])
        #expect(Roles.split([a, b]).tracks.map { $0.flatMap(\.names) } == [["Solo A"], ["Solo B"]])
        #expect(Roles.split([b, a]).tracks.map { $0.flatMap(\.names) } == [["Solo B"], ["Solo A"]])
    }

    @Test func noTextCarriesASeparatorGlyphOrAMoreCount() {
        let recording = WorkIndex.Recording(
            id: "r", album: "Album", year: 1972,
            songs: [Self.track("a", 1, Self.house, duration: 2518), Self.track("b", 2, Self.house, duration: 2)])
        let text = [recording.summary, recording.facts()] + recording.names.flatMap { $0.rows(locale: Self.english) }
            .flatMap { [$0.label, $0.text] }
        for part in text {
            #expect(!part.contains("·") && !part.contains("•") && !part.contains("|") && !part.contains("+"))
        }
    }

    @Test func factsReadAsProse() {
        let nbsp = "\u{00A0}"
        let whole = WorkIndex.Recording(
            id: "r", album: "Dvořák Symphonies", year: 1972,
            songs: (1...4).map { Self.track("t\($0)", $0, duration: 629) })
        #expect(whole.facts() == "Recorded in 1972 on Dvořák Symphonies. 42\(nbsp)minutes, 4\(nbsp)movements.")
        #expect(whole.facts(includingAlbum: false) == "Recorded in 1972. 42\(nbsp)minutes, 4\(nbsp)movements.")
        #expect(
            WorkIndex.Recording(id: "r", album: "", songs: [Self.track("a", 1)]).facts() == "1\(nbsp)movement.")
    }

    @Test func durationsRoundToTheNearestMinuteAndNeverUnderOne() {
        let nbsp = "\u{00A0}"
        #expect(WorkIndex.Recording.duration(2518) == "42\(nbsp)minutes")
        #expect(WorkIndex.Recording.duration(5) == "1\(nbsp)minute")
        #expect(WorkIndex.Recording.duration(6480) == "1\(nbsp)hour 48\(nbsp)minutes")
        #expect(WorkIndex.Recording.duration(7200) == "2\(nbsp)hours")
        #expect(WorkIndex.Recording.duration(0) == nil)
    }

    @Test func aPartialRecordingSaysHowManyMovementsItHolds() {
        func movement(_ id: String, _ number: Int) -> Song {
            var song = Self.track(id, number, duration: 600)
            song.movements = [Song.Movement(name: "M", number: number, count: 5)]
            return song
        }
        let part = WorkIndex.Recording(
            id: "r", album: "A", songs: [movement("a", 1), movement("b", 3), movement("c", 4)])
        #expect(part.facts(includingAlbum: false).hasSuffix("3 of 5 movements."))
    }

    @Test func albumNamesDoNotDependOnTheFirstTrack() {
        let first = Self.track("a", 1, [Self.who("conductor", "Carl")])
        let second = Self.track("b", 2, [Self.who("performer", "Daniel", "piano")])
        for songs in [[first, second], [second, first]] {
            let names = Roles.lines(of: songs.sorted { ($0.track ?? 0) < ($1.track ?? 0) })
            #expect(names.flatMap(\.names) == ["Carl", "Daniel"])
        }
    }

    @Test func aRoleThatKlassikDoesNotKnowShowsUnderItsOwnTag() {
        let lines = Roles.lines(of: [
            Self.track("a", 1, [Self.who("director", "Dora Stage"), Self.who("producer", "Pat Booth")])
        ])
        #expect(lines.map(\.label) == ["director"])
        #expect(lines.first?.kind == .other)
        #expect(lines.flatMap(\.names) == ["Dora Stage"])
    }

    @Test func aNameThatHoldsAGroupWordIsAnEnsembleWhateverTheTagSays() {
        for name in [
            "Testing Philharmonic", "Berliner Philharmoniker", "Kammerorchester Basel", "London Symphony",
            "Wiener Symphoniker", "Chor des Bayerischen Rundfunks", "Tokyo String Quartett",
        ] {
            let lines = Roles.lines(of: [Self.track("a", 1, [Self.who("performer", name)])])
            #expect(lines.map(\.kind) == [.ensemble], "\(name)")
        }
    }

    @Test func aPersonIsNotAnEnsemble() {
        for name in ["Eva Bogen", "Anna Chorley", "Marie Kammerer"] {
            let lines = Roles.lines(of: [Self.track("a", 1, [Self.who("performer", name)])])
            #expect(lines.first?.kind == .soloist, "\(name)")
        }
    }

    @Test func theArtistTagKeepsAnOrchestraThatContributorsLeaveOut() {
        let song = Self.track("a", 1, artist: "Bavarian Radio Symphony Orchestra", [Self.who("conductor", "Carl")])
        #expect(Roles.lines(of: [song]).map(\.kind) == [.conductor, .unlabelled])
        #expect(Roles.lines(of: [song]).last?.names == ["Bavarian Radio Symphony Orchestra"])
    }

    @Test func theArtistTagDoesNotRepeatANameThatContributorsHold() {
        let song = Self.track("a", 1, artist: "Carl Fixture", [Self.who("conductor", "Carl Fixture")])
        #expect(Roles.lines(of: [song]).flatMap(\.names) == ["Carl Fixture"])
        let withSoloist = Self.track(
            "b", 1, artist: "Some Orchestra", [Self.who("conductor", "Carl"), Self.who("performer", "Eva", "viola")])
        #expect(Roles.lines(of: [withSoloist]).flatMap(\.names) == ["Carl", "Eva"])
    }

    @Test func namesWithoutASortNameSortByTheirLastWordLikeSortNames() {
        let people = [
            Self.who("performer", "Mia Mid", "viola"),
            Self.who("performer", "Rafael Kubelík", "viola", sort: "Kubelík, Rafael"),
        ]
        for contributors in [people, people.reversed()] {
            #expect(Roles.lines(of: [Self.track("a", 1, contributors)]).first?.names == ["Rafael Kubelík", "Mia Mid"])
        }
    }

    @Test func aRecordingKeepsItsNamesWhenItsTracksChange() {
        var recording = WorkIndex.Recording(
            id: "r", album: "A", songs: [Self.track("a", 1, [Self.who("conductor", "One")])])
        #expect(recording.names.flatMap(\.names) == ["One"])
        recording.songs = [Self.track("b", 1, [Self.who("conductor", "Two")])]
        #expect(recording.names.flatMap(\.names) == ["Two"])
    }

    @Test func aRecordingReadsBackWithItsNames() throws {
        let recording = WorkIndex.Recording(
            id: "r", album: "A", year: 1990, songs: [Self.track("a", 1, [Self.who("conductor", "One")])], isAlbum: true)
        let read = try JSONDecoder().decode(WorkIndex.Recording.self, from: JSONEncoder().encode(recording))
        #expect(read.names == recording.names && read.isAlbum && read.year == 1990)
    }
}
