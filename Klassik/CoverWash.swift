import CoreGraphics
import Observation
import SwiftUI
import UIKit

/// A colour in sRGB, each channel from 0 to 1.
struct SRGB: Equatable, Sendable {
    var red: Double
    var green: Double
    var blue: Double

    /// WCAG relative luminance.
    var luminance: Double {
        0.2126 * Self.linear(red) + 0.7152 * Self.linear(green) + 0.0722 * Self.linear(blue)
    }

    static func linear(_ value: Double) -> Double {
        value <= 0.040_45 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
    }

    static func encoded(_ value: Double) -> Double {
        value <= 0.003_130_8 ? value * 12.92 : 1.055 * pow(value, 1 / 2.4) - 0.055
    }

    /// The WCAG contrast ratio between two colours.
    static func contrast(_ first: SRGB, _ second: SRGB) -> Double {
        let (low, high) = (min(first.luminance, second.luminance), max(first.luminance, second.luminance))
        return (high + 0.05) / (low + 0.05)
    }
}

extension SRGB {
    init(_ resolved: Color.Resolved) {
        func unit(_ value: Float) -> Double { min(max(Double(value), 0), 1) }
        self.init(red: unit(resolved.red), green: unit(resolved.green), blue: unit(resolved.blue))
    }

    var resolved: Color.Resolved {
        Color.Resolved(colorSpace: .sRGB, red: Float(red), green: Float(green), blue: Float(blue))
    }
}

/// A colour in OKLCH: lightness 0 to 1, chroma, and hue in degrees.
struct OKLCH: Equatable, Sendable {
    var lightness: Double
    var chroma: Double
    var hue: Double

    /// The OKLab coordinates of a colour.
    static func lab(_ colour: SRGB) -> (lightness: Double, a: Double, b: Double) {
        let red = SRGB.linear(colour.red)
        let green = SRGB.linear(colour.green)
        let blue = SRGB.linear(colour.blue)
        let l = cbrt(0.412_221_470_8 * red + 0.536_332_536_3 * green + 0.051_445_992_9 * blue)
        let m = cbrt(0.211_903_498_2 * red + 0.680_699_545_1 * green + 0.107_396_956_6 * blue)
        let s = cbrt(0.088_302_461_9 * red + 0.281_718_837_6 * green + 0.629_978_700_5 * blue)
        return (
            0.210_454_255_3 * l + 0.793_617_785 * m - 0.004_072_046_8 * s,
            1.977_998_495_1 * l - 2.428_592_205 * m + 0.450_593_709_9 * s,
            0.025_904_037_1 * l + 0.782_771_766_2 * m - 0.808_675_766 * s
        )
    }

    /// The linear channels, which fall outside 0 to 1 when the colour is outside sRGB.
    private var linear: (red: Double, green: Double, blue: Double) {
        let a = chroma * cos(hue * .pi / 180)
        let b = chroma * sin(hue * .pi / 180)
        let l = pow(lightness + 0.396_337_777_4 * a + 0.215_803_757_3 * b, 3)
        let m = pow(lightness - 0.105_561_345_8 * a - 0.063_854_172_8 * b, 3)
        let s = pow(lightness - 0.089_484_177_5 * a - 1.291_485_548 * b, 3)
        return (
            4.076_741_662_1 * l - 3.307_711_591_3 * m + 0.230_969_929_2 * s,
            -1.268_438_004_6 * l + 2.609_757_401_1 * m - 0.341_319_396_5 * s,
            -0.004_196_086_3 * l - 0.703_418_614_7 * m + 1.707_614_701 * s
        )
    }

    private var isInGamut: Bool {
        let channels = linear
        return [channels.red, channels.green, channels.blue].allSatisfy { $0 >= -0.000_1 && $0 <= 1.000_1 }
    }

