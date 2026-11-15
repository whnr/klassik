import Foundation
import Testing
import UIKit

@testable import Klassik

struct PortraitSizeTests {
    /// An iPhone Pro Max: 440 points wide at 3 pixels per point, with a 62 point top inset over the hero.
    static let proMax = PortraitSize.Screen(hero: CGSize(width: 440, height: 362), scale: 3)
    static let small = PortraitSize.Screen(hero: CGSize(width: 375, height: 320), scale: 2)
    static let aspects: [CGFloat] = [0.5, 0.75, 1, 1.5, 3]
    static let faces: [CGRect?] = [
        nil, CGRect(x: 0.45, y: 0.2, width: 0.02, height: 0.02), CGRect(x: 0.3, y: 0.1, width: 0.4, height: 0.4),
        CGRect(x: 0.8, y: 0.85, width: 0.1, height: 0.1),
    ]

    static let thumb = URL(
        string: "https://upload.wikimedia.org/wikipedia/commons/thumb/f/f0/Bach_%C3%A9.jpg/1280px-Bach_%C3%A9.jpg")!
    static let original = URL(string: "https://upload.wikimedia.org/wikipedia/commons/f/f0/Bach_%C3%A9.jpg")!

    @Test(arguments: [proMax, small])
    func theHeroGetsOnePicturePixelForEachScreenPixelAtEveryCrop(screen: PortraitSize.Screen) {
        for aspect in Self.aspects {
            let need = PortraitSize.width(aspect: aspect, screen: screen)
            for face in Self.faces {
                // The framing scales a picture of any resolution to the same width in points.
                let rect = PortraitFraming.rect(
                    image: CGSize(width: 1000 * aspect, height: 1000), frame: screen.hero, face: face)
                #expect(need >= rect.width * screen.scale - 0.001, "aspect \(aspect), face \(String(describing: face))")
            }
        }
    }

    @Test(arguments: [proMax, small])
    func theWholePictureGetsOnePicturePixelForEachScreenPixel(screen: PortraitSize.Screen) {
        let tall = CGSize(width: screen.hero.width, height: screen.hero.width * 2.2)
        for aspect in Self.aspects {
            let fit = min(tall.width, tall.height * aspect) * screen.scale
            #expect(PortraitSize.width(aspect: aspect, screen: screen) >= fit)
        }
    }

    @Test func aHalfWidthCropOfAProMaxHeroNeedsTwiceTheScreenWidth() {
        // A 3:4 portrait fills the hero by width; the largest face zoom leaves half the width visible.
        #expect(PortraitSize.heroWidth(aspect: 0.75, screen: Self.proMax) == 2640)
        #expect(PortraitSize.wholeWidth(screen: Self.proMax) == 1320)
    }

    @Test func aNeedRoundsUpToAWikimediaStep() {
        #expect(PortraitSize.step(100) == 500)
        #expect(PortraitSize.step(1280) == 1280)
        #expect(PortraitSize.step(1320) == 1920)
        #expect(PortraitSize.step(2640) == 3840)
        #expect(PortraitSize.step(9000) == 3840)
    }

