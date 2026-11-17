import Foundation
import Testing
import UIKit

@testable import Klassik

struct PerformerPageTests {
    private static func song(_ id: String, album: String, year: Int?, who: [(String, String)]) -> Song {
        WorkIndexTests.song(id, album: album, track: 1, work: "Op. \(album)", year: year, performers: who)
    }

    private static let conductor = ("conductor", "Carl Fixture")

    @Test func albumsRunNewestFirstWithoutAYearLast() {
        let index = WorkIndex(songs: [
            Self.song("a", album: "Old", year: 1960, who: [Self.conductor]),
            Self.song("b", album: "New", year: 1990, who: [Self.conductor]),
            Self.song("c", album: "Undated", year: nil, who: [Self.conductor]),
            Self.song("d", album: "Other", year: 2000, who: [("conductor", "Someone Else")]),
        ])
        #expect(index.albums(ofPerformer: "Carl Fixture").map(\.title) == ["New", "Old", "Undated"])
        #expect(index.albums(ofPerformer: "Nobody").isEmpty)
    }

    @Test func rolesComeFromTheTagsInRoleOrder() throws {
        let index = WorkIndex(songs: [
            Self.song("a", album: "A", year: 1960, who: [("performer", "Carl Fixture")]),
            Self.song("b", album: "B", year: 1970, who: [Self.conductor]),
        ])
        let performer = try #require(index.performer(named: "Carl Fixture"))
        #expect(index.roles(ofPerformer: performer) == ["Conductor", "Soloist"])
    }

    @Test func tagRolesShowOnlyWithoutAWikidataDescription() {
        let described = PersonFacts(qid: "Q1", name: "X", description: "Fixture conductor", born: 1950)
        let bare = PersonFacts(qid: "Q1", name: "X", description: nil, born: 1950)
        #expect(PerformerPage.line(facts: described, roles: ["Conductor"]) == "Fixture conductor, born 1950")
        #expect(PerformerPage.line(facts: bare, roles: ["Conductor"]) == "Conductor, born 1950")
        #expect(PerformerPage.line(facts: nil, roles: ["Conductor"]) == nil)
    }

    private static func portrait(faces: [CGRect]) -> LoadedPortrait {
        LoadedPortrait(image: UIImage(), faces: faces)
    }

    @Test func aPictureIsAPortraitOnlyWithOneFace() {
        let face = CGRect(x: 0.4, y: 0.2, width: 0.2, height: 0.3)
        #expect(!Self.portrait(faces: []).isPortrait)
        #expect(Self.portrait(faces: [face]).isPortrait)
        #expect(!Self.portrait(faces: [face, face]).isPortrait)
    }

    @Test func aGroupOrAHallFillsTheFrameFromItsCentre() {
        let face = CGRect(x: 0.4, y: 0.2, width: 0.2, height: 0.3)
        #expect(Self.portrait(faces: [face]).framingFace(performer: true) == face)
        #expect(Self.portrait(faces: []).framingFace(performer: true) == nil)
        #expect(Self.portrait(faces: [face, face]).framingFace(performer: true) == nil)
    }

    @Test func aComposerPictureWithSeveralFacesCentresOnTheLargest() {
        let large = CGRect(x: 0.1, y: 0.1, width: 0.4, height: 0.5)
        let small = CGRect(x: 0.7, y: 0.2, width: 0.1, height: 0.1)
        #expect(Self.portrait(faces: [large, small]).framingFace(performer: false) == large)
        #expect(Self.portrait(faces: [large]).framingFace(performer: false) == large)
        #expect(Self.portrait(faces: []).framingFace(performer: false) == nil)
    }

    private static func part(
        _ id: String, albumID: String, track: Int, year: Int, artist: String?, album: String = "Encores",
        performer: (String, String) = PerformerPageTests.conductor
    ) -> Song {
        var song = WorkIndexTests.song(
            id, album: album, track: track, work: "Op. \(track)", year: year, performers: [performer])
        song.albumId = albumID
        song.displayAlbumArtist = artist
        return song
    }

    @Test func anAlbumThatTheServerSplitsByYearShowsOnce() throws {
        let index = WorkIndex(songs: [
            Self.part("a", albumID: "al-1999", track: 1, year: 1999, artist: "Carl Fixture"),
            Self.part("b", albumID: "al-2004", track: 2, year: 2004, artist: "Carl Fixture"),
        ])
        let albums = index.albums(ofPerformer: "Carl Fixture")
        #expect(albums.count == 1)
        let album = try #require(albums.first)
        #expect(album.tracks.map(\.id) == ["a", "b"])
        #expect(album.year == 1999)
        #expect(index.album("al-1999")?.id == album.id)
        #expect(index.album("al-2004")?.id == album.id)
        // A part opens the recording that the work page lists for this album.
        for part in album.parts {
            #expect(index.work(part.workID)?.recordings.contains { $0.id == part.recordingID } == true)
        }
    }

