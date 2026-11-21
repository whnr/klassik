import SwiftUI

/// The tabs of a person page, drawn flat as person.html .segmented draws them. The thumb slides to the chosen tab
/// and the content under it changes at once. The system segmented control draws glass that morphs between the
/// states, which this page does not want.
struct PageTabs<Tab: Hashable>: View {
    let tabs: [Tab]
    let title: (Tab) -> String
    @Binding var selection: Tab
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .subheadline) private var height = Layout.segmentedHeight

    var body: some View {
        let chosen = tabs.firstIndex(of: selection) ?? 0
        HStack(spacing: 0) {
            ForEach(tabs, id: \.self) { tab in
                Button {
                    selection = tab
                } label: {
                    Text(title(tab))
                        .typeStyle(Layout.segmentedLabel)
                        .foregroundStyle(Palette.textPrimary)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, minHeight: height)
                        .contentShape(Rectangle())
                }
                .buttonStyle(FlatPress())
                .accessibilityAddTraits(tab == selection ? .isSelected : [])
            }
        }
        .background(alignment: .leading) {
            GeometryReader { proxy in
                let width = proxy.size.width / CGFloat(max(tabs.count, 1))
                RoundedRectangle(cornerRadius: Layout.segmentedCorner - Layout.segmentedPadding)
                    .fill(Palette.backgroundRow)
                    .shadow(color: .black.opacity(0.12), radius: Layout.segmentedShadow, y: Layout.segmentedShadowY)
                    .frame(width: width, height: proxy.size.height)
                    .offset(x: width * CGFloat(chosen))
                    .animation(Motion.open.animation(reduceMotion: reduceMotion), value: chosen)
            }
            .accessibilityHidden(true)
        }
        .padding(Layout.segmentedPadding)
        .background(Palette.fillQuiet, in: RoundedRectangle(cornerRadius: Layout.segmentedCorner))
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