    /// The colour in sRGB. A colour outside sRGB loses chroma, never lightness or hue.
    var srgb: SRGB {
        var inside = self
        if !isInGamut {
            var low = 0.0
            var high = chroma
            for _ in 0..<30 {
                let middle = (low + high) / 2
                inside.chroma = middle
                if inside.isInGamut { low = middle } else { high = middle }
            }
            inside.chroma = low
        }
        let channels = inside.linear
        func clamp(_ value: Double) -> Double { SRGB.encoded(min(max(value, 0), 1)) }
        return SRGB(red: clamp(channels.red), green: clamp(channels.green), blue: clamp(channels.blue))
    }
}

extension OKLCH {
    init(_ colour: SRGB) {
        let lab = Self.lab(colour)
        var hue = atan2(lab.b, lab.a) * 180 / .pi
        if hue < 0 { hue += 360 }
        self.init(lightness: lab.lightness, chroma: (lab.a * lab.a + lab.b * lab.b).squareRoot(), hue: hue)
    }
}

/// The hue that a cover gives to the player.
enum CoverHue {
    struct Pick: Equatable, Sendable {
        /// The hue of the family, in degrees.
        var hue: Double
        /// The chroma of the chroma-weighted mean colour of the family.
        var chroma: Double
    }

    /// The side of the small copy of the cover, in pixels.
    static let side = 32
    /// Pixels below this chroma count as grey; pixels outside these lightness limits are shadow or highlight.
    static let chromaFloor = 0.03
    static let darkest = 0.15
    static let lightest = 0.96
    /// The 24 hue families, 15 degrees each.
    static let families = 24
    /// The least weight of the heaviest family, as summed chroma over the 32 by 32 copy. A lighter cover is grey.
    static let leastWeight = 0.6

    /// The heaviest chromatic hue family of a small copy of the cover, never the average: the average of a painting
    /// is mud. Each pixel weighs its chroma. Nil for a grey cover.
    static func pick(from pixels: [SRGB]) -> Pick? {
        guard !pixels.isEmpty else { return nil }
        let width = 360 / Double(families)
        var weight = [Double](repeating: 0, count: families)
        var sumA = [Double](repeating: 0, count: families)
        var sumB = [Double](repeating: 0, count: families)
        for pixel in pixels {
            let lab = OKLCH.lab(pixel)
            let chroma = (lab.a * lab.a + lab.b * lab.b).squareRoot()
            guard chroma >= chromaFloor, lab.lightness >= darkest, lab.lightness <= lightest else { continue }
            var hue = atan2(lab.b, lab.a) * 180 / .pi
            if hue < 0 { hue += 360 }
            let family = min(Int(hue / width), families - 1)
            weight[family] += chroma
            sumA[family] += lab.a * chroma
            sumB[family] += lab.b * chroma
        }
        guard let best = weight.indices.max(by: { weight[$0] < weight[$1] }) else { return nil }
        // The floor holds for any size of copy: it scales with the pixel count.
        let floor = leastWeight * Double(pixels.count) / Double(side * side)
        guard weight[best] >= floor, weight[best] > 0 else { return nil }
        let a = sumA[best] / weight[best]
        let b = sumB[best] / weight[best]
        var hue = atan2(b, a) * 180 / .pi
        if hue < 0 { hue += 360 }
        return Pick(hue: hue, chroma: (a * a + b * b).squareRoot())
    }

    /// The hue of a kept cover file. Its `pick` is nil for a grey cover.
    struct Kept: Equatable, Sendable {
        var pick: Pick?
    }

    /// The hue of the first of `files` that `read` finds and that decodes. Nil when none does.
    /// The wash reads only kept covers (ADR 0059), never the network.
    @MainActor static func kept(_ files: [String], read: (String) async -> Data?) async -> Kept? {
        for file in files {
            guard let data = await read(file), let image = await CoverArt.scaled(data, to: side)?.cgImage else {
                continue
            }
            return Kept(pick: pick(from: pixels(of: image)))
        }
        return nil
    }

