import CoreText
import SwiftUI
import TipKit
import UIKit

extension Palette {
    /// The colour for UIKit, which follows the appearance and the contrast setting as the colour set does.
    var uiColor: UIColor { UIColor(named: assetName()) ?? .label }
}

/// The faces that the app bundles.
enum BundledFonts {
    static let files = ["Wittgenstein-Medium"]
    /// The licence of each face. The SIL Open Font License asks that its text goes with the font.
    static let licences = [Licence(name: "Wittgenstein", file: "Wittgenstein-OFL")]

    struct Licence: Identifiable, Sendable {
        let name: String
        /// The text file in the bundle, without its extension.
        let file: String
        var id: String { file }

        var text: String {
            guard let url = Bundle.main.url(forResource: file, withExtension: "txt") else { return "" }
            return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        }
    }

    /// Makes the faces known to the process. The app calls this before it draws the first view,
    /// because the navigation bar takes its title font once.
    static func register() {
        for file in files {
            guard let url = Bundle.main.url(forResource: file, withExtension: "ttf") else { continue }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }
}

extension TypeStyle {
    /// The font at a size that Dynamic Type has scaled already.
    func font(size: CGFloat) -> Font {
        if let face { .custom(face, fixedSize: size) } else { .system(size: size, weight: weight) }
    }
}

private struct TypeStyleModifier: ViewModifier {
    private let style: TypeStyle
    @ScaledMetric private var size: CGFloat

    init(style: TypeStyle) {
        self.style = style
        _size = ScaledMetric(wrappedValue: style.size, relativeTo: style.textStyle)
    }

    func body(content: Content) -> some View {
        content.font(style.font(size: size))
    }
}

/// An explicit foreground style does not dim in a disabled row, so the disabled colour stands in.
private struct InkModifier: ViewModifier {
    @Environment(\.isEnabled) private var isEnabled

    func body(content: Content) -> some View {
        content.foregroundStyle(
            isEnabled ? Palette.textPrimary : Palette.textTertiary,
            isEnabled ? Palette.textSecondary : Palette.textTertiary,
            Palette.textTertiary)
    }
}

private struct MotionModifier<Value: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let motion: Motion
    let value: Value

    func body(content: Content) -> some View {
        content.animation(motion.animation(reduceMotion: reduceMotion), value: value)
    }
}

extension View {
    /// Sets a text style. Its size follows Dynamic Type without an upper limit.
    func typeStyle(_ style: TypeStyle) -> some View {
        modifier(TypeStyleModifier(style: style))
    }

    /// Animates the changes of a value. Reduce Motion gets a short cross-fade.
    func motion(_ motion: Motion, value: some Equatable) -> some View {
        modifier(MotionModifier(motion: motion, value: value))
    }

    /// Sets ink for text, and the two quieter text colours for the levels below it.
    /// A button must not get it: a foreground style replaces the tint of a button.
    func ink() -> some View {
        modifier(InkModifier())
    }

    /// Puts an inset list on Klassik's grounds.
    func grounds() -> some View {
        scrollContentBackground(.hidden)
            .background(Palette.backgroundGrouped)
    }
}

extension ScaledMetric where Value == CGFloat {
    /// A gap that grows with Dynamic Type.
    init(space: Space, relativeTo textStyle: Font.TextStyle = .body) {
        self.init(wrappedValue: space.points, relativeTo: textStyle)
    }
}

/// The plain list of a content page (ADR 0030): rows and hairlines on the paper ground, no cards.
/// Every row takes the specimen row insets. A row that sets its own insets keeps them.
struct PageList<Content: View>: View {
    @Environment(\.pageHeading) private var heading
    @ViewBuilder let content: Content

    var body: some View {
        List {
            PageHeading(title: heading, plain: true)
            BackTipRow()
                .listRowBackground(Color.clear)
            content
                .listRowBackground(Color.clear)
                .pageRow()
        }
        .listStyle(.plain)
        // The specimen gaps are the whole distance between two lines. A system minimum would add to them.
        .environment(\.defaultMinListRowHeight, 0)
        .environment(\.defaultMinListHeaderHeight, 0)
        .environment(\.isPageList, true)
        .scrollContentBackground(.hidden)
        .background(Palette.backgroundPage)
    }
}

/// The inset grouped list of Settings and sheets (ADR 0030), on Klassik's grounds.
/// The system gives a list its own colours, and each row its own ground.
struct GroupedPageList<Content: View>: View {
    @Environment(\.pageHeading) private var heading
    @ViewBuilder let content: Content

    var body: some View {
        List {
            PageHeading(title: heading, plain: false)
            BackTipRow()
            content.listRowBackground(Palette.backgroundRow.color)
        }
        .grounds()
    }
}

/// A `Form` on Klassik's grounds.
struct PageForm<Content: View>: View {
    @Environment(\.pageHeading) private var heading
    @ViewBuilder let content: Content

