import SwiftUI

/// Names, one line per role, behind a small-cap label (ADR 0031). A row aligns them on the leading edge. The page
/// header centres them.
struct RoleLines: View {
    let lines: [Roles.Line]
    let alignment: HorizontalAlignment
    let style: TypeStyle
    @ScaledMetric(space: .inGroup) private var gap: CGFloat
    @ScaledMetric private var size: CGFloat
    @Environment(\.dynamicTypeSize) private var typeSize

    /// `style` sets the size of label and names. The explicit fonts here ignore a `typeStyle` of the caller.
    init(lines: [Roles.Line], alignment: HorizontalAlignment = .leading, style: TypeStyle = .body) {
        self.lines = lines
        self.alignment = alignment
        self.style = style
        _size = ScaledMetric(wrappedValue: style.size, relativeTo: style.textStyle)
    }

    var body: some View {
        let rows = lines.flatMap { $0.rows() }
        if !rows.isEmpty {
            VStack(alignment: alignment, spacing: gap) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    line(row)
                }
            }
            .accessibilityElement(children: .combine)
        }
    }

    /// At accessibility sizes the label stands above its names.
    @ViewBuilder private func line(_ row: Roles.Line.Row) -> some View {
        if row.label.isEmpty {
            names(row)
        } else if typeSize.isAccessibilitySize {
            VStack(alignment: alignment, spacing: 0) {
                label(row.label)
                names(row)
            }
        } else {
            // A no-break space and a little kerning tie the label to the first name (about 0.45 em).
            Text("\(label(row.label))\(tie)\(names(row))")
        }
    }

    private var tie: Text { Text("\u{00A0}").kerning(size * 0.2) }

    private func label(_ text: String) -> Text {
        Text(text)
            .font(style.font(size: size).lowercaseSmallCaps())
            .tracking(size * 0.06)
            .foregroundStyle(Palette.textSecondary)
    }

    private func names(_ row: Roles.Line.Row) -> Text {
        Text(row.text).font(style.font(size: size))
    }
}
