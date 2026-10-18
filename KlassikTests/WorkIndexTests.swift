import Foundation
import Testing

@testable import Klassik

struct WorkIndexTests {
    static func song(
        _ id: String, album: String, track: Int, composer: String = "Ludwig van Beethoven", work: String? = nil,
        year: Int? = nil, performers: [(String, String)] = [], movement: (number: Int, count: Int)? = nil,
        contributors: [Song.Contributor]? = nil
    ) -> Song {
        Song(
            id: id, title: "Track \(track)", album: album, albumId: album, artist: "Album Artist", track: track,
            discNumber: 1, year: year, displayComposer: composer,
            contributors: contributors
                ?? performers.map { Song.Contributor(role: $0.0, artist: Song.Artist(id: $0.1, name: $0.1)) },
            works: work.map { [Song.Work(name: $0)] },
            movements: movement.map { [Song.Movement(name: "M", number: $0.number, count: $0.count)] })
    }

    @Test func groupsTaggedWorksIntoRecordingsByAlbum() throws {
        let index = WorkIndex(songs: [
            Self.song("b2", album: "Karajan", track: 2, work: "Op. 67", year: 1963),
            Self.song("b1", album: "Karajan", track: 1, work: "Op. 67", year: 1963),
            Self.song("a1", album: "Kleiber", track: 1, work: "Op. 67", year: 1975),
            Self.song("k1", album: "Bach", track: 1, composer: "Johann Sebastian Bach", work: "BWV 1007"),
        ])
        #expect(index.composers.map(\.name) == ["Johann Sebastian Bach", "Ludwig van Beethoven"])
        let fifth = try #require(index.composers.last?.works.first)
        #expect(fifth.isTagged)
        #expect(fifth.recordings.map(\.album) == ["Karajan", "Kleiber"])
        #expect(fifth.recordings.first?.songs.map(\.id) == ["b1", "b2"])
    }

    /// A whole album plays in disc and track order and names each track in full, because it can hold several works.
    @Test func albumPlaysAllTracksOnce() throws {
        var movement = Self.song("m2", album: "Encores", track: 2, work: "Op. 98")
        movement.movements = [Song.Movement(name: "Allegro giocoso")]
        let duplicate = Self.song("x1", album: "Encores", track: 1)
        let album = try #require(WorkIndex.album([movement, Self.song("m1", album: "Encores", track: 1), duplicate]))
        #expect(album.recording.isAlbum)
        #expect(album.recording.songs.map(\.id) == ["m1", "m2"])
        #expect(album.recording.title(of: movement) == "Track 2")
        #expect(album.recording.performers == "Album Artist")
        #expect(album.work.title == "Encores")
        #expect(WorkIndex.album([]) == nil)
    }

    /// Only a recording with every track starred is the reference. The reference plays when the work plays.
    @Test func starredRecordingIsTheReference() throws {
        var first = Self.song("k1", album: "Kleiber", track: 1, work: "Op. 67", year: 1975)
        var second = Self.song("k2", album: "Kleiber", track: 2, work: "Op. 67", year: 1975)
        let early = Self.song("b1", album: "Karajan", track: 1, work: "Op. 67", year: 1963)
        let partly = try #require(WorkIndex(songs: [first, second, early]).composers.first?.works.first)
        #expect(partly.defaultRecording?.album == "Karajan")
        first.starred = "2026-10-18T00:00:00Z"
        let half = try #require(WorkIndex(songs: [first, second, early]).composers.first?.works.first)
        #expect(half.recordings.allSatisfy { !$0.isReference })
        second.starred = "2026-10-18T00:00:00Z"
        let whole = try #require(WorkIndex(songs: [first, second, early]).composers.first?.works.first)
        #expect(whole.defaultRecording?.album == "Kleiber")
        #expect(whole.defaultRecording?.isReference == true)
    }