    /// The pixels of the small copy of a picture, in sRGB.
    static func pixels(of image: CGImage) -> [SRGB] {
        var bytes = [UInt8](repeating: 0, count: side * side * 4)
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let space = CGColorSpace(name: CGColorSpace.sRGB),
                let context = CGContext(
                    data: buffer.baseAddress, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                    space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard drawn else { return [] }
        return (0..<side * side).map { index in
            SRGB(
                red: Double(bytes[index * 4]) / 255, green: Double(bytes[index * 4 + 1]) / 255,
                blue: Double(bytes[index * 4 + 2]) / 255)
        }
    }
}

/// The room that sets the limits of the player ground and the targets on it.
enum WashRoom: CaseIterable, Sendable {
    case light
    case dark
    case lightIncreasedContrast
    case darkIncreasedContrast

    init(colorScheme: ColorScheme, contrast: ColorSchemeContrast) {
        let high = contrast == .increased
        switch colorScheme {
        case .dark: self = high ? .darkIncreasedContrast : .dark
        default: self = high ? .lightIncreasedContrast : .light
        }
    }

    var isDark: Bool { self == .dark || self == .darkIncreasedContrast }

    var isIncreasedContrast: Bool { self == .lightIncreasedContrast || self == .darkIncreasedContrast }

    /// The lightness of the ground. Increase Contrast in the dark keeps the dark ground: no other is set.
    var lightness: Double {
        switch self {
        case .light: 0.935
        case .lightIncreasedContrast: 0.95
        case .dark, .darkIncreasedContrast: 0.235
        }
    }

    /// The most chroma that the ground may take.
    var chromaLimit: Double {
        switch self {
        case .light: 0.026
        case .lightIncreasedContrast: 0.018
        case .dark, .darkIncreasedContrast: 0.04
        }
    }

    /// The contrast that each solved colour keeps on the ground: the page targets of `design/scripts/palette.py`.
    func target(of colour: Palette) -> Double? {
        switch (colour, self) {
        case (.textPrimary, .light), (.textPrimary, .lightIncreasedContrast): 7
        case (.textPrimary, .dark): 11.5
        case (.textPrimary, .darkIncreasedContrast): 15
        case (.textSecondary, .light): 5.2
        case (.textSecondary, .dark): 6
        case (.textSecondary, .lightIncreasedContrast): 7.5
        case (.textSecondary, .darkIncreasedContrast): 8
        case (.tint, .light): 7
        case (.tint, .dark): 6.5
        case (.tint, _): 9
        case (.favourite, .light): 4.5
        case (.favourite, .lightIncreasedContrast): 7
        case (.favourite, .dark): 6.5
        case (.favourite, .darkIncreasedContrast): 9
        case (.favouriteOff, _): isIncreasedContrast ? 4.5 : 3
        default: nil
        }
    }
}

/// The wash of the player while it plays, and the colours that stay readable on it.
enum CoverWash {
    /// Temporary installed-app comparison until Flo selects the cover tint strength.
    static let strengthKey = "player.tintStrength"
    static let defaultStrength = 3.0
    static let strengthRange = 0.0...5.0
    static let strengthStep = 0.5

    /// The colours that are solved again on the wash.
    static let solvedColours: [Palette] = [.textPrimary, .textSecondary, .tint, .favourite, .favouriteOff]

    /// The colour of the wash and the colours that it replaces.
    struct Wash: Equatable, Sendable {
        var ground: SRGB
        var colours: [Palette: SRGB]
    }

    /// Stronger chroma needs lightness headroom, so gamut mapping does not collapse the comparison choices.
    static func ground(_ pick: CoverHue.Pick, in room: WashRoom, strength: Double = 1) -> SRGB {
        OKLCH(
            lightness: room.lightness - (strength - 1) * (room.isDark ? 0.01 : 0.03),
            chroma: min(pick.chroma, room.chromaLimit) * strength, hue: pick.hue
        ).srgb
    }

