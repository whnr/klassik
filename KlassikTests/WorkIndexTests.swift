import Foundation
import Testing
@testable import Klassik

struct WorkIndexTests {
    static func song(
        _ id: String, album: String, track: Int, composer: String = "Ludwig van Beethoven", work: String? = nil,
        year: Int? = nil, performers: [(String, String)] = []
    ) -> Song {
        Song(
            id: id, title: "Track \(track)", album: album, albumId: album, artist: "Album Artist", track: track,
            discNumber: 1, year: year, displayComposer: composer,
            contributors: performers.map { Song.Contributor(role: $0.0, artist: Song.Artist(id: $0.1, name: $0.1)) },
            works: work.map { [Song.Work(name: $0)] })
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
        let tagged = Self.song("t", album: "A", track: 1, performers: [("conductor", "Anna Probe"), ("performer", "Eva Bogen")])
        #expect(tagged.performers == "Eva Bogen, Anna Probe")
        #expect(Self.song("u", album: "A", track: 1).performers == "Album Artist")
    }
}