    @Test func albumIsTheWorkWithoutWorkTag() throws {
        let index = WorkIndex(songs: [
            Self.song("s1", album: "Symphonie Nr.5", track: 1), Self.song("s2", album: "Symphonie Nr.5", track: 2),
        ])
        let work = try #require(index.composers.first?.works.first)
        #expect(!work.isTagged)
        #expect(work.title == "Symphonie Nr.5")
        #expect(work.recordings.first?.songs.count == 2)
    }

    /// The server holds some files twice; each movement plays once.
    @Test func dropsDuplicateTracks() {
        let index = WorkIndex(songs: [
            Self.song("s1", album: "Symphonie Nr.5", track: 1), Self.song("s1-copy", album: "Symphonie Nr.5", track: 1),
        ])
        #expect(index.composers.first?.works.first?.recordings.first?.songs.map(\.id) == ["s1"])
    }

    @Test func performersBeforeConductorElseArtist() {
        let tagged = Self.song(
            "t", album: "A", track: 1, performers: [("conductor", "Anna Probe"), ("performer", "Eva Bogen")])
        #expect(tagged.performers == "Eva Bogen, Anna Probe")
        #expect(Self.song("u", album: "A", track: 1).performers == "Album Artist")
    }

    @Test(
        arguments: [
            (["Symphonie Nr.5 c-moll (1)", "Symphonie Nr.5 c-moll (2)"], "Symphonie Nr.5 c-moll"),
            (
                ["Violin Concerto in E minor, Op. 64: I. Allegro", "Violin Concerto in E minor, Op. 64: II. Andante"],
                "Violin Concerto in E minor, Op. 64"
            ),
            (["Symphony No. 9: IV. Presto"], "Symphony No. 9: IV. Presto"),
            (["Blue Sine", "Square Dance"], nil),
        ] as [([String], String?)])
    func sharedTitleNamesTheWork(titles: [String], expected: String?) {
        #expect(WorkIndex.commonTitle(titles) == expected)
    }

    /// A WORK tag such as "Op. 67" alone does not say which symphony it is.
    @Test func contextNamesTheWorkFromTitlesAndAlbum() throws {
        var first = Self.song("s1", album: "Symphonie Nr.5", track: 1, work: "Op. 67")
        var second = Self.song("s2", album: "Symphonie Nr.5", track: 2, work: "Op. 67")
        first.title = "Symphonie Nr.5 c-moll (1)"
        second.title = "Symphonie Nr.5 c-moll (2)"
        let work = try #require(WorkIndex(songs: [first, second]).composers.first?.works.first)
        #expect(work.context == "Symphonie Nr.5 c-moll · Symphonie Nr.5")
    }

    @Test func performersListSoloistsThenEnsemblesThenConductor() {
        func contributor(_ role: String, _ name: String, _ subRole: String? = nil) -> Song.Contributor {
            Song.Contributor(role: role, subRole: subRole, artist: Song.Artist(id: name, name: name))
        }
        let contributors = [
            contributor("conductor", "Anna Probe"), contributor("performer", "Testing Philharmonic", "orchestra"),
            contributor("performer", "Eva Bogen", "violin"), contributor("performer", "Adam Alto", "viola"),
        ]
        let song = Self.song("t", album: "A", track: 1, contributors: contributors)
        #expect(song.performers == "Adam Alto, Eva Bogen, Testing Philharmonic, Anna Probe")
        let shuffled = Self.song("t", album: "A", track: 1, contributors: contributors.reversed())
        #expect(shuffled.performers == song.performers)
    }

    @Test func completenessNamesMissingMovements() {
        let part = WorkIndex.Recording(
            id: "r", album: "A", performers: "",
            songs: [
                Self.song("a", album: "A", track: 1, movement: (1, 5)),
                Self.song("b", album: "A", track: 2, movement: (3, 5)),
                Self.song("c", album: "A", track: 3, movement: (4, 5)),
            ])
        #expect(part.completeness == "3 of 5 movements")
        let whole = WorkIndex.Recording(
            id: "r", album: "A", performers: "", songs: [Self.song("a", album: "A", track: 1, movement: (1, 1))])
        #expect(whole.completeness == nil)
        #expect(WorkIndex.Recording(id: "r", album: "A", performers: "", songs: []).completeness == nil)
    }
}
