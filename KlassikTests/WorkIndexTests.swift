import Foundation
import Testing

@testable import Klassik

struct WorkIndexTests {
    static func song(
        _ id: String, album: String, track: Int, composer: String = "Ludwig van Beethoven", work: String? = nil,
        year: Int? = nil, performers: [(String, String)] = [], movement: (number: Int, count: Int)? = nil,
        contributors: [Song.Contributor]? = nil, grouping: String? = nil
    ) -> Song {
        Song(
            id: id, title: "Track \(track)", album: album, albumId: album, artist: "Album Artist", track: track,
            discNumber: 1, year: year, displayComposer: composer,
            contributors: contributors
                ?? performers.map { Song.Contributor(role: $0.0, artist: Song.Artist(id: $0.1, name: $0.1)) },
            works: work.map { [Song.Work(name: $0)] },
            movements: movement.map { [Song.Movement(name: "M", number: $0.number, count: $0.count)] },
            groupings: grouping.map { [$0] })
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

    @Test func setsFollowTheGroupingTagInNaturalOrder() throws {
        func piece(_ id: String, _ work: String, _ grouping: String?) -> Song {
            Self.song(id, album: "Edition", track: 1, composer: "Frédéric Chopin", work: work, grouping: grouping)
        }
        let chopin = try #require(
            WorkIndex(songs: [
                piece("a", "Mazurka No. 5", "Mazurkas, Op. 7"),
                piece("b", "Mazurka No. 1", "Mazurkas, Op. 17"),
                piece("c", "Mazurka No. 2", "Mazurkas, Op. 7"),
                piece("d", "Waltz in A minor", nil),
            ]).composers.first)
        #expect(chopin.sets.map(\.name) == ["Mazurkas, Op. 7", "Mazurkas, Op. 17"])
        #expect(chopin.sets.first?.works.map(\.title) == ["Mazurka No. 2", "Mazurka No. 5"])
        #expect(chopin.looseWorks.map(\.title) == ["Waltz in A minor"])
    }

    @Test func genresShowOnceWhenTheServerSendsThemTwice() {
        let song = Song(id: "g", title: "T", genre: "Classical", genres: [Song.Genre(name: "Classical")])
        #expect(song.allGenres == ["Classical"])
    }

    @Test func tagsScreenExplainsAWholeAlbum() throws {
        let tracks = [Self.song("t1", album: "Box", track: 1, work: "Op. 60")]
        let whole = try #require(WorkIndex.album(tracks)).work
        #expect(whole.groupingReason.hasPrefix("A whole album"))
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
        #expect(album.recording.names.flatMap(\.names) == ["Album Artist"])
        #expect(album.work.title == "Encores")
        #expect(WorkIndex.album([]) == nil)
    }

    @Test(arguments: [false, true])
    func albumPerformersMatchDirectAndRecordingWalks(visitRecordingFirst: Bool) throws {
        let brahms = Self.song(
            "b", album: "Romantic Encores", track: 1, work: "Op. 98",
            performers: [("performer", "Sine Wave Chamber Orchestra"), ("conductor", "Carl Fixture")])
        let mozart = Self.song(
            "m", album: "Romantic Encores", track: 2, work: "K. 467",
            contributors: [
                .init(role: "conductor", artist: .init(id: "c", name: "Carl Fixture")),
                .init(
                    role: "performer", subRole: "orchestra", artist: .init(id: "o", name: "Sine Wave Chamber Orchestra")
                ),
                .init(role: "performer", subRole: "piano", artist: .init(id: "p", name: "Daniel Keys")),
            ])
        var encore = Self.song("e", album: "Romantic Encores", track: 1)
        encore.discNumber = 2
        encore.artist = "Guest Soloist"

        // Sync responses and contributor lists can arrive in either order.
        for tracks in [[brahms, mozart, encore], [encore, mozart, brahms], [mozart, brahms, encore]] {
            for reverseContributors in [false, true] {
                let tracks = tracks.map { song in
                    var song = song
                    if reverseContributors { song.contributors = song.contributors?.reversed() }
                    return song
                }
                if visitRecordingFirst {
                    let index = WorkIndex(songs: tracks)
                    let recording = try #require(index.composers.first?.works.first?.defaultRecording)
                    #expect(!recording.songs.isEmpty)
                }
                let album = try #require(WorkIndex.album(tracks))
                #expect(
                    album.recording.names.flatMap(\.names)
                        == ["Carl Fixture", "Daniel Keys", "Sine Wave Chamber Orchestra", "Guest Soloist"])
                #expect(album.recording.summary.contains("•") == false)
                #expect(album.recording.songs.map(\.id) == ["b", "m", "e"])
            }
        }
    }

    @Test func albumOrdersEqualTrackNumbersByID() throws {
        let first = Self.song("a", album: "A", track: 1, performers: [("performer", "First Soloist")])
        var second = Self.song("b", album: "A", track: 1, performers: [("performer", "Second Soloist")])
        second.title = "Other Track"
        for tracks in [[first, second], [second, first]] {
            let album = try #require(WorkIndex.album(tracks))
            #expect(album.recording.names.flatMap(\.names) == ["First Soloist", "Second Soloist"])
        }
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

    @Test func conductorLeadsAndTheTrackArtistStandsInWithoutRoles() {
        let tagged = Self.song(
            "t", album: "A", track: 1, performers: [("conductor", "Anna Probe"), ("performer", "Eva Bogen")])
        #expect(Roles.lines(of: [tagged]).flatMap(\.names) == ["Anna Probe", "Eva Bogen"])
        #expect(Roles.lines(of: [Self.song("u", album: "A", track: 1)]).flatMap(\.names) == ["Album Artist"])
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
        #expect(work.context == "Symphonie Nr.5 c-moll")
    }

    @Test func namesKeepTheirOrderWhateverOrderTheServerSends() {
        func contributor(_ role: String, _ name: String, _ subRole: String? = nil) -> Song.Contributor {
            Song.Contributor(role: role, subRole: subRole, artist: Song.Artist(id: name, name: name))
        }
        let contributors = [
            contributor("conductor", "Anna Probe"), contributor("performer", "Testing Philharmonic", "orchestra"),
            contributor("performer", "Eva Bogen", "violin"), contributor("performer", "Adam Alto", "viola"),
        ]
        let song = Self.song("t", album: "A", track: 1, contributors: contributors)
        let names = Roles.lines(of: [song]).flatMap(\.names)
        #expect(names == ["Anna Probe", "Adam Alto", "Eva Bogen", "Testing Philharmonic"])
        let shuffled = Self.song("t", album: "A", track: 1, contributors: contributors.reversed())
        #expect(Roles.lines(of: [shuffled]).flatMap(\.names) == names)
    }

    @Test func completenessNamesMissingMovements() {
        let part = WorkIndex.Recording(
            id: "r", album: "A",
            songs: [
                Self.song("a", album: "A", track: 1, movement: (1, 5)),
                Self.song("b", album: "A", track: 2, movement: (3, 5)),
                Self.song("c", album: "A", track: 3, movement: (4, 5)),
            ])
        #expect(part.completeness == "3 of 5 movements")
        let whole = WorkIndex.Recording(
            id: "r", album: "A", songs: [Self.song("a", album: "A", track: 1, movement: (1, 1))])
        #expect(whole.completeness == nil)
        #expect(WorkIndex.Recording(id: "r", album: "A", songs: []).completeness == nil)
    }
}
