import CoreGraphics
import Foundation

/// The pixels that a person picture needs on this screen, and the Commons files that give them.
/// A view needs the width at which it draws the whole picture: the shown width in pixels divided by the share of
/// the picture width that stays visible after the crop. The largest need of the views decides.
enum PortraitSize {
    /// Thumbnail widths that Wikimedia keeps in its cache. Another width misses the cache or gets a refusal.
    static let steps = [500, 960, 1280, 1920, 2560, 3840]
    /// Original formats that UIImage reads. Commons serves other formats only as thumbnails.
    static let readable: Set<String> = ["jpg", "jpeg", "png", "webp"]

    struct Screen: Equatable, Sendable {
        /// The hero frame, in points. Its width is the screen width.
        var hero: CGSize
        /// Pixels per point.
        var scale: CGFloat
    }

    struct Candidate: Equatable, Sendable {
        var url: URL
        /// True: only on a network that is not expensive and not in Low Data Mode.
        var wifiOnly: Bool
    }

    /// The hero covers its frame, and a face zooms the picture up to `PortraitFraming.maxZoom` further. The face
    /// is not known before the download, so the need takes the full zoom.
    static func heroWidth(aspect: CGFloat, screen: Screen) -> CGFloat {
        max(screen.hero.width, screen.hero.height * aspect) * PortraitFraming.maxZoom * screen.scale
    }

    /// The whole picture fits the screen, so it is never wider than the screen.
    static func wholeWidth(screen: Screen) -> CGFloat {
        screen.hero.width * screen.scale
    }

    /// The width in pixels that gives every view at least one picture pixel for each screen pixel.
    static func width(aspect: CGFloat, screen: Screen) -> CGFloat {
        max(heroWidth(aspect: aspect, screen: screen), wholeWidth(screen: screen))
    }

    /// The smallest step at or above the width. A wider need gets the largest step.
    static func step(_ width: CGFloat) -> Int {
        steps.first { CGFloat($0) >= width } ?? steps[steps.count - 1]
    }

    /// The files to try in order: the full need on Wi-Fi, a screen-width file on any network, then the stored
    /// file. A picture without a known size counts as square.
    static func candidates(_ portrait: PersonPortrait, screen: Screen) -> [Candidate] {
        let aspect = portrait.aspect ?? 1
        let wanted: [Candidate?] = [
            file(portrait, width: step(width(aspect: aspect, screen: screen))).map { .init(url: $0, wifiOnly: true) },
            file(portrait, width: step(wholeWidth(screen: screen))).map { .init(url: $0, wifiOnly: false) },
            .init(url: portrait.url, wifiOnly: false),
        ]
        var result: [Candidate] = []
        for candidate in wanted.compactMap(\.self) {
            if let index = result.firstIndex(where: { $0.url == candidate.url }) {
                result[index].wifiOnly = result[index].wifiOnly && candidate.wifiOnly
            } else {
                result.append(candidate)
            }
        }
        return result
    }

    /// The original when the step is not narrower than it, else the thumbnail at the step. Commons refuses a
    /// thumbnail wider than the original. Nil: no such file, and the stored file serves.
    static func file(_ portrait: PersonPortrait, width: Int) -> URL? {
        if let original = portrait.width, width >= original {
            guard let url = portrait.original, readable.contains(url.pathExtension.lowercased()) else { return nil }
            return url
        }
        return thumbnail(portrait.url, width: width)
    }

    /// The same Commons thumbnail at another width. A thumbnail name is `[prefix-]<width>px-<name>`, under a
    /// `/thumb/` path; the prefix holds a page or a quality, as in `lossy-page1-`.
    static func thumbnail(_ url: URL, width: Int) -> URL? {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        let path = components.percentEncodedPath
        guard path.contains("/thumb/"), let slash = path.lastIndex(of: "/") else { return nil }
        let name = path[path.index(after: slash)...]
        guard let px = name.range(of: "px-") else { return nil }
        let head = name[..<px.lowerBound]
        let digits = head.reversed().prefix { $0.isASCII && $0.isNumber }.count
        let prefix = head.dropLast(digits)
        guard digits > 0, prefix.isEmpty || prefix.hasSuffix("-") else { return nil }
        components.percentEncodedPath = path[...slash] + prefix + "\(width)" + name[px.lowerBound...]
        return components.url
    }
}
