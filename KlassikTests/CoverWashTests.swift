import Foundation
import SwiftUI
import Testing
import UIKit

@testable import Klassik

/// The cover hue and the player wash of ADR 0034.
@MainActor
struct CoverWashTests {
    static func hex(_ value: UInt32) -> SRGB {
        SRGB(
            red: Double((value >> 16) & 0xff) / 255, green: Double((value >> 8) & 0xff) / 255,
            blue: Double(value & 0xff) / 255)
    }

    /// A 32 by 32 sample cover: the first colours fill their counts of pixels, the last colour fills the rest.
    static func cover(_ parts: [(UInt32, Int)], rest: UInt32) -> [SRGB] {
        let side = CoverHue.side * CoverHue.side
        var pixels = parts.flatMap { Array(repeating: hex($0.0), count: $0.1) }
        pixels += Array(repeating: hex(rest), count: side - pixels.count)
        return pixels
    }

    /// The angle between two hues, in degrees.
    static func distance(_ first: Double, _ second: Double) -> Double {
        let difference = abs(first - second).truncatingRemainder(dividingBy: 360)
        return min(difference, 360 - difference)
    }

    static let rooms: [(room: WashRoom, style: UIUserInterfaceStyle, contrast: UIAccessibilityContrast)] = [
        (.light, .light, .normal),
        (.dark, .dark, .normal),
        (.lightIncreasedContrast, .light, .high),
        (.darkIncreasedContrast, .dark, .high),
    ]

    /// A colour of the asset catalog in a room.
    static func base(_ colour: Palette, style: UIUserInterfaceStyle, contrast: UIAccessibilityContrast) -> SRGB {
        let traits = UITraitCollection { traits in
            traits.userInterfaceStyle = style
            traits.accessibilityContrast = contrast
        }
        let named = UIColor(named: colour.assetName(), in: Bundle(for: BundleToken.self), compatibleWith: traits)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        _ = (named ?? .black).resolvedColor(with: traits).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        func unit(_ value: CGFloat) -> Double { min(max(Double(value), 0), 1) }
        return SRGB(red: unit(red), green: unit(green), blue: unit(blue))
    }

    @Test func tintSliderUsesTheRequestedRangeAndDefault() {
        #expect(CoverWash.defaultStrength == 3)
        #expect(CoverWash.strengthRange == 0...5)
        #expect(CoverWash.strengthStep == 0.5)
    }

    @Test(arguments: [false, true])
    func pictureScrimKeepsBothMarksVisible(increased: Bool) {
        let contrast: UIAccessibilityContrast = increased ? .high : .normal
        let marks = [Palette.favourite, .favouriteOff].map { Self.base($0, style: .dark, contrast: contrast) }
        for grey in stride(from: 0.0, through: 1.0, by: 0.1) {
            let picture = PictureScrim.RGB(red: grey, green: grey, blue: grey)
            let opacity = PictureScrim.opacity(over: picture, increasedContrast: increased, marks: marks)
            let ground = picture.covered(by: PictureScrim.hall, opacity: opacity)
            let rgb = SRGB(red: ground.red, green: ground.green, blue: ground.blue)
            for mark in marks {
                #expect(SRGB.contrast(mark, rgb) >= (increased ? 4.5 : 3) - 0.005)
            }
        }
    }

    @Test func picturePlaceholderKeepsTheUnselectedMarkVisible() throws {
        for (_, style, contrast) in Self.rooms {
            let traits = UITraitCollection { traits in
                traits.userInterfaceStyle = style
                traits.accessibilityContrast = contrast
            }
            let asset = PersonHero.placeholder.assetName()
            let named = try #require(UIColor(named: asset, in: Bundle(for: BundleToken.self), compatibleWith: traits))
            var alpha: CGFloat = 0
            _ = named.resolvedColor(with: traits).getRed(nil, green: nil, blue: nil, alpha: &alpha)
            #expect(alpha == 1, "\(style.rawValue) \(contrast.rawValue)")
            let ground = Self.base(PersonHero.placeholder, style: style, contrast: contrast)
            let mark = Self.base(.favouriteOff, style: style, contrast: contrast)
            #expect(SRGB.contrast(mark, ground) >= (contrast == .high ? 4.5 : 3) - 0.005)
        }
    }

    @Test(arguments: [false, true])
    func aPortraitWithoutAFavouriteKeepsTheTextOnlyScrim(increased: Bool) {
        let picture = PictureScrim.RGB(red: 1, green: 1, blue: 1)
        let environment = EnvironmentValues()
        let marks = PersonHero.pictureMarks(showsFavourite: false, environment: environment)
        let visibleMarks = PersonHero.pictureMarks(showsFavourite: true, environment: environment)
        let textOnly = PictureScrim.opacity(over: picture, increasedContrast: increased)
        #expect(marks.isEmpty)
        #expect(visibleMarks.count == 2)
        #expect(PictureScrim.opacity(over: picture, increasedContrast: increased, marks: marks) == textOnly)
        #expect(PictureScrim.opacity(over: picture, increasedContrast: increased, marks: visibleMarks) > textOnly)
    }

