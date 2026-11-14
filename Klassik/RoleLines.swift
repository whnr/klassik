import SwiftUI

/// Names, one line per role, behind a small-cap label (ADR 0031). A row aligns them on the leading edge. The page
/// header centres them.
struct RoleLines: View {
    let lines: [Roles.Line]
    var alignment: HorizontalAlignment = .leading
    @ScaledMetric(space: .inGroup) private var gap: CGFloat
    @ScaledMetric(relativeTo: .body) private var size = TypeStyle.body.size
    @Environment(\.dynamicTypeSize) private var typeSize

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
            // A no-break space ties the label to the first name.
            (label(row.label) + Text("\u{00A0}") + names(row))
        }
    }

    private func label(_ text: String) -> Text {
        Text(text)
            .font(TypeStyle.body.font(size: size).lowercaseSmallCaps())
            .tracking(size * 0.06)
            .foregroundStyle(Palette.textSecondary)
    }

    private func names(_ row: Roles.Line.Row) -> Text {
        Text(row.text).font(TypeStyle.body.font(size: size))
    }
}
