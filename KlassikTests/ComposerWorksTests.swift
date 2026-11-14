import Foundation
import Testing

@testable import Klassik

struct ComposerWorksTests {
    static func song(_ id: String, work: String?, genres: [String], grouping: String? = nil) -> Song {
        Song(
            id: id, title: "Track \(id)", album: "Album \(id)", albumId: "album-\(id)", track: 1, discNumber: 1,
            genres: genres.map { Song.Genre(name: $0) }, displayComposer: "Frédéric Chopin",
            works: work.map { [Song.Work(name: $0)] }, groupings: grouping.map { [$0] })
    }

    static func chopin(_ songs: [Song]) throws -> ComposerWorks {
        ComposerWorks(try #require(WorkIndex(songs: songs).composers.first))
    }

    @Test func rowsRunAToZAndFoldSets() throws {
        let works = try Self.chopin([
            Self.song("a", work: "Waltz in A minor", genres: ["Piano"]),
            Self.song("b", work: "Etude No. 2", genres: ["Piano"], grouping: "Etudes, Op. 10"),
            Self.song("c", work: "Etude No. 1", genres: ["Piano"], grouping: "Etudes, Op. 10"),
            Self.song("d", work: "Ballade No. 1", genres: ["Piano"]),
        ])
        let rows = works.rows()
        #expect(rows.map(\.title) == ["Ballade No. 1", "Etudes, Op. 10", "Waltz in A minor"])
        #expect(rows[1].works.map(\.title) == ["Etude No. 1", "Etude No. 2"])
    }

    @Test func aSetOfOneWorkIsAWork() throws {
        let works = try Self.chopin([Self.song("a", work: "Etude No. 1", genres: [], grouping: "Etudes, Op. 10")])
        guard case .work = try #require(works.rows().first) else {
            Issue.record("expected a work row")
            return
        }
    }

    @Test func aGenreEveryWorkCarriesIsHidden() throws {
        let works = try Self.chopin([
            Self.song("a", work: "Ballade", genres: ["Classical", "Piano"]),
            Self.song("b", work: "Concerto", genres: ["Classical", "Orchestral"]),
            Self.song("c", work: "Etude", genres: ["Classical", "Piano"]),
        ])
        #expect(works.genres == ["Piano", "Orchestral"])
    }

    @Test func chipsJoinWithOr() throws {
        let works = try Self.chopin([
            Self.song("a", work: "Ballade", genres: ["Piano"]),
            Self.song("b", work: "Concerto", genres: ["Orchestral"]),
            Self.song("c", work: "Song", genres: ["Vocal"]),
        ])
        #expect(works.rows(filter: ["Piano", "Vocal"]).map(\.title) == ["Ballade", "Song"])
        #expect(works.rows(filter: ["Orchestral"]).map(\.title) == ["Concerto"])
        #expect(works.rows(filter: []).count == 3)
    }

    @Test func aSetKeepsOnlyTheWorksThatMatch() throws {
        let works = try Self.chopin([
            Self.song("a", work: "Nocturne 1", genres: ["Piano"], grouping: "Nocturnes"),
            Self.song("b", work: "Nocturne 2", genres: ["Arrangement"], grouping: "Nocturnes"),
            Self.song("c", work: "Nocturne 3", genres: ["Piano"], grouping: "Nocturnes"),
        ])
        #expect(works.rows(filter: ["Piano"]).first?.works.map(\.title) == ["Nocturne 1", "Nocturne 3"])
        #expect(works.rows(filter: ["Arrangement"]).first?.works.map(\.title) == ["Nocturne 2"])
    }

    @Test func albumsWithoutWorkTagsStayAsOneEntry() throws {
        let works = try Self.chopin([
            Self.song("a", work: nil, genres: ["Piano"]),
            Self.song("b", work: "Ballade", genres: ["Piano"]),
        ])
        #expect(works.rows().count == 2)
    }
}

struct PortraitFramingTests {
    @Test func theFrameAlwaysCoversTheView() {
        let frame = CGSize(width: 390, height: 400)
        let faces = [
            nil, CGRect(x: 0.05, y: 0.05, width: 0.1, height: 0.1), CGRect(x: 0.8, y: 0.9, width: 0.2, height: 0.1),
        ]
        let images = [
            CGSize(width: 800, height: 1200), CGSize(width: 3000, height: 1000), CGSize(width: 390, height: 400),
        ]
        for face in faces {
            for image in images {
                let rect = PortraitFraming.rect(image: image, frame: frame, face: face)
                #expect(rect.minX <= 0.001 && rect.minY <= 0.001)
                #expect(rect.maxX >= frame.width - 0.001 && rect.maxY >= frame.height - 0.001)
            }
        }
    }

