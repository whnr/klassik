import CoreGraphics
import Foundation

/// Where a picture sits in the frame of a person page: wide as the screen, around the face (ADR 0017).
enum PortraitFraming {
    /// How far a small face may zoom beyond the picture that just fills the frame.
    static let maxZoom: CGFloat = 2
    /// The share of the frame height that a face aims at.
    static let faceHeight: CGFloat = 0.3
    /// Where the face centre sits in the frame, from the top. The name sits in the lower part.
    static let faceLine: CGFloat = 0.4

    /// The rectangle that the whole picture takes in the frame. It always covers the frame.
    /// `face` is a rectangle in the unit square of the picture, from its top left.
    static func rect(image: CGSize, frame: CGSize, face: CGRect?) -> CGRect {
        guard image.width > 0, image.height > 0, frame.width > 0, frame.height > 0 else {
            return CGRect(origin: .zero, size: frame)
        }
        let fill = max(frame.width / image.width, frame.height / image.height)
        var scale = fill
        if let face, face.height > 0 {
            let wanted = frame.height * faceHeight / (face.height * image.height)
            scale = min(max(fill, wanted), fill * maxZoom)
        }
        let size = CGSize(width: image.width * scale, height: image.height * scale)
        let centre = face.map { CGPoint(x: $0.midX * size.width, y: $0.midY * size.height) }
            ?? CGPoint(x: size.width / 2, y: size.height * 0.35)
        let x = min(0, max(frame.width - size.width, frame.width / 2 - centre.x))
        let y = min(0, max(frame.height - size.height, frame.height * faceLine - centre.y))
        return CGRect(origin: CGPoint(x: x, y: y), size: size)
    }

    /// The area of the picture that the frame shows, in the unit square of the picture.
    static func visible(of rect: CGRect, in frame: CGSize) -> CGRect {
        CGRect(
            x: -rect.minX / rect.width, y: -rect.minY / rect.height, width: frame.width / rect.width,
            height: frame.height / rect.height)
    }
}

/// How strong the scrim under the name and the facts must be (ADR 0034). Text over a picture never fails.
enum PictureScrim {
    /// The paper colour of the text, sRGB.
    static let text = RGB(red: 0.980, green: 0.953, blue: 0.898)
    /// The colour of the hall that the scrim paints, sRGB.
    static let hall = RGB(red: 0.105, green: 0.082, blue: 0.070)
    static let minimum = 0.25
    static let maximum = 0.9

    struct RGB: Equatable, Sendable {
        var red: Double
        var green: Double
        var blue: Double

        /// WCAG relative luminance.
        var luminance: Double {
            func linear(_ value: Double) -> Double {
                value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
        }

        /// The colour after a layer of `other` with this opacity over it, mixed as the screen mixes it.
        func covered(by other: RGB, opacity: Double) -> RGB {
            RGB(
                red: red * (1 - opacity) + other.red * opacity, green: green * (1 - opacity) + other.green * opacity,
                blue: blue * (1 - opacity) + other.blue * opacity)
        }
    }

    /// The contrast ratio of the text over a ground.
    static func contrast(over ground: RGB) -> Double {
        (text.luminance + 0.05) / (ground.luminance + 0.05)
    }

    /// The targets: 4.5 for the facts and 3 for the name; 7 and 4.5 with Increase Contrast.
    static func targets(increasedContrast: Bool) -> (facts: Double, name: Double) {
        increasedContrast ? (7, 4.5) : (4.5, 3)
    }

    /// The weakest scrim opacity that lifts both lines to their target over the picture, between the minimum
    /// and the maximum. A picture that cannot reach the targets gets the maximum.
    /// `picture` is the brightest part under the text, after the blur.
    static func opacity(over picture: RGB, increasedContrast: Bool) -> Double {
        let target = targets(increasedContrast: increasedContrast)
        let needed = max(target.facts, target.name)
        func reaches(_ opacity: Double) -> Bool {
            contrast(over: picture.covered(by: hall, opacity: opacity)) >= needed
        }
        guard !reaches(minimum) else { return minimum }
        guard reaches(maximum) else { return maximum }
        var low = minimum
        var high = maximum
        for _ in 0..<24 {
            let middle = (low + high) / 2
            if reaches(middle) { high = middle } else { low = middle }
        }
        return high
    }
}