    /// The hue that a grey cover takes: the accent, measured from the tint.
    static func accent(_ tint: SRGB) -> CoverHue.Pick {
        let colour = OKLCH(tint)
        return CoverHue.Pick(hue: colour.hue, chroma: colour.chroma)
    }

    /// The colour itself when it reaches the target on the ground. Else the same hue and chroma, moved away from
    /// the ground in lightness until it does: darker on a light ground, lighter on a dark one.
    static func solved(_ colour: SRGB, on ground: SRGB, target: Double) -> SRGB {
        guard SRGB.contrast(colour, ground) < target else { return colour }
        let start = OKLCH(colour)
        let darker = ground.luminance >= 0.18
        var near = start.lightness
        var far = darker ? 0.0 : 1.0
        for _ in 0..<40 {
            let middle = (near + far) / 2
            var trial = start
            trial.lightness = middle
            if SRGB.contrast(trial.srgb, ground) >= target { far = middle } else { near = middle }
        }
        var result = start
        result.lightness = far
        return result.srgb
    }

    /// The wash and the colours that it replaces. `base` gives a colour of the asset catalog in the room.
    /// The wash fades into the page ground, so each colour reaches its target on both ends of the fade. Every
    /// colour between the two ends has a luminance between theirs, so the colour reaches its target there too.
    static func wash(_ pick: CoverHue.Pick?, in room: WashRoom, strength: Double = 1, base: (Palette) -> SRGB) -> Wash {
        let ground = ground(pick ?? accent(base(.tint)), in: room, strength: strength)
        let page = base(.backgroundPage)
        var colours: [Palette: SRGB] = [:]
        for colour in solvedColours {
            guard let target = room.target(of: colour) else { continue }
            let onWash = solved(base(colour), on: ground, target: target)
            colours[colour] = solved(onWash, on: page, target: target)
        }
        return Wash(ground: ground, colours: colours)
    }
}

/// How far the player list has scrolled, so that the wash moves with the content.
/// The list of the old item stays alive while it leaves upwards, and its scroll can still change. Only the list of
/// the item that the player shows moves the wash, so the next item opens with its wash at the top.
@MainActor @Observable
final class WashScroll {
    private(set) var item: UUID?
    private(set) var offset: CGFloat = 0

    /// The player shows `item`. Its list opens at its top and reports scroll only after movement.
    func open(_ item: UUID) {
        guard item != self.item else { return }
        self.item = item
        offset = 0
    }

    /// The list of `owner` scrolled to `offset`.
    func report(_ offset: CGFloat, from owner: UUID?) {
        guard owner != nil, owner == item else { return }
        self.offset = offset
    }
}

/// The wash that the player shows while its item plays.
struct PlayerWash {
    var colour: Color.Resolved
    var scroll: WashScroll
}

extension EnvironmentValues {
    /// Set under the player while its item plays. A page list then shows the wash through a clear ground.
    @Entry var playerWash: PlayerWash?
    /// The queue item whose page holds this list in the player. Only that list moves the wash.
    @Entry var washOwner: UUID?
}

/// The ground of the player. While its item plays, the wash lies at the top of the content and fades into the page
/// ground over `Layout.washHeight` (specimen player.html `.wash`). Rows and grouped grounds keep their colours.
struct PlayerGround: View {
    @Environment(\.playerWash) private var wash

