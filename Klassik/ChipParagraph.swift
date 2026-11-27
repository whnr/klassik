import SwiftUI
import UIKit

/// The conditions of a search as one paragraph of chips that break across lines like text.
/// No system component does this, so TextKit lays out the text and the view draws each chip behind its words:
/// round at the real start and end of a chip, square where a line breaks it (specimen filters.css .cond).
/// Each chip is one accessibility button with its remove sign; a line break cannot split it.
struct ChipParagraph: UIViewRepresentable {
    let paragraph: ConditionParagraph
    let remove: (Int, Search.Term) -> Void
    let toggle: (Int) -> Void
    @Environment(\.dynamicTypeSize) private var typeSize

    func makeUIView(context: Context) -> ChipParagraphView {
        ChipParagraphView()
    }

    func updateUIView(_ view: ChipParagraphView, context: Context) {
        view.apply(paragraph, remove: remove, toggle: toggle, typeSize: typeSize)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView view: ChipParagraphView, context: Context) -> CGSize? {
        view.apply(paragraph, remove: remove, toggle: toggle, typeSize: typeSize)
        return view.size(fitting: proposal.width ?? UIScreen.main.bounds.width)
    }
}

final class ChipParagraphView: UIView {
    private let storage = NSTextStorage()
    private let layoutManager = NSLayoutManager()
    private let container = NSTextContainer()
    private var paragraph = ConditionParagraph(conditions: [], joining: nil)
    private var ranges: [NSRange] = []
    private var typeSize: DynamicTypeSize?
    private var remove: (Int, Search.Term) -> Void = { _, _ in }
    private var toggle: (Int) -> Void = { _ in }
    private var elements: [ChipElement] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        storage.addLayoutManager(layoutManager)
        layoutManager.addTextContainer(container)
        container.lineFragmentPadding = 0
        backgroundColor = .clear
        isOpaque = false
        contentMode = .redraw
        isAccessibilityElement = false
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped)))
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: ChipParagraphView, _) in
            view.typeSize = nil
            view.setNeedsLayout()
            view.setNeedsDisplay()
        }
    }

    required init?(coder: NSCoder) { nil }

    // MARK: Content

    func apply(
        _ paragraph: ConditionParagraph, remove: @escaping (Int, Search.Term) -> Void,
        toggle: @escaping (Int) -> Void, typeSize: DynamicTypeSize
    ) {
        self.remove = remove
        self.toggle = toggle
        if paragraph != self.paragraph || typeSize != self.typeSize {
            self.paragraph = paragraph
            self.typeSize = typeSize
            build()
            setNeedsLayout()
        }
        setNeedsDisplay()
    }

    func size(fitting width: CGFloat) -> CGSize {
        guard !paragraph.pieces.isEmpty else { return CGSize(width: width, height: 0) }
        place(width: width)
        return CGSize(width: width, height: ceil(layoutManager.usedRect(for: container).height))
    }

    // MARK: Metrics

    private var metrics: UIFontMetrics { UIFontMetrics(forTextStyle: Layout.chipLabel.textStyle.uiKit) }

    private func scaled(_ value: CGFloat) -> CGFloat {
        metrics.scaledValue(for: value, compatibleWith: traitCollection)
    }

    private func font(bold: Bool = false) -> UIFont {
        UIFont.systemFont(ofSize: scaled(Layout.chipLabel.size), weight: bold ? .semibold : .regular)
    }

    private func leadingPad(_ kind: ConditionParagraph.Kind) -> CGFloat {
        switch kind {
        case .chip: scaled(Layout.chipPaddingLeading)
        case .plus: scaled(Layout.orButtonPadding)
        case .and, .or: 0
        }
    }

    private func trailingPad(_ kind: ConditionParagraph.Kind) -> CGFloat {
        switch kind {
        case .chip: scaled(Layout.chipPaddingTrailing)
        case .plus: scaled(Layout.orButtonPadding)
        case .and, .or: 0
        }
    }

    private func verticalPad(_ kind: ConditionParagraph.Kind) -> CGFloat {
        switch kind {
        case .chip: scaled(Layout.chipPaddingVertical)
        case .plus: scaled(Layout.orButtonVertical)
        case .and, .or: 0
        }
    }

    private func isWord(_ kind: ConditionParagraph.Kind) -> Bool {
        switch kind {
        case .and, .or: true
        case .chip, .plus: false
        }
    }

    /// The text starts after the leading padding of its first chip, so the chip can grow into the margin.
    private var edgeLeading: CGFloat {
        paragraph.pieces.map { leadingPad($0.kind) }.max() ?? 0
    }

    private var edgeTrailing: CGFloat {
        paragraph.pieces.map { trailingPad($0.kind) }.max() ?? 0
    }

    // MARK: Text

    private func build() {
        let text = paragraph.layout()
        ranges = text.ranges
        let lineHeight = scaled(Layout.orButtonHeight)
        let regular = font()
        let style = NSMutableParagraphStyle()
        style.minimumLineHeight = lineHeight
        style.maximumLineHeight = lineHeight
        style.lineBreakMode = .byWordWrapping
        // The text sits in the middle of the tall line, which is the tap height of a chip.
        let shift = (lineHeight - regular.lineHeight) / 2
        let base: [NSAttributedString.Key: Any] = [
            .font: regular, .paragraphStyle: style, .baselineOffset: shift,
        ]
        let result = NSMutableAttributedString(string: text.text, attributes: base)
        let tie = (ConditionParagraph.tie as NSString).size(withAttributes: [.font: regular]).width
        for (index, piece) in paragraph.pieces.enumerated() {
            let range = ranges[index]
            switch piece.kind {
            case .chip:
                result.addAttribute(.foregroundColor, value: UIColor(Palette.textPrimary.color), range: range)
                let last = NSRange(location: range.upperBound - 1, length: 1)
                result.addAttribute(.foregroundColor, value: UIColor(Palette.textTertiary.color), range: last)
                let tieRange = NSRange(location: range.upperBound - 2, length: 1)
                result.addAttribute(.kern, value: max(0, scaled(Layout.chipRemoveGap) - tie), range: tieRange)
            case .plus(_, let isMarked):
                let color = isMarked ? Palette.onAccent : Palette.tint
                result.addAttribute(.foregroundColor, value: UIColor(color.color), range: range)
            case .and:
                result.addAttributes(
                    [.foregroundColor: UIColor(Palette.textSecondary.color), .font: font(bold: true)], range: range)
            case .or:
                result.addAttribute(.foregroundColor, value: UIColor(Palette.textSecondary.color), range: range)
            }
            if index > 0 {
                // The space before a piece keeps the padding of both neighbours and the margin of a word.
                let before = paragraph.pieces[index - 1].kind
                var gap = trailingPad(before) + leadingPad(piece.kind)
                if isWord(before) { gap += scaled(Layout.conditionTermGap) }
                if isWord(piece.kind) { gap += scaled(Layout.conditionTermGap) }
                result.addAttribute(.kern, value: gap, range: NSRange(location: range.location - 1, length: 1))
            }
        }
        storage.setAttributedString(result)
    }

    private func place(width: CGFloat) {
        container.size = CGSize(
            width: max(1, width - edgeLeading - edgeTrailing), height: .greatestFiniteMagnitude)
        layoutManager.ensureLayout(for: container)
    }

    // MARK: Geometry

    private struct Part {
        var fill: CGRect
        var tap: CGRect
        var roundsStart: Bool
        var roundsEnd: Bool
    }

    /// The part of a piece on each line it touches.
    private func parts(of index: Int) -> [Part] {
        guard ranges.indices.contains(index) else { return [] }
        let kind = paragraph.pieces[index].kind
        let range = ranges[index]
        let glyphs = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        let origin = CGPoint(x: edgeLeading, y: 0)
        let height = font().lineHeight + 2 * verticalPad(kind)
        let string = storage.string as NSString
        var result: [Part] = []
        layoutManager.enumerateLineFragments(forGlyphRange: glyphs) { fragment, _, _, lineGlyphs, _ in
            let line = self.layoutManager.characterRange(forGlyphRange: lineGlyphs, actualGlyphRange: nil)
            guard var segment = ChipSegment.split(range, lines: [line]).first else { return }
            // A space that a line leaves at its end is no part of the chip.
            var part = segment.range
            while part.length > 1, string.character(at: part.location) == 0x20 {
                part.location += 1
                part.length -= 1
            }
            while part.length > 1, string.character(at: part.upperBound - 1) == 0x20 { part.length -= 1 }
            segment.range = part
            let box = self.layoutManager.boundingRect(
                forGlyphRange: self.layoutManager.glyphRange(forCharacterRange: part, actualCharacterRange: nil),
                in: self.container)
            var minX = box.minX + origin.x
            var maxX = box.maxX + origin.x
            if segment.roundsStart { minX -= self.leadingPad(kind) }
            if segment.roundsEnd { maxX += self.trailingPad(kind) }
            let fill = CGRect(x: minX, y: fragment.midY - height / 2, width: maxX - minX, height: height)
            let tap = CGRect(x: minX, y: fragment.minY, width: maxX - minX, height: fragment.height)
            result.append(
                Part(fill: fill, tap: tap, roundsStart: segment.roundsStart, roundsEnd: segment.roundsEnd))
        }
        return result
    }

    // MARK: Drawing

    override func draw(_ rect: CGRect) {
        guard !paragraph.pieces.isEmpty else { return }
        for (index, piece) in paragraph.pieces.enumerated() {
            let color: Palette
            switch piece.kind {
            case .chip: color = .fillQuiet
            case .plus(_, let isMarked):
                guard isMarked else { continue }
                color = .accentFill
            case .and, .or: continue
            }
            UIColor(color.color).resolvedColor(with: traitCollection).setFill()
            for part in parts(of: index) {
                var corners: UIRectCorner = []
                if part.roundsStart { corners.formUnion([.topLeft, .bottomLeft]) }
                if part.roundsEnd { corners.formUnion([.topRight, .bottomRight]) }
                let radius = CGSize(width: part.fill.height / 2, height: part.fill.height / 2)
                UIBezierPath(roundedRect: part.fill, byRoundingCorners: corners, cornerRadii: radius).fill()
            }
        }
        layoutManager.drawGlyphs(
            forGlyphRange: layoutManager.glyphRange(for: container), at: CGPoint(x: edgeLeading, y: 0))
    }

    // MARK: Taps

    @objc private func tapped(_ recognizer: UITapGestureRecognizer) {
        let point = recognizer.location(in: self)
        for (index, piece) in paragraph.pieces.enumerated() where piece.isButton {
            guard parts(of: index).contains(where: { $0.tap.contains(point) }) else { continue }
            activate(piece)
            return
        }
    }

    fileprivate func activate(_ piece: ConditionParagraph.Piece) {
        switch piece.kind {
        case .chip(let condition, let term): remove(condition, term)
        case .plus(let condition, _): toggle(condition)
        case .and, .or: break
        }
    }

    // MARK: Accessibility

    override var accessibilityElements: [Any]? {
        get { elements }
        set {}
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        place(width: bounds.width)
        elements = paragraph.pieces.enumerated().map { index, piece in
            let element = ChipElement(accessibilityContainer: self)
            element.accessibilityLabel = piece.accessibilityLabel
            let found = parts(of: index)
            if let first = found.first {
                let frame = found.dropFirst().reduce(first.tap) { $0.union($1.tap) }
                element.accessibilityFrameInContainerSpace = frame
                if found.count > 1 {
                    // A chip on two lines is one shape: the path keeps VoiceOver's focus ring on both parts.
                    let path = UIBezierPath()
                    for part in found { path.append(UIBezierPath(rect: part.tap)) }
                    element.accessibilityPath = UIAccessibility.convertToScreenCoordinates(path, in: self)
                }
            }
            switch piece.kind {
            case .chip:
                element.accessibilityTraits = .button
                element.accessibilityIdentifier = "filter-chip"
            case .plus(_, let isMarked):
                element.accessibilityTraits = isMarked ? [.button, .selected] : .button
                element.accessibilityIdentifier = "filter-or"
            case .and, .or:
                element.accessibilityTraits = .staticText
            }
            element.onActivate = { [weak self] in self?.activate(piece) }
            return element
        }
    }
}

private final class ChipElement: UIAccessibilityElement {
    var onActivate: () -> Void = {}

    override func accessibilityActivate() -> Bool {
        onActivate()
        return true
    }
}

extension Font.TextStyle {
    /// The UIKit style whose metrics scale a size.
    fileprivate var uiKit: UIFont.TextStyle {
        switch self {
        case .largeTitle: .largeTitle
        case .title: .title1
        case .title2: .title2
        case .title3: .title3
        case .headline: .headline
        case .body: .body
        case .callout: .callout
        case .subheadline: .subheadline
        case .footnote: .footnote
        case .caption: .caption1
        case .caption2: .caption2
        default: .body
        }
    }
}