    @Test func titleAttachmentUsesTheWashColour() {
        let original = FermataShape.image(em: 24, isSet: false, scale: 2, scheme: .light, contrast: .standard)
        let adjusted = FermataShape.image(
            em: 24, isSet: false, scale: 2, scheme: .light, contrast: .standard,
            colourOverride: SRGB(red: 1, green: 0, blue: 0).resolved)
        #expect(original.pngData() != adjusted.pngData())
    }

    // MARK: Cover hue

    /// A red figure on a grey ground gives red: grey pixels never vote.
    @Test func redFigureOnGreyGivesRed() throws {
        let pick = try #require(CoverHue.pick(from: Self.cover([(0xc0_20_20, 200)], rest: 0x80_80_80)))
        #expect(Self.distance(pick.hue, OKLCH(Self.hex(0xc0_20_20)).hue) < 2)
    }

    /// The heaviest family wins, never the average: blue sky and orange sun do not make a green or grey wash.
    @Test func heaviestFamilyWinsOverTheAverage() throws {
        let orange = Self.hex(0xe0_70_20)
        let blue = Self.hex(0x20_50_c0)
        let pick = try #require(CoverHue.pick(from: Self.cover([(0xe0_70_20, 600)], rest: 0x20_50_c0)))
        #expect(Self.distance(pick.hue, OKLCH(orange).hue) < 2)
        #expect(Self.distance(pick.hue, OKLCH(blue).hue) > 90)
    }

