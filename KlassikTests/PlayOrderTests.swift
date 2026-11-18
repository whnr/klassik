import Foundation
import Testing

@testable import Klassik

struct PlayOrderTests {
    /// Nine symphonies on nine discs, every disc tagged Disc 1. The movement titles repeat across discs.
    static func box() -> [Song] {
        (1...3).flatMap { disc in
            (1...4).map { track in
                Song(
                    id: "s\(disc)t\(track)", title: "Movement \(track)", album: "Symphonies", albumId: "box",
                    artist: "Masur", track: track, discNumber: 1, displayComposer: "Ludwig van Beethoven",
                    path: "Beethoven/Symphonies/CD\(disc)/0\(track) Movement.flac")
            }
        }
    }

    @Test func ordersACollidingBoxByPath() {
        let shuffled = Self.box().reversed()
        let ids = Song.playOrder(Array(shuffled)).map(\.id)
        #expect(ids == (1...3).flatMap { disc in (1...4).map { "s\(disc)t\($0)" } })
    }

    @Test func ordersPathsByNumber() {
        let songs = ["CD10/01.flac", "CD2/01.flac", "CD1/01.flac"].enumerated().map { index, path in
            Song(id: "x\(index)", title: "T\(index)", track: 1, discNumber: 1, path: path)
        }
        #expect(Song.playOrder(songs).map(\.path) == ["CD1/01.flac", "CD2/01.flac", "CD10/01.flac"])
    }

    @Test func keepsDiscAndTrackOrderWhenTheTagsAreRight() {
        let songs = [
            Song(id: "b", title: "B", track: 1, discNumber: 2, path: "a/z.flac"),
            Song(id: "a", title: "A", track: 2, discNumber: 1, path: "a/y.flac"),
            Song(id: "c", title: "C", track: 1, discNumber: 1, path: "a/x.flac"),
        ]
        #expect(Song.playOrder(songs).map(\.id) == ["c", "a", "b"])
    }

    @Test func keepsServerOrderWithoutPaths() {
        let songs = (1...3).flatMap { disc in
            (1...2).map { Song(id: "d\(disc)t\($0)", title: "T\(disc)", track: $0, discNumber: 1) }
        }
        #expect(Song.playOrder(songs).map(\.id) == ["d1t1", "d2t1", "d3t1", "d1t2", "d2t2", "d3t2"])
    }

    @Test func albumPlaysTheBoxInOrder() throws {
        let album = Album(id: "box", name: "Symphonies", song: Array(Self.box().reversed()))
        #expect(album.songs.map(\.id).first == "s1t1")
        #expect(album.songs.map(\.id).last == "s3t4")
        let whole = try #require(WorkIndex.album(Array(Self.box().reversed())))
        #expect(whole.recording.songs.map(\.id) == Self.box().map(\.id))
    }

    @Test func aFileHeldTwiceStillPlaysOnce() throws {
        var songs = Self.box()
        songs.append(songs[0])
        let whole = try #require(WorkIndex.album(songs))
        #expect(whole.recording.songs.count == 12)
    }
}