    /// Classical tags often set the album artist to the composer, so two pianists' releases can share both.
    @Test func twoReleasesWithOneNameAndOneAlbumArtistStayApart() throws {
        let first = ("performer", "Anna Probe")
        let second = ("performer", "Bert Probe")
        let index = WorkIndex(songs: [
            Self.part("a1", albumID: "al-a", track: 1, year: 1990, artist: "Ludwig van Beethoven", performer: first),
            Self.part("a2", albumID: "al-a", track: 2, year: 1990, artist: "Ludwig van Beethoven", performer: first),
            Self.part("b1", albumID: "al-b", track: 1, year: 2010, artist: "Ludwig van Beethoven", performer: second),
            Self.part("b2", albumID: "al-b", track: 2, year: 2010, artist: "Ludwig van Beethoven", performer: second),
        ])
        #expect(index.albums.count == 2)
        #expect(try #require(index.album("al-a")).tracks.map(\.id) == ["a1", "a2"])
        #expect(try #require(index.album("al-b")).tracks.map(\.id) == ["b1", "b2"])
        #expect(index.albums(ofPerformer: "Anna Probe").map(\.id) == ["al-a"])
        #expect(index.albums(ofPerformer: "Bert Probe").map(\.id) == ["al-b"])
    }

    @Test func aSplitAlbumMergesBesideAnotherReleaseWithItsName() throws {
        let other = ("performer", "Bert Probe")
        let index = WorkIndex(songs: [
            Self.part("a", albumID: "al-1999", track: 1, year: 1999, artist: "Carl Fixture"),
            Self.part("b", albumID: "al-2004", track: 2, year: 2004, artist: "Carl Fixture"),
            Self.part("x1", albumID: "al-x", track: 1, year: 2010, artist: "Carl Fixture", performer: other),
            Self.part("x2", albumID: "al-x", track: 2, year: 2010, artist: "Carl Fixture", performer: other),
        ])
        #expect(index.albums.count == 2)
        let split = try #require(index.album("al-2004"))
        #expect(split.id == "al-1999")
        #expect(split.tracks.map(\.id) == ["a", "b"])
        #expect(try #require(index.album("al-x")).tracks.map(\.id) == ["x1", "x2"])
    }

    /// One server album whose tracks disagree on the album artist or the album name must not stop the index build.
    @Test func oneAlbumIDWithTwoAlbumArtistsStaysOneAlbum() throws {
        let index = WorkIndex(songs: [
            Self.part("a", albumID: "al-1", track: 1, year: 1999, artist: "Carl Fixture"),
            Self.part("b", albumID: "al-1", track: 2, year: 1999, artist: "Someone Else"),
            Self.part("c", albumID: "al-1", track: 3, year: 1999, artist: nil, album: "Encores II"),
            Self.part("d", albumID: "al-2", track: 4, year: 2004, artist: "Carl Fixture"),
            Self.part("e", albumID: "al-3", track: 5, year: 2004, artist: "Someone Else"),
        ])
        #expect(index.albums.count == 3)
        #expect(try #require(index.album("al-1")).tracks.map(\.id) == ["a", "b", "c"])
        #expect(index.album("al-2")?.id == "al-2")
        #expect(index.album("al-3")?.id == "al-3")
    }

    @Test func albumsWithOneNameButNoAlbumArtistStayApart() {
        let index = WorkIndex(songs: [
            Self.part("a", albumID: "al-1", track: 1, year: 1999, artist: nil),
            Self.part("b", albumID: "al-2", track: 2, year: 2004, artist: nil),
        ])
        #expect(index.albums(ofPerformer: "Carl Fixture").count == 2)
    }

    @Test func aDownloadedPictureWithoutAFaceIsNoPortrait() async throws {
        let size = CGSize(width: 64, height: 64)
        let png = UIGraphicsImageRenderer(size: size).pngData { context in
            UIColor.gray.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
        let loaded = await PortraitLoader.load(URL(string: "https://upload.wikimedia.org/a.png")!) { _ in (png, 200) }
        #expect(try #require(loaded).faces.isEmpty)
        #expect(loaded?.isPortrait == false)
    }
}