    var body: some View {
        Form {
            PageHeading(title: heading, plain: false)
            BackTipRow()
            content.listRowBackground(Palette.backgroundRow.color)
        }
        .grounds()
    }
}

/// A label with its title in ink. The icon keeps the tint, which `ink()` on a whole label replaces.
struct InkLabel: View {
    let title: String
    let systemImage: String

    init(_ title: String, systemImage: String) {
        self.title = title
        self.systemImage = systemImage
    }

    var body: some View {
        Label {
            Text(title).ink()
        } icon: {
            Image(systemName: systemImage)
        }
    }
}

/// The heading of a section on a content page, in sentence case. Settings keep the system header.
/// A content page sets it as the first row of its section, not as the section header: a plain list adds padding of
/// its own above a header and pins the header while the page scrolls, and the specimen has neither.
struct SectionHeading: View {
    @Environment(\.isPageList) private var isPageList
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .typeStyle(Layout.sectionHeading)
            .foregroundStyle(Palette.textPrimary)
            .textCase(nil)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("section-heading")
            .pageSectionHeader(isPageList)
    }
}

/// The heading scrolls as content, so UIKit cannot collapse it before it crosses the soft edge.
private struct PageHeading: View {
    @AppStorage(TimelineSide.storageKey) private var side = TimelineSide.standard
    @Environment(\.pageHeadingBottom) private var bottom
    let title: String
    @Environment(\.pageFavourite) private var favourite
    /// A plain list sets the heading as the specimen does: close under the back arrow.
    let plain: Bool

    var body: some View {
        if !title.isEmpty {
            Group {
                if let favourite {
                    FavouriteTitle(title: title, isSet: favourite.isSet, action: favourite.action)
                        .accessibilityIdentifier(favourite.identifier)
                } else {
                    Text(title).accessibilityIdentifier("page-heading")
                }
            }
            .typeStyle(Layout.pageTitle)
            .foregroundStyle(Palette.textPrimary)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(plain ? Layout.edges(side: side, top: Layout.headTop, bottom: bottom) : nil)
        }
    }
}

extension View {
    /// The navigation name supplies Back and VoiceOver; the list draws the visible heading (ADR 0023).
    func pageTitle(_ title: String) -> some View {
        environment(\.pageHeading, title)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
    }
}

struct FavouriteHeading {
    var isSet: Bool
    var action: @MainActor () -> Void
    var identifier: String
}

extension EnvironmentValues {
    @Entry var pageFavourite: FavouriteHeading? = nil
    @Entry var pageHeading = ""
    /// The gap under the page title. A page with meta lines under its title sets the specimen gap to them.
    @Entry var pageHeadingBottom = Layout.headBottom
    /// True inside `PageList`. A grouped list keeps the system insets of its headers.
    @Entry var isPageList = false
}

extension Layout {
    /// The page insets for a timeline on `side`: the timeline side keeps clear of the timeline.
    /// Each content page uses them. Settings and sheets keep the system insets.
    static func edges(side: TimelineSide, top: CGFloat = 0, bottom: CGFloat = 0) -> EdgeInsets {
        EdgeInsets(
            top: top, leading: side == .left ? timelineEdge : edge,
            bottom: bottom, trailing: side == .left ? edge : timelineEdge)
    }
}

/// Sets the specimen page insets on a list row, for the timeline side that the listener chose.
private struct PageEdges: ViewModifier {
    @AppStorage(TimelineSide.storageKey) private var side = TimelineSide.standard
    let top: CGFloat
    let bottom: CGFloat

    func body(content: Content) -> some View {
        content.listRowInsets(Layout.edges(side: side, top: top, bottom: bottom))
    }
}

/// The page edges of the timeline side without a list row, such as a scrolling row of chips.
private struct PagePadding: ViewModifier {
    @AppStorage(TimelineSide.storageKey) private var side = TimelineSide.standard

    func body(content: Content) -> some View {
        let insets = Layout.edges(side: side)
        content
            .padding(.leading, insets.leading)
            .padding(.trailing, insets.trailing)
    }
}

extension View {
    /// The row insets of a content page.
    func pageEdges(top: CGFloat = 0, bottom: CGFloat = 0) -> some View {
        modifier(PageEdges(top: top, bottom: bottom))
    }

    /// The insets of a row of a content page.
    func pageRow() -> some View {
        pageEdges(top: Layout.rowPadding, bottom: Layout.rowPadding)
    }

    /// The row of a section heading on a content page. A grouped list keeps the system insets.
    @ViewBuilder func pageSectionHeader(_ isPageList: Bool) -> some View {
        if isPageList {
            pageEdges(top: Layout.sectionTop, bottom: Layout.sectionHeadBottom)
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
        } else {
            self
        }
    }

    /// Leading and trailing page edges as padding.
    func pagePadding() -> some View {
        modifier(PagePadding())
    }
}
