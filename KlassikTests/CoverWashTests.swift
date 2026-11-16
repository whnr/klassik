import Foundation
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
            let colours = CoverWash.palette(nil, in: room) { Self.base($0, style: style, contrast: contrast) }
            let ground = OKLCH(try #require(colours[.backgroundPage]))
            #expect(Self.distance(ground.hue, OKLCH(tint).hue) < 3, "\(room)")
            #expect(abs(ground.chroma - room.chromaLimit) < 0.003, "\(room)")
        }
    }

    // MARK: Contrast on the wash

    /// Text, the tint and the favourite keep their targets on every wash, in every room.
    @Test func solvedColoursKeepTheirTargets() throws {
        for (room, style, contrast) in Self.rooms {
            for hue in stride(from: 0.0, to: 360, by: 20) {
                let pick = CoverHue.Pick(hue: hue, chroma: 0.15)
                let colours = CoverWash.palette(pick, in: room) { Self.base($0, style: style, contrast: contrast) }
                let ground = try #require(colours[.backgroundPage])
                for grounds in CoverWash.grounds { #expect(colours[grounds] == ground) }
                for colour in CoverWash.solvedColours {
                    let target = try #require(room.target(of: colour))
                    let solved = try #require(colours[colour], "\(colour)")
                    #expect(
                        SRGB.contrast(solved, ground) >= target - 0.01,
                        "\(colour) on hue \(hue) in \(room): \(SRGB.contrast(solved, ground))")
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

    // MARK: The end of the player

    @Test func tailShowsTheNextItem() {
        let next = UUID()
        #expect(PlayerTail(isPlaying: true, upNext: [next, UUID()], ended: false) == .next(next))
    }

    @Test func tailSaysWhereTheQueueEnds() {
        #expect(PlayerTail(isPlaying: true, upNext: [], ended: false) == .endsHere)
        #expect(PlayerTail(isPlaying: false, upNext: [], ended: true) == .ended)
        #expect(PlayerTail(isPlaying: false, upNext: [UUID()], ended: false) == .nothing)
        #expect(PlayerTail(isPlaying: false, upNext: [], ended: false) == .nothing)
    }
}
