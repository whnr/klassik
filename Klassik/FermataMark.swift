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

/// The favourite mark after a line of text. It is 0.64 em high and sits on the baseline (ADR 0032).
struct FermataMark: View {
    let isSet: Bool
    var isTitle = false
    @ScaledMetric(relativeTo: .body) private var em: CGFloat = 17

    var body: some View {
        let height = em * (isTitle ? 16.0 / 9 : 1) * 0.64
        FermataShape()
            .fill(isSet ? Palette.favourite : Palette.favouriteOff)
            .frame(width: height * 17 / 10.5, height: height)
            .alignmentGuide(.firstTextBaseline) { $0[.bottom] }
            .accessibilityLabel(isSet ? "Favourite" : "Not a favourite")
    }
}

/// Text lays out the mark with the final word, including when the title wraps.
struct FavouriteTitle: View {
    let title: String
    let isSet: Bool
    let action: @MainActor () -> Void
    var textIdentifier = "page-heading"
    @ScaledMetric(relativeTo: .title) private var em = TypeStyle.pageTitle.size
    @Environment(\.displayScale) private var scale
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        Button(action: action) {
            Text("\(title)\u{00A0}\(Image(uiImage: mark))")
                .typeStyle(.pageTitle)
                .foregroundStyle(Palette.textPrimary)
                .accessibilityIdentifier(textIdentifier)
        }
        .buttonStyle(.plain)
        .frame(minHeight: Measure.hitTarget)
        .accessibilityValue(isSet ? "Favourite" : "Not a favourite")
    }

    private var mark: UIImage {
        let size = CGSize(width: em * 0.64 * 17 / 10.5, height: em * 0.64)
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
