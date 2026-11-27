import SwiftUI

/// The frame that the Library edit sheet and the Search filter sheet share (the specimen sheet frame): one header
/// line, a footnote line for a count, and one scroll area. A back chevron shows only one level deeper, and Done
/// closes. Changes apply at once, so the frame has no Cancel.
/// A part that must stay under the header goes in a `Section` with a header: the scroll area pins it.
struct SheetFrame<Content: View>: View {
    let title: LocalizedStringKey
    /// The line under the title. Empty keeps the line, so the scroll area does not move when a count appears.
    let count: String
    let back: (() -> Void)?
    let done: () -> Void
    /// The start of the accessibility identifiers of the sheet's Done, Back and count.
    let identifier: String
    let content: Content
    @ScaledMetric(relativeTo: .body) private var hitTarget = Layout.frameHeadHeight

    init(
        title: LocalizedStringKey, count: String = "", back: (() -> Void)? = nil, done: @escaping () -> Void,
        identifier: String = "sheet", @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.count = count
        self.back = back
        self.done = done
        self.identifier = identifier
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Text(verbatim: count.isEmpty ? "\u{200B}" : count)
                .typeStyle(.footnote)
                .monospacedDigit()
                .foregroundStyle(Palette.textSecondary)
                .padding(.horizontal, Layout.frameHeadInset)
                .padding(.bottom, Layout.frameCountBottom)
                .accessibilityIdentifier("\(identifier)-count")
                .accessibilityHidden(count.isEmpty)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                    content
                }
                .padding(.leading, Layout.frameScrollInset)
                .padding(.trailing, Layout.frameScrollTrailing)
                .padding(.bottom, Layout.frameScrollBottom)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .background(Palette.backgroundGrouped)
    }

    /// Back, title and Done on one line. The outer columns share the width, so the title stays centred.
    private var header: some View {
        HStack(spacing: 0) {
            // The clear base keeps the column at its share of the width when there is no Back.
            ZStack(alignment: .leading) {
                Color.clear
                if let back {
                    Button(action: back) {
                        Image(systemName: "chevron.left")
                            .fontWeight(.semibold)
                            .frame(width: hitTarget, height: hitTarget)
                            .contentShape(Rectangle())
                    }
                    .padding(.leading, Layout.frameBackMargin)
                    .accessibilityLabel("Back")
                    .accessibilityIdentifier("\(identifier)-back")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(title)
                .typeStyle(.headline)
                .foregroundStyle(Palette.textPrimary)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
            Button("Done", action: done)
                .typeStyle(.headline)
                .frame(minHeight: hitTarget)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .accessibilityIdentifier("\(identifier)-done")
        }
        .padding(.top, Layout.frameHeadTop)
        .padding(.horizontal, Layout.frameHeadInset)
        .frame(minHeight: hitTarget)
    }
}

extension View {
    /// Presents the content in the fixed half-height frame: no other height, the system grabber, and the corner of
    /// the specimen.
    func sheetFrame() -> some View {
        presentationDetents([.fraction(Layout.frameHeightRatio)])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(Layout.frameCorner)
            .presentationBackground(Palette.backgroundGrouped)
    }
}