    @Test func aThumbnailChangesOnlyItsWidth() {
        #expect(
            PortraitSize.thumbnail(Self.thumb, width: 3840)?.absoluteString
                == "https://upload.wikimedia.org/wikipedia/commons/thumb/f/f0/Bach_%C3%A9.jpg/3840px-Bach_%C3%A9.jpg")
        let folder = "https://upload.wikimedia.org/wikipedia/commons/thumb/a/ab/Score.tif/"
        let paged = URL(string: folder + "lossy-page1-1280px-Score.tif.jpg")!
        #expect(PortraitSize.thumbnail(paged, width: 1920)?.lastPathComponent == "lossy-page1-1920px-Score.tif.jpg")
    }

    @Test func theRecordedCommonsThumbnailKeepsItsHostAndQuery() throws {
        let parsed = try #require(PersonFactsService.parsePortrait(Data(RecordedWikimedia.bachCommons.utf8)))
        let url = try #require(PortraitSize.thumbnail(parsed.portrait.url, width: 2560))
        #expect(url.host == parsed.portrait.url.host)
        #expect(url.query == parsed.portrait.url.query)
        #expect(url.lastPathComponent == "2560px-Johann_Sebastian_Bach.png")
    }

    @Test func aURLThatIsNoThumbnailStaysAsItIs() {
        #expect(PortraitSize.thumbnail(Self.original, width: 1920) == nil)
        let fixture = URL(string: "https://thumb.wikimedia.org/fixture/portrait-1200.png")!
        #expect(PortraitSize.candidates(PersonPortrait(url: fixture), screen: Self.proMax).map(\.url) == [fixture])
    }

    @Test func aLargeOriginalGivesTheFullNeedOnWiFiThenTheScreenWidth() {
        let portrait = PersonPortrait(url: Self.thumb, original: Self.original, width: 6000, height: 8000)
        let candidates = PortraitSize.candidates(portrait, screen: Self.proMax)
        let names = candidates.map(\.url.lastPathComponent)
        #expect(names == ["3840px-Bach_é.jpg", "1920px-Bach_é.jpg", "1280px-Bach_é.jpg"])
        #expect(candidates.map(\.wifiOnly) == [true, false, false])
    }

    @Test func aNeedAtOrAboveTheOriginalGetsTheOriginal() {
        let portrait = PersonPortrait(url: Self.thumb, original: Self.original, width: 2000, height: 2667)
        let candidates = PortraitSize.candidates(portrait, screen: Self.proMax)
        #expect(candidates.map(\.url) == [Self.original, PortraitSize.thumbnail(Self.thumb, width: 1920)!, Self.thumb])
    }

    @Test func anOriginalThatUIImageCannotReadIsNeverAsked() {
        let tiff = URL(string: "https://upload.wikimedia.org/wikipedia/commons/f/f0/Bach.tif")!
        let portrait = PersonPortrait(url: Self.thumb, original: tiff, width: 2000, height: 2667)
        let candidates = PortraitSize.candidates(portrait, screen: Self.proMax)
        #expect(!candidates.map(\.url).contains(tiff))
        #expect(candidates.last?.url == Self.thumb)
    }

    @Test func storedFactsWithoutASizeStillGetALargerThumbnail() {
        let candidates = PortraitSize.candidates(PersonPortrait(url: Self.thumb), screen: Self.proMax)
        // A square counts: the hero needs 440 × 2 × 3 = 2640 pixels, so the step is 3840.
        #expect(candidates.first?.url.lastPathComponent == "3840px-Bach_é.jpg")
        #expect(candidates.first?.wifiOnly == true)
        #expect(candidates.last?.url == Self.thumb)
    }

    @Test func commonsGivesTheOriginalAndItsSize() throws {
        let json = """
            {"query":{"pages":{"1":{"imageinfo":[{"thumburl":"\(Self.thumb.absoluteString)",\
            "url":"\(Self.original.absoluteString)","width":3000,"height":4000}]}}}}
            """
        let portrait = try #require(PersonFactsService.parsePortrait(Data(json.utf8))).portrait
        #expect(portrait.original == Self.original)
        #expect(portrait.width == 3000 && portrait.height == 4000)
        #expect(portrait.aspect == 0.75)
    }

    @Test func factsStoredWithoutASizeStillDecode() throws {
        let json = #"{"url":"https://upload.wikimedia.org/a.jpg"}"#
        let portrait = try JSONDecoder().decode(PersonPortrait.self, from: Data(json.utf8))
        #expect(portrait.width == nil && portrait.aspect == nil)
    }
}

struct PortraitLoaderSizeTests {
    final class Requests: @unchecked Sendable {
        private let lock = NSLock()
        private var list: [URLRequest] = []
        var all: [URLRequest] { lock.withLock { list } }
        func add(_ request: URLRequest) { lock.withLock { list.append(request) } }
    }

    static func jpeg(width: CGFloat) -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: width, height: width * 4 / 3), format: format)
            .jpegData(withCompressionQuality: 0.5) { context in
                UIColor.brown.setFill()
                context.fill(CGRect(x: 0, y: 0, width: width, height: width * 4 / 3))
            }
    }

    static let portrait = PersonPortrait(
        url: PortraitSizeTests.thumb, original: PortraitSizeTests.original, width: 6000, height: 8000)

    @Test func theLargeFileAsksForWiFiAndKeepsOnlyTheNeededPixels() async throws {
        let requests = Requests()
        let loaded = try #require(
            await PortraitLoader.load(Self.portrait, screen: PortraitSizeTests.proMax) { request in
                requests.add(request)
                return (Self.jpeg(width: 3840), 200)
            })
        let first = try #require(requests.all.first)
        #expect(requests.all.count == 1)
        #expect(!first.allowsExpensiveNetworkAccess && !first.allowsConstrainedNetworkAccess)
        #expect(loaded.image.size.width == 2640)
    }

    @Test func withoutWiFiTheScreenWidthFileLoads() async throws {
        let requests = Requests()
        let loaded = try #require(
            await PortraitLoader.load(Self.portrait, screen: PortraitSizeTests.proMax) { request in
                requests.add(request)
                // URLSession refuses a request that forbids the expensive or constrained network it is on.
                guard request.allowsConstrainedNetworkAccess else { throw URLError(.notConnectedToInternet) }
                return (Self.jpeg(width: 1920), 200)
            })
        #expect(requests.all.map { $0.url?.lastPathComponent } == ["3840px-Bach_é.jpg", "1920px-Bach_é.jpg"])
        #expect(requests.all.last?.allowsConstrainedNetworkAccess == true)
        #expect(loaded.image.size.width == 1920)
    }

    @Test func whenEveryFileFailsThereIsNoPicture() async {
        let requests = Requests()
        let loaded = await PortraitLoader.load(Self.portrait, screen: PortraitSizeTests.proMax) { request in
            requests.add(request)
            return (Data(), 404)
        }
        #expect(loaded == nil)
        #expect(requests.all.count == 3)
    }
}
