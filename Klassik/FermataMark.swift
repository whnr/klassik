import SwiftUI
import UIKit

/// The engraved fermata of ADR 0033, on its 17 × 10.5 grid, as `design/marks/fermata.svg` draws it.
struct FermataShape: Shape {
    func path(in rect: CGRect) -> Path {
        let scale = rect.width / 17
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * scale, y: rect.minY + (y - 4) * scale)
        }
        var path = Path()
        // The arc: an outer half ellipse, 8.5 by 10.5, and an inner one, 7.8 by 7.9, closed at the feet.
        path.move(to: point(0, 14.5))
        for step in stride(from: 0.0, through: 1.0, by: 1.0 / 48) {
            let angle = Double.pi * (1 - step)
            path.addLine(to: point(8.5 + 8.5 * cos(angle), 14.5 - 10.5 * sin(angle)))
        }
        path.addLine(to: point(16.3, 14.5))
        for step in stride(from: 0.0, through: 1.0, by: 1.0 / 48) {
            let angle = Double.pi * step
            path.addLine(to: point(8.5 + 7.8 * cos(angle), 14.5 - 7.9 * sin(angle)))
        }
        path.closeSubpath()
        path.addEllipse(
            in: CGRect(
                x: rect.minX + 6.1 * scale, y: rect.minY + (11.9 - 2.4 - 4) * scale,
                width: 4.8 * scale, height: 4.8 * scale))
        return path
    }
}

extension FermataShape {
    /// The mark as a template image, for a place that takes an image and tints it, such as a swipe action. It has the
    /// size of the symbols on the other swipe actions.
    @MainActor static let icon: UIImage = {
        let em = TypeStyle.title3.size
        let size = CGSize(width: em * Layout.fermataWidth, height: em * Layout.fermataHeight)
        return UIGraphicsImageRenderer(size: size).image { _ in
            UIColor.black.setFill()
            UIBezierPath(cgPath: FermataShape().path(in: CGRect(origin: .zero, size: size)).cgPath).fill()
        }
        .withRenderingMode(.alwaysTemplate)
    }()
}

/// The favourite mark after a line of text. It is 0.64 em high and sits on the baseline (ADR 0032).
struct FermataMark: View {
    let isSet: Bool
    @ScaledMetric(relativeTo: .body) private var em = TypeStyle.body.size

    var body: some View {
        FermataShape()
            .fill(isSet ? Palette.favourite : Palette.favouriteOff)
            .frame(width: em * Layout.fermataWidth, height: em * Layout.fermataHeight)
            .alignmentGuide(.firstTextBaseline) { $0[.bottom] }
            .accessibilityLabel(isSet ? "Favourite" : "Not a favourite")
            .transaction { $0.animation = nil }
    }
}

/// Text lays out the mark with the final word, including when the title wraps.
struct FavouriteTitle: View {
    let title: String
    let isSet: Bool
    let action: @MainActor () -> Void
    var textIdentifier = "page-heading"
    var ink: Color = Palette.textPrimary.color
    var minimumHeight: CGFloat? = Measure.hitTarget
    @ScaledMetric(relativeTo: .title) private var em = TypeStyle.pageTitle.size
    @Environment(\.displayScale) private var scale
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        Button(action: action) {
            Text("\(title)\u{00A0}\(Image(uiImage: mark))")
                .typeStyle(.pageTitle)
                .foregroundStyle(ink)
                .accessibilityIdentifier(textIdentifier)
                // A new mark replaces the old one in the same frame, also under an animation of the page.
                .contentTransition(.identity)
                .transaction { $0.animation = nil }
        }
        // The mark changes state at once. A pressed button must not fade the title.
        .buttonStyle(.still)
        .frame(minHeight: minimumHeight)
        .accessibilityLabel(title)
        .accessibilityValue(isSet ? "Favourite" : "Not a favourite")
    }

    private var mark: UIImage {
        FermataShape.image(em: em, isSet: isSet, scale: scale, scheme: scheme, contrast: contrast)
    }
}

extension FermataShape {
    /// The mark as a text attachment, so a wrapped title keeps it with the final word.
    @MainActor static func image(
        em: CGFloat, isSet: Bool, scale: CGFloat, scheme: ColorScheme, contrast: ColorSchemeContrast
    ) -> UIImage {
        let size = CGSize(width: em * Layout.fermataWidth, height: em * Layout.fermataHeight)
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        let traits = UITraitCollection {
            $0.userInterfaceStyle = scheme == .dark ? .dark : .light
            $0.accessibilityContrast = contrast == .increased ? .high : .normal
        }
        let colour = (isSet ? Palette.favourite : Palette.favouriteOff).uiColor.resolvedColor(with: traits)
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            colour.setFill()
            UIBezierPath(cgPath: FermataShape().path(in: CGRect(origin: .zero, size: size)).cgPath).fill()
        }
    }
}

/// A title in a list row. A favourite gets the set fermata a quarter em after its last word (ADR 0033); any other
/// row shows no mark, so a list stays quiet until something in it is a favourite.
struct MarkedTitle: View {
    let title: String
    let isFavourite: Bool
    @ScaledMetric(relativeTo: .body) private var em = TypeStyle.body.size
    @Environment(\.displayScale) private var scale
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        if isFavourite {
            let mark = FermataShape.image(em: em, isSet: true, scale: scale, scheme: scheme, contrast: contrast)
            // A no-break space is about a quarter em wide and keeps the mark with the last word.
            Text("\(title)\u{00A0}\(Image(uiImage: mark))")
                .accessibilityLabel(title)
                .accessibilityValue("Favourite")
        } else {
            Text(title)
        }
    }
}
