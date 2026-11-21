import SwiftUI

/// Names, one line per role, behind a small-cap label (ADR 0031). A row aligns them on the leading edge. The page
/// header centres them.
struct RoleLines: View {
    let lines: [Roles.Line]
    let alignment: HorizontalAlignment
    let style: TypeStyle
    /// The page of a name, if it has one. Such a name is a link in the tint (specimen `.roles a`).
    let link: (Roles.Line, String) -> Page?
    @ScaledMetric(space: .inGroup) private var gap: CGFloat
    @ScaledMetric private var size: CGFloat
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.paletteOverrides) private var overrides
    @Environment(\.colorSchemeContrast) private var contrast

    /// `style` sets the size of label and names. The explicit fonts here ignore a `typeStyle` of the caller.
    init(
        lines: [Roles.Line], alignment: HorizontalAlignment = .leading, style: TypeStyle = .body,
        link: @escaping (Roles.Line, String) -> Page? = { _, _ in nil }
    ) {
        self.lines = lines
        self.alignment = alignment
        self.style = style
        self.link = link
        _size = ScaledMetric(wrappedValue: style.size, relativeTo: style.textStyle)
    }

    var body: some View {
        let rows = lines.flatMap { line in line.rows().map { (line, $0) } }
        if !rows.isEmpty {
            VStack(alignment: alignment, spacing: gap) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, entry in
                    self.line(entry.1, of: entry.0)
                }
            }
            // A text link draws in the tint of its view.
            .tint(tint)
            // Links keep their own elements, so VoiceOver and the walk can follow a name.
            .accessibilityElement(children: hasLinks ? .contain : .combine)
        }
    }

    private var tint: Color { overrides[.tint].map { Color($0) } ?? Palette.tint.color }

    private var hasLinks: Bool { lines.contains { line in line.names.contains { link(line, $0) != nil } } }

    /// At accessibility sizes the label stands above its names.
    @ViewBuilder private func line(_ row: Roles.Line.Row, of line: Roles.Line) -> some View {
        if row.label.isEmpty {
            names(row, of: line)
        } else if typeSize.isAccessibilitySize {
            VStack(alignment: alignment, spacing: 0) {
                label(row.label)
                names(row, of: line)
            }
        } else {
            // A no-break space and a little kerning tie the label to the first name (about 0.45 em).
            Text("\(label(row.label))\(tie)\(names(row, of: line))")
        }
    }

    private var tie: Text { Text("\u{00A0}").kerning(size * 0.2) }

    private func label(_ text: String) -> Text {
        Text(text)
            .font(style.font(size: size).lowercaseSmallCaps())
            .tracking(size * Layout.roleLabelTracking)
            .foregroundStyle(Palette.textSecondary)
    }

    private func names(_ row: Roles.Line.Row, of line: Roles.Line) -> Text {
        let linked = LinkedNames.text(
            row.text, names: line.names, link: { link(line, $0) }, tint: tint, underline: contrast == .increased)
        return Text(linked).font(style.font(size: size))
    }
}

/// Names in a line of text, each name that has a page as a link. Increase Contrast underlines a link in its own
/// colour (ADR 0034).
enum LinkedNames {
    static func text(
        _ text: String, names: [String], link: (String) -> Page?, tint: Color, underline: Bool
    ) -> AttributedString {
        var result = AttributedString(text)
        var start = result.startIndex
        for name in names {
            guard let range = result[start...].range(of: name) else { continue }
            start = range.upperBound
            guard let page = link(name), let url = PageLink.url(page) else { continue }
            result[range].link = url
            result[range].foregroundColor = tint
            if underline { result[range].underlineStyle = Text.LineStyle.single }
        }
        return result
    }
}
