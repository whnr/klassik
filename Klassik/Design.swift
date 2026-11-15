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
struct PageList<Content: View>: View {
    @Environment(\.pageHeading) private var heading
    @ViewBuilder let content: Content

    var body: some View {
        List {
            PageHeading(title: heading, plain: true)
            BackTipRow()
                .listRowBackground(Color.clear)
            content.listRowBackground(Color.clear)
        }
        .listStyle(.plain)
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
struct SectionHeading: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .typeStyle(.sectionHeading)
            .foregroundStyle(Palette.textPrimary)
            .textCase(nil)
    }
}

/// The heading scrolls as content, so UIKit cannot collapse it before it crosses the soft edge.
private struct PageHeading: View {
    let title: String
    /// A plain list sets the heading as the specimen does: close under the back arrow.
    let plain: Bool

    private static let plainInsets = EdgeInsets(
        top: Space.xs.points, leading: 20, bottom: Space.s.points, trailing: 20)

    var body: some View {
        if !title.isEmpty {
            Text(title)
                .typeStyle(.pageTitle)
                .foregroundStyle(Palette.textPrimary)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("page-heading")
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(plain ? Self.plainInsets : nil)
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

extension EnvironmentValues {
    @Entry var pageHeading = ""
}
