import SwiftUI
import UIKit

/// The engraved fermata, on its 17 × 10.5 grid, as `design/marks/fermata.svg` draws it.
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

/// The favourite mark after a line of text. It is 0.64 em high and sits on the baseline.
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

/// The specimen makes only the mark a button. Wrapped titles must keep that target beside the final word.
struct FavouriteTitle: View {
    let title: String
    let isSet: Bool
    let action: @MainActor () -> Void
    var textIdentifier = "page-heading"
    var ink: Color?
    var minimumHeight: CGFloat? = Measure.hitTarget
    @ScaledMetric(relativeTo: .title) private var em = TypeStyle.pageTitle.size
    @Environment(\.displayScale) private var scale
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.paletteOverrides) private var colours
    @Environment(\.isEnabled) private var isEnabled
    @State private var markFrame = MarkFrame()

    var body: some View {
        let markText = Text(Image(uiImage: mark)).customAttribute(FermataRun())
        Text("\(title)\u{00A0}\(markText)")
            .typeStyle(.pageTitle)
            .foregroundStyle(ink.map { AnyShapeStyle($0) } ?? AnyShapeStyle(Palette.textPrimary))
            // Favourite toggles must not animate, including under a page animation.
            .contentTransition(.identity)
            .transaction { $0.animation = nil }
            .textRenderer(MarkFrameRenderer(frame: markFrame))
            .onTapGesture(coordinateSpace: .local) { location in
                guard isEnabled, FermataShape.hitArea(around: markFrame.rect).contains(location) else { return }
                action()
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(title)
            .accessibilityValue(isSet ? "Favourite" : "Not a favourite")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction {
                if isEnabled { action() }
            }
            .modifier(MarkActivation(mark: markFrame.rect))
            .frame(minHeight: minimumHeight)
    }

    private var mark: UIImage {
        FermataShape.image(
            em: em, isSet: isSet, scale: scale, scheme: scheme, contrast: contrast,
            colourOverride: colours[isSet ? .favourite : .favouriteOff])
    }
}

extension FermataShape {
    /// Small marks need the minimum hit target on both axes.
    static func hitArea(around mark: CGRect) -> CGRect {
        guard !mark.isNull else { return .null }
        let dx = max(0, Measure.hitTarget - mark.width) / 2
        let dy = max(0, Measure.hitTarget - mark.height) / 2
        return mark.insetBy(dx: -dx, dy: -dy)
    }
}

/// The renderer needs to distinguish the mark from the title words.
private struct FermataRun: TextAttribute {}

/// Hit testing needs the visible mark frame in text coordinates.
@MainActor @Observable private final class MarkFrame {
    private(set) var rect = CGRect.null

    func update(_ rect: CGRect) {
        if rect != self.rect { self.rect = rect }
    }
}

/// Hit testing must follow the mark when the title wraps.
private struct MarkFrameRenderer: TextRenderer {
    let frame: MarkFrame

    func draw(layout: Text.Layout, in context: inout GraphicsContext) {
        var mark = CGRect.null
        for line in layout {
            for run in line where run[FermataRun.self] != nil {
                mark = mark.union(run.typographicBounds.rect)
            }
            context.draw(line)
        }
        let frame = frame
        let found = mark
        Task { @MainActor in frame.update(found) }
    }
}

/// VoiceOver and the walk need an activation point on the visible mark.
private struct MarkActivation: ViewModifier {
    let mark: CGRect

    func body(content: Content) -> some View {
        if mark.isNull {
            content
        } else {
            content.accessibilityActivationPoint(CGPoint(x: mark.midX, y: mark.midY))
        }
    }
}

extension FermataShape {
    /// The mark as a text attachment, so a wrapped title keeps it with the final word.
    @MainActor static func image(
        em: CGFloat, isSet: Bool, scale: CGFloat, scheme: ColorScheme, contrast: ColorSchemeContrast,
        colourOverride: Color.Resolved? = nil
    ) -> UIImage {
        let size = CGSize(width: em * Layout.fermataWidth, height: em * Layout.fermataHeight)
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        let traits = UITraitCollection {
            $0.userInterfaceStyle = scheme == .dark ? .dark : .light
            $0.accessibilityContrast = contrast == .increased ? .high : .normal
        }
        let colour =
            colourOverride.map { UIColor(Color($0)) }
            ?? (isSet ? Palette.favourite : Palette.favouriteOff).uiColor.resolvedColor(with: traits)
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            colour.setFill()
            UIBezierPath(cgPath: FermataShape().path(in: CGRect(origin: .zero, size: size)).cgPath).fill()
        }
    }
}

/// A title in a list row. A favourite gets the set fermata a quarter em after its last word; any other
/// row shows no mark, so a list stays quiet until something in it is a favourite.
struct MarkedTitle: View {
    let title: String
    let isFavourite: Bool
    /// The mark must match the title size.
    @ScaledMetric private var em: CGFloat
    @Environment(\.displayScale) private var scale
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast

    init(title: String, isFavourite: Bool, style: TypeStyle = .body) {
        self.title = title
        self.isFavourite = isFavourite
        _em = ScaledMetric(wrappedValue: style.size, relativeTo: style.textStyle)
    }

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
