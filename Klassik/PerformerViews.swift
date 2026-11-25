import SwiftUI

/// The look of the control: the person page tabs, or the kinds of the filter sheet.
struct PageTabsStyle {
    var label: TypeStyle
    var height: CGFloat
    var corner: CGFloat
    /// The filter sheet sets the chosen kind in bold.
    var boldSelection: Bool

    static let page = PageTabsStyle(
        label: Layout.segmentedLabel, height: Layout.segmentedHeight, corner: Layout.segmentedCorner,
        boldSelection: false)
    static let kinds = PageTabsStyle(
        label: Layout.filterKindsLabel, height: Layout.filterKindsHeight, corner: Layout.filterKindsCorner,
        boldSelection: true)
}

/// The tabs of a person page, drawn flat as person.html .segmented draws them. The thumb slides to the chosen tab
/// and the content under it changes at once. The system segmented control draws glass that morphs between the
/// states, which this page does not want.
struct PageTabs<Tab: Hashable>: View {
    let tabs: [Tab]
    let title: (Tab) -> String
    @Binding var selection: Tab
    var style = PageTabsStyle.page
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Dynamic Type scales both heights by the factor of the page height.
    @ScaledMetric(relativeTo: .subheadline) private var scaledHeight = Layout.segmentedHeight
    private var scale: CGFloat { scaledHeight / Layout.segmentedHeight }

    var body: some View {
        let chosen = tabs.firstIndex(of: selection) ?? 0
        HStack(spacing: 0) {
            ForEach(tabs, id: \.self) { tab in
                Button {
                    selection = tab
                } label: {
                    Text(title(tab))
                        .typeStyle(style.label)
                        .fontWeight(style.boldSelection && tab == selection ? .semibold : nil)
                        .foregroundStyle(Palette.textPrimary)
                        .frame(maxWidth: .infinity, minHeight: style.height * scale)
                        .contentShape(Rectangle())
                }
                .buttonStyle(FlatPress())
                .accessibilityAddTraits(tab == selection ? .isSelected : [])
            }
        }
        .background(alignment: .leading) {
            GeometryReader { proxy in
                let width = proxy.size.width / CGFloat(max(tabs.count, 1))
                RoundedRectangle(cornerRadius: style.corner - Layout.segmentedPadding)
                    .fill(Palette.backgroundRow)
                    .shadow(color: .black.opacity(0.12), radius: Layout.segmentedShadow, y: Layout.segmentedShadowY)
                    .frame(width: width, height: proxy.size.height)
                    .offset(x: width * CGFloat(chosen))
                    .animation(Motion.open.animation(reduceMotion: reduceMotion), value: chosen)
            }
            .accessibilityHidden(true)
        }
        .padding(Layout.segmentedPadding)
        .background(Palette.fillQuiet, in: RoundedRectangle(cornerRadius: style.corner))
        .accessibilityElement(children: .contain)
    }
}

/// A press dims the label and nothing else: no glass, no scale, no row highlight.
struct FlatPress: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}