    var body: some View {
        ZStack(alignment: .top) {
            // The ground below both branches keeps the player opaque while one branch fades into the other.
            Rectangle().fill(Palette.backgroundGrouped)
            if let wash {
                Rectangle().fill(Palette.backgroundPage)
                LinearGradient(
                    stops: [
                        .init(color: Color(wash.colour), location: 0),
                        .init(color: Color(wash.colour), location: Layout.washSolid),
                        .init(color: Color(wash.colour).opacity(0), location: 1),
                    ], startPoint: .top, endPoint: .bottom
                )
                .frame(height: Layout.washHeight)
                .offset(y: -max(wash.scroll.offset, 0))
                .transition(.opacity)
            } else {
                Rectangle().fill(Palette.backgroundGrouped)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .clipped()
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

/// Washes the player in its cover's hue while its item plays.
struct CoverWashModifier: ViewModifier {
    @Environment(AppModel.self) private var model
    @Environment(\.self) private var environment
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The item that the player shows. Each item has its own list, which opens at its top.
    let item: UUID
    /// The song whose cover gives the hue, or nil when the item has no song.
    let song: Song?
    let isPlaying: Bool
    @AppStorage(CoverWash.strengthKey) private var strength = CoverWash.defaultStrength
    @State private var loaded: Loaded?
    @State private var scroll = WashScroll()

    struct Loaded: Equatable {
        var item: UUID?
        var slot: String?
        var pick: CoverHue.Pick?
    }

    /// The pick that the wash shows. A new movement of the same item keeps the last pick until its own cover is
    /// read, so a jump across movements never drops the wash for a frame. Another item never shows it.
    static func shown(_ loaded: Loaded?, item: UUID, slot: String?) -> Loaded? {
        guard let loaded, loaded.slot == slot || loaded.item == item else { return nil }
        return loaded
    }

    /// The kept files of the cover and their arrival count. A new file starts the pick again.
    struct Load: Equatable {
        var slot: String?
        var candidates: [String]
        var arrival: Int

        @MainActor init(song: Song?, covers: AlbumCovers) {
            slot = song?.id
            candidates = song.map { covers.candidates(for: $0) } ?? []
            arrival = song.map { covers.arrival(for: $0) } ?? 0
        }
    }

    func body(content: Content) -> some View {
        let room = WashRoom(colorScheme: colorScheme, contrast: contrast)
        let covers = model.albumCovers
        let load = Load(song: song, covers: covers)
        let wash: CoverWash.Wash? =
            if isPlaying, let loaded = Self.shown(loaded, item: item, slot: load.slot) {
                CoverWash.wash(loaded.pick, in: room, strength: strength) {
                    SRGB($0.color.resolve(in: environment))
                }
            } else {
                nil
            }
        let colours = wash?.colours.mapValues(\.resolved) ?? [:]
        content
            .tint(colours[.tint].map { Color($0) } ?? Palette.tint.color)
            .environment(\.paletteOverrides, colours)
            .environment(\.playerWash, wash.map { PlayerWash(colour: $0.ground.resolved, scroll: scroll) })
            .animation(Motion.inPlace.animation(reduceMotion: reduceMotion), value: wash == nil)
            .onChange(of: item, initial: true) { scroll.open(item) }
            .task(id: load) {
                if var found = await Self.loaded(load, song: song, store: model.albumArt) {
                    found.item = item
                    if !Task.isCancelled { loaded = found }
                } else if let song {
                    // The kept file arrives later and starts this task again. The wash waits for it.
                    covers.request(song, playback: true)
                }
            }
    }

    /// Track and disc links can supply art without a server cover ID (ADR 0059). A song with no cover ID and no
    /// readable kept file takes the accent, as the hero shows no art for it.
    @MainActor static func loaded(_ load: Load, song: Song?, store: ImageStore) async -> Loaded? {
        if let kept = await CoverHue.kept(load.candidates, read: { await store.data(named: $0) }) {
            return Loaded(slot: load.slot, pick: kept.pick)
        }
        guard song?.coverArt == nil else { return nil }
        return Loaded(slot: load.slot, pick: nil)
    }
}

extension View {
    /// Washes the view in its cover's hue while its item plays.
    func coverWash(item: UUID, song: Song?, isPlaying: Bool) -> some View {
        modifier(CoverWashModifier(item: item, song: song, isPlaying: isPlaying))
    }
}