    @Test func aSmallFaceZoomsAtMostTwice() {
        let frame = CGSize(width: 400, height: 400)
        let image = CGSize(width: 2000, height: 2000)
        let fill = max(frame.width / image.width, frame.height / image.height)
        let face = CGRect(x: 0.45, y: 0.3, width: 0.02, height: 0.02)
        let rect = PortraitFraming.rect(image: image, frame: frame, face: face)
        #expect(rect.width <= image.width * fill * 2 + 0.001)
        #expect(rect.width > image.width * fill)
    }

    @Test func theFaceStaysInTheFrame() {
        let frame = CGSize(width: 390, height: 400)
        let face = CGRect(x: 0.4, y: 0.2, width: 0.2, height: 0.2)
        let rect = PortraitFraming.rect(image: CGSize(width: 1000, height: 1500), frame: frame, face: face)
        let centre = CGPoint(x: rect.minX + face.midX * rect.width, y: rect.minY + face.midY * rect.height)
        #expect(centre.x > 0 && centre.x < frame.width)
        #expect(centre.y > 0 && centre.y < frame.height * 0.6)
    }

    @Test func visibleAreaIsInsideThePicture() {
        let frame = CGSize(width: 390, height: 400)
        let rect = PortraitFraming.rect(image: CGSize(width: 1000, height: 1500), frame: frame, face: nil)
        let visible = PortraitFraming.visible(of: rect, in: frame)
        #expect(visible.minX >= -0.001 && visible.minY >= -0.001 && visible.maxX <= 1.001 && visible.maxY <= 1.001)
    }
}

struct PictureScrimTests {
    typealias RGB = PictureScrim.RGB

    private func grounds(_ picture: RGB, increased: Bool) -> (Double, Double) {
        let opacity = PictureScrim.opacity(over: picture, increasedContrast: increased)
        let ground = picture.covered(by: PictureScrim.hall, opacity: opacity)
        return (opacity, PictureScrim.contrast(over: ground))
    }

    @Test func aDarkPictureGetsTheMinimum() {
        #expect(PictureScrim.opacity(over: RGB(red: 0.1, green: 0.1, blue: 0.1), increasedContrast: false) == 0.25)
    }

    @Test(arguments: [0.4, 0.5, 0.6, 0.7, 0.8])
    func aLighterPictureGetsJustEnough(grey: Double) {
        let (opacity, ratio) = grounds(RGB(red: grey, green: grey, blue: grey), increased: false)
        #expect(opacity >= PictureScrim.minimum && opacity <= PictureScrim.maximum)
        #expect(ratio >= 4.5 - 0.01)
    }

    @Test func increaseContrastRaisesTheTargets() {
        let picture = RGB(red: 0.6, green: 0.6, blue: 0.6)
        let standard = PictureScrim.opacity(over: picture, increasedContrast: false)
        let increased = PictureScrim.opacity(over: picture, increasedContrast: true)
        #expect(increased > standard)
        #expect(PictureScrim.contrast(over: picture.covered(by: PictureScrim.hall, opacity: increased)) >= 7 - 0.01)
    }

    @Test func aWhitePictureStillReachesTheTarget() {
        let (opacity, ratio) = grounds(RGB(red: 1, green: 1, blue: 1), increased: true)
        #expect(opacity <= PictureScrim.maximum)
        #expect(ratio >= 7 - 0.01)
    }
}

struct PortraitLoaderTests {
    private func request(_ url: String) -> (URL, Counter) { (URL(string: url)!, Counter()) }

    final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var value = 0
        var count: Int { lock.withLock { value } }
        func hit() { lock.withLock { value += 1 } }
    }

    @Test func aPictureOnAnUntrustedHostIsNeverRequested() async {
        for link in ["http://upload.wikimedia.org/a.jpg", "https://upload.example/a.jpg", "file:///etc/hosts"] {
            let (url, counter) = request(link)
            let loaded = await PortraitLoader.load(url) { _ in
                counter.hit()
                return (Data(), 200)
            }
            #expect(loaded == nil)
            #expect(counter.count == 0)
        }
    }

    @Test func anOversizeBodyGivesNoPicture() async {
        let (url, counter) = request("https://upload.wikimedia.org/a.jpg")
        let loaded = await PortraitLoader.load(url) { _ in
            counter.hit()
            return (Data(count: PortraitLoader.maxBytes + 1), 200)
        }
        #expect(loaded == nil)
        #expect(counter.count == 1)
    }

    @Test func aFailedOrNonImageBodyGivesNoPicture() async {
        let url = URL(string: "https://upload.wikimedia.org/a.jpg")!
        #expect(await PortraitLoader.load(url) { _ in (Data("not an image".utf8), 200) } == nil)
        #expect(await PortraitLoader.load(url) { _ in (Data(), 404) } == nil)
        #expect(await PortraitLoader.load(url) { _ in throw URLError(.timedOut) } == nil)
    }
}