    /// Chroma weighs: a vivid patch outweighs a larger area of faint tint.
    @Test func vividPatchOutweighsFaintArea() throws {
        // A faint beige of chroma about 0.035 on 600 pixels against a vivid blue on 150 pixels.
        let pick = try #require(
            CoverHue.pick(from: Self.cover([(0xd8_cc_b4, 600), (0x18_40_e0, 150)], rest: 0x80_80_80)))
        #expect(Self.distance(pick.hue, OKLCH(Self.hex(0x18_40_e0)).hue) < 2)
    }

    /// A grey cover, or one with a few coloured specks, gives no hue.
    @Test func greyCoverGivesNoHue() {
        #expect(CoverHue.pick(from: Self.cover([(0x30_30_30, 400)], rest: 0xa0_a0_a0)) == nil)
        #expect(CoverHue.pick(from: Self.cover([(0xc0_20_20, 2)], rest: 0xa0_a0_a0)) == nil)
        #expect(CoverHue.pick(from: Self.cover([], rest: 0x7f_80_82)) == nil)
    }

    /// Deep shadow and white paper carry no hue, however coloured their numbers are.
    @Test func shadowAndHighlightCarryNoHue() {
        // Navy below OKLCH L 0.15 and a cream above L 0.96.
        let pixels = Self.cover([(0x00_00_1c, 512)], rest: 0xff_fa_ec)
        #expect(OKLCH(Self.hex(0x00_00_1c)).lightness < CoverHue.darkest)
        #expect(OKLCH(Self.hex(0xff_fa_ec)).lightness > CoverHue.lightest)
        #expect(CoverHue.pick(from: pixels) == nil)
    }

    /// The copy of a real picture: a drawn image gives the same pick as its pixels.
    @Test func drawnImageGivesItsHue() throws {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 64, height: 64))
        let image = renderer.image { context in
            UIColor.gray.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
            UIColor(red: 0.1, green: 0.5, blue: 0.3, alpha: 1).setFill()
            context.fill(CGRect(x: 0, y: 0, width: 64, height: 32))
        }
        let pixels = CoverHue.pixels(of: try #require(image.cgImage))
        #expect(pixels.count == CoverHue.side * CoverHue.side)
        let pick = try #require(CoverHue.pick(from: pixels))
        #expect(Self.distance(pick.hue, OKLCH(SRGB(red: 0.1, green: 0.5, blue: 0.3)).hue) < 3)
    }

    // MARK: Ground

    /// The ground takes the room's lightness and at most its chroma (ADR 0034).
    @Test(arguments: WashRoom.allCases)
    func groundKeepsTheRoomLimits(room: WashRoom) {
        for hue in stride(from: 0.0, to: 360, by: 15) {
            for chroma in [0.01, 0.2] {
                let ground = OKLCH(CoverWash.ground(CoverHue.Pick(hue: hue, chroma: chroma), in: room))
                #expect(abs(ground.lightness - room.lightness) < 0.005, "\(room) \(hue)")
                #expect(ground.chroma <= min(chroma, room.chromaLimit) + 0.002, "\(room) \(hue)")
                #expect(ground.chroma >= min(chroma, room.chromaLimit) - 0.003, "\(room) \(hue)")
                if ground.chroma > 0.008 { #expect(Self.distance(ground.hue, hue) < 3, "\(room) \(hue)") }
            }
        }
    }

    @Test(arguments: WashRoom.allCases)
    func strengthChoicesStayDistinctAfterGamutMapping(room: WashRoom) {
        for hue in stride(from: 0.0, to: 360, by: 20) {
            let pick = CoverHue.Pick(hue: hue, chroma: 0.15)
            let grounds = [1.0, 2.0, 3.0].map { CoverWash.ground(pick, in: room, strength: $0) }
            #expect(grounds[0] != grounds[1])
            #expect(grounds[1] != grounds[2])
        }
    }

    @Test func roomLimitsAreTheDecidedValues() {
        #expect(WashRoom.light.lightness == 0.935 && WashRoom.light.chromaLimit == 0.026)
        #expect(WashRoom.dark.lightness == 0.235 && WashRoom.dark.chromaLimit == 0.04)
        #expect(WashRoom.lightIncreasedContrast.lightness == 0.95)
        #expect(WashRoom.lightIncreasedContrast.chromaLimit == 0.018)
    }

    @Test func roomFollowsTheAppearance() {
        #expect(WashRoom(colorScheme: .light, contrast: .standard) == .light)
        #expect(WashRoom(colorScheme: .dark, contrast: .standard) == .dark)
        #expect(WashRoom(colorScheme: .light, contrast: .increased) == .lightIncreasedContrast)
        #expect(WashRoom(colorScheme: .dark, contrast: .increased) == .darkIncreasedContrast)
    }

    /// A grey cover takes the accent: the ground has the tint's hue at the room's full chroma.
    @Test func greyCoverTakesTheAccent() throws {
        for (room, style, contrast) in Self.rooms {
            let tint = Self.base(.tint, style: style, contrast: contrast)
            let wash = CoverWash.wash(nil, in: room) { Self.base($0, style: style, contrast: contrast) }
            let ground = OKLCH(wash.ground)
            #expect(Self.distance(ground.hue, OKLCH(tint).hue) < 3, "\(room)")
            #expect(abs(ground.chroma - room.chromaLimit) < 0.003, "\(room)")
        }
    }

    // MARK: Contrast on the wash

    /// Text, the tint and the favourite keep their targets on every wash and on the page ground that it fades into,
    /// in every room. The wash replaces no ground.
    @Test(arguments: Array(stride(from: 0.0, through: 5.0, by: 0.5)))
    func solvedColoursKeepTheirTargets(strength: Double) throws {
        for (room, style, contrast) in Self.rooms {
            let page = Self.base(.backgroundPage, style: style, contrast: contrast)
            for hue in stride(from: 0.0, to: 360, by: 20) {
                let pick = CoverHue.Pick(hue: hue, chroma: 0.15)
                let wash = CoverWash.wash(pick, in: room, strength: strength) {
                    Self.base($0, style: style, contrast: contrast)
                }
                #expect(Set(wash.colours.keys).isSubset(of: CoverWash.solvedColours))
                for colour in CoverWash.solvedColours {
                    let target = try #require(room.target(of: colour))
                    let solved = try #require(wash.colours[colour], "\(colour)")
                    for ground in [wash.ground, page] {
                        #expect(
                            SRGB.contrast(solved, ground) >= target - 0.01,
                            "\(colour) on hue \(hue) in \(room): \(SRGB.contrast(solved, ground))")
                    }
                }
            }
        }
    }

    /// A colour that already reaches its target stays as the asset catalog has it.
    @Test func colourThatReachesItsTargetStays() {
        let ink = Self.hex(0x20_18_14)
        let ground = Self.hex(0xf0_e8_d8)
        #expect(CoverWash.solved(ink, on: ground, target: 7) == ink)
    }

    /// A solved colour keeps its hue and moves away from the ground: darker by day, lighter at night.
    @Test func solvedColourMovesAwayFromTheGround() {
        let tint = OKLCH(lightness: 0.6, chroma: 0.1, hue: 6).srgb
        let light = OKLCH(lightness: 0.935, chroma: 0.02, hue: 6).srgb
        let dark = OKLCH(lightness: 0.235, chroma: 0.02, hue: 6).srgb
        let day = CoverWash.solved(tint, on: light, target: 7)
        let night = CoverWash.solved(tint, on: dark, target: 7)
        #expect(OKLCH(day).lightness < 0.6)
        #expect(OKLCH(night).lightness > 0.6)
        #expect(Self.distance(OKLCH(day).hue, 6) < 3)
        #expect(SRGB.contrast(day, light) >= 6.99)
        #expect(SRGB.contrast(night, dark) >= 6.99)
    }

    @Test func colourRoundTripsThroughOKLCH() {
        for value: UInt32 in [0xfa_f3_e5, 0x8a_1c_2e, 0x20_50_c0, 0x00_00_00, 0xff_ff_ff] {
            let colour = Self.hex(value)
            let back = OKLCH(colour).srgb
            #expect(abs(back.red - colour.red) < 0.002 && abs(back.green - colour.green) < 0.002)
            #expect(abs(back.blue - colour.blue) < 0.002)
        }
    }

    // MARK: Kept covers

    /// A plain cover file of one colour, as the album art store keeps it.
    static func file(_ colour: UIColor) -> Data {
        UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).pngData { context in
            colour.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        }
    }

    /// The wash takes its hue from the first kept file that decodes (ADR 0059). It skips a missing or broken file.
    @Test func keptCoverGivesTheHue() async throws {
        let files = ["missing": nil, "broken": Data([1, 2, 3]), "red": Self.file(.red), "blue": Self.file(.blue)]
        var asked: [String] = []
        let found = await CoverHue.kept(["missing", "broken", "red", "blue"]) { name in
            asked.append(name)
            return files[name] ?? nil
        }
        let pick = try #require(found?.pick)
        #expect(Self.distance(pick.hue, OKLCH(SRGB(red: 1, green: 0, blue: 0)).hue) < 5)
        #expect(asked == ["missing", "broken", "red"])
    }

    /// Without a kept file the wash waits: no pick, and no grey accent either.
    @Test func noKeptCoverGivesNoPick() async {
        let none = await CoverHue.kept([]) { _ in Self.file(.red) }
        let missing = await CoverHue.kept(["missing"]) { _ in nil }
        #expect(none == nil)
        #expect(missing == nil)
    }

    /// A grey kept cover gives a kept result without a hue, so the wash takes the accent.
    @Test func greyKeptCoverGivesNoHue() async throws {
        let found = await CoverHue.kept(["grey"]) { _ in Self.file(.gray) }
        #expect(found == CoverHue.Kept(pick: nil))
    }

    @Test func loaderReadsEmbeddedArtWithoutAServerCoverID() async throws {
        let fixture = CoverArtTests()
        let song = CoverArtTests.song("embedded", album: "a", disc: 1, cover: nil)
        let store = try fixture.makeStore()
        let covers = fixture.makeCovers(store, songs: [song])
        await covers.idle()
        covers.inspect(song, file: try fixture.flac(with: Self.file(.red)))
        await covers.idle()
        let load = CoverWashModifier.Load(song: song, covers: covers)
        let loaded = await CoverWashModifier.loaded(load, song: song, store: store)
        let pick = try #require(loaded?.pick)
        #expect(loaded?.slot == song.id)
        #expect(Self.distance(pick.hue, OKLCH(Self.hex(0xff_00_00)).hue) < 5)
        #expect(fixture.server.requests.isEmpty)
    }

    @Test func loaderReadsTheAlbumDiscFallbackWithoutAServerCoverID() async throws {
        let fixture = CoverArtTests()
        let source = CoverArtTests.song("source", album: "a", disc: 1, cover: "album")
        let song = CoverArtTests.song("fallback", album: "a", disc: 2, cover: nil)
        fixture.server.covers = ["album": Self.file(.blue)]
        let store = try fixture.makeStore()
        let covers = fixture.makeCovers(store, songs: [source, song])
        await covers.idle()
        fixture.server.reset()
        let loaded = await CoverWashModifier.loaded(.init(song: song, covers: covers), song: song, store: store)
        let pick = try #require(loaded?.pick)
        #expect(Self.distance(pick.hue, OKLCH(Self.hex(0x00_00_ff)).hue) < 5)
        #expect(fixture.server.requests.isEmpty)
    }

    @Test func loaderUsesTheAccentOnlyWithoutCoverSources() async throws {
        let fixture = CoverArtTests()
        let song = Song(id: "bare", title: "Bare")
        let store = try fixture.makeStore()
        let covers = fixture.makeCovers(store, songs: [song])
        await covers.idle()
        let loaded = await CoverWashModifier.loaded(.init(song: song, covers: covers), song: song, store: store)
        #expect(loaded == CoverWashModifier.Loaded(slot: song.id, pick: nil))
    }

    // MARK: The end of the player

    @Test func tailShowsTheNextItem() {
        let next = UUID()
        #expect(PlayerTail(isPlaying: true, upNext: [next, UUID()]) == .next(next))
    }

    @Test func tailSaysWhereTheQueueEnds() {
        #expect(PlayerTail(isPlaying: true, upNext: []) == .endsHere)
        #expect(PlayerTail(isPlaying: false, upNext: [UUID()]) == .nothing)
        #expect(PlayerTail(isPlaying: false, upNext: []) == .nothing)
    }
}
