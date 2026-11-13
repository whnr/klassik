import SwiftUI
import TipKit
import UIKit

/// The three places, each with its own stack. The system `TabView` keeps the places and their stacks. Its tab bar
/// spans the screen, so a tab bar drawn by hand takes its place and leaves room for the mini player (ADR 0028).
struct PlacesView: View {
    @Environment(AppModel.self) private var model
    /// Owned here, so that a sign-out takes the stacks away with the places.
    @State private var navigator = AppNavigator()
    @AppStorage(TimelineSide.storageKey) private var side = TimelineSide.standard
    @State private var backTransition = PlaceBackTransition()
    @State private var clearance = TabRow.clearance(safeArea: 0)

    var body: some View {
        TabView(selection: Binding(get: { navigator.selection }, set: { navigator.select($0) })) {
            Tab(Place.library.title, systemImage: Place.library.symbol, value: Place.library) {
                PlaceStack(place: .library) { LibraryView() }
            }
            Tab(Place.chronology.title, systemImage: Place.chronology.symbol, value: Place.chronology) {
                PlaceStack(place: .chronology) { WorkTimelineView() }
            }
            Tab(value: Place.search, role: .search) {
                PlaceStack(place: .search) { SearchView() }
            }
        }
        .background { PlaceBackSurface(transition: backTransition) }
        .environment(\.placeBackTransition, backTransition)
        .onChange(of: model.playback.item.map(Page.init(playing:))) { old, new in
            navigator.followPlayback(from: old, to: new)
        }
        .overlay {
            // The reader keeps the safe area, so its insets are real. The chrome inside ignores it and places
            // itself: the timeline starts at the top safe area (ADR 0035), and the tab row sits where the system
            // tab bar sits. The keyboard does not move the chrome, so the row stays below the search results.
            GeometryReader { proxy in
                let insets = proxy.safeAreaInsets
                VStack(spacing: 0) {
                    if model.playback.item != nil {
                        TimelineBarView(side: side)
                    } else {
                        Spacer(minLength: 0)
                    }
                    TabRow(side: side)
                }
                .padding(.top, insets.top)
                .padding(.bottom, TabRow.gap(safeArea: insets.bottom))
                .ignoresSafeArea(.container)
                .onChange(of: insets.bottom, initial: true) { _, bottom in
                    clearance = TabRow.clearance(safeArea: bottom)
                }
            }
            .ignoresSafeArea(.keyboard)
        }
        .environment(\.tabRowClearance, clearance)
        .environment(navigator)
    }
}

extension Place {
    var symbol: String {
        switch self {
        case .library: "books.vertical"
        case .chronology: "calendar"
        case .search: "magnifyingglass"
        }
    }
}

/// The tab bar, drawn by hand: the tabs in a glass capsule, Search on its own, and the mini player on the
/// timeline's side while something plays. It keeps the height of the system tab bar (ADR 0028).
struct TabRow: View {
    @Environment(AppModel.self) private var model
    @Environment(AppNavigator.self) private var navigator
    let side: TimelineSide

    /// The capsule around the items: as tall as the pill.
    nonisolated static let height = MiniPlayer.item + 2 * Space.xs.points
    /// The distance from the screen bottom to the row.
    nonisolated static func gap(safeArea bottom: CGFloat) -> CGFloat {
        max(bottom, Space.s.points)
    }

    /// The height above the bottom safe area that a page keeps clear: the row and a gap of `Space.s` above it.
    nonisolated static func clearance(safeArea bottom: CGFloat) -> CGFloat {
        max(0, gap(safeArea: bottom) + height + Space.s.points - bottom)
    }

    var body: some View {
        let playing = model.playback.item != nil
        HStack(spacing: Space.s.points) {
            if playing, side == .left { MiniPlayer(side: side) }
            GlassEffectContainer(spacing: Space.s.points) {
                HStack(spacing: Space.s.points) {
                    HStack(spacing: 0) {
                        ForEach([Place.library, .chronology], id: \.self) { place in
                            tab(place)
                        }
                    }
                    .padding(Space.xs.points)
                    .glassEffect(.regular.interactive(), in: .capsule)
                    tab(.search)
                        .padding(Space.xs.points)
                        .frame(width: Self.height)
                        .glassEffect(.regular.interactive(), in: .circle)
                }
            }
            .padding(.leading, playing && side == .left ? 0 : Space.l.points)
            .padding(.trailing, playing && side == .right ? 0 : Space.l.points)
            if playing, side == .right { MiniPlayer(side: side) }
        }
        .frame(height: Self.height)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("tab-row")
    }

    private func tab(_ place: Place) -> some View {
        let selected = navigator.selection == place
        return Button {
            navigator.select(place)
        } label: {
            VStack(spacing: 1) {
                Image(systemName: place.symbol)
                    .font(.system(size: 22))
                    // As in the system tab bar, the selected tab shows the filled symbol.
                    .symbolVariant(selected ? .fill : .none)
                // A system tab bar keeps its label size and offers the large content viewer instead.
                if place != .search {
                    Text(place.title)
                        .font(.system(size: 10, weight: .medium))
                }
            }
            .frame(maxWidth: .infinity, minHeight: MiniPlayer.item)
            .foregroundStyle(selected ? Palette.tint : Palette.textPrimary)
            .background {
                if selected, place != .search { Capsule().fill(Palette.fillQuiet) }
            }
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(place.title)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityShowsLargeContentViewer()
        .accessibilityIdentifier("tab-\(place.rawValue)")
    }
}

/// The `NavigationStack` of one place. Its pages are the stack of the navigator. The back button of a page is the
/// system one. A root has none, so a root that the listener reached from another place gets an arrow and an
/// edge swipe back to that place (ADR 0038).
struct PlaceStack<Root: View>: View {
    @Environment(AppNavigator.self) private var navigator
    @Environment(AppModel.self) private var model
    @Environment(\.placeBackTransition) private var backTransition
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.tabRowClearance) private var clearance
    let place: Place
    @ViewBuilder let root: Root

    var body: some View {
        let target = navigator.backTarget(for: place)
        // On a pushed page the system swipe works, and this one stays off.
        let edgeSwipe = EdgeSwipe(isEnabled: target != nil && navigator.pages(in: place).isEmpty) {
            navigator.goBack(from: place)
        }
        NavigationStack(
            path: Binding(
                get: { navigator.pages(in: place) },
                set: { navigator.setPages($0, in: place) })
        ) {
            root
                .modifier(PlaceInsets())
                .gesture(edgeSwipe)
                .toolbar {
                    if let target {
                        ToolbarItem(placement: .topBarLeading) {
                            let name = target.page?.backTitle(in: model.library) ?? target.place.title
                            Button {
                                if let backTransition {
                                    backTransition.perform(reduceMotion: reduceMotion, bottom: clearance) {
                                        navigator.goBack(from: place)
                                    }
                                } else {
                                    navigator.goBack(from: place)
                                }
                            } label: {
                                // The system back button of iOS 27 draws the chevron only. The label keeps the name.
                                Image(systemName: "chevron.backward")
                                    .fontWeight(.semibold)
                            }
                            // The system back button draws in the primary colour, not in the tint of the app.
                            .tint(.primary)
                            .accessibilityLabel(name)
                            .accessibilityIdentifier("place-back")
                        }
                    }
                }
                .navigationDestination(for: Page.self) { page in
                    // From the second page on, the back button has a pages menu behind it.
                    // A repeated copy of the first page gets index 0 and shows no back tip.
                    PageView(page: page)
                        .modifier(PlaceInsets())
                        .environment(\.showsBackTip, (navigator.pages(in: place).firstIndex(of: page) ?? 0) >= 1)
                }
        }
        .toolbarVisibility(.hidden, for: .tabBar)
    }
}

/// Keeps the last rows of a page clear of the tab row, and the scroll indicator clear of the timeline (ADR 0029).
/// Each page needs its own inset: an inset on the `NavigationStack` does not move the last rows of a pushed List.
/// Each page also hides the system tab bar, so that a push does not bring it back.
private struct PlaceInsets: ViewModifier {
    @Environment(AppModel.self) private var model
    @AppStorage(TimelineSide.storageKey) private var side = TimelineSide.standard
    @Environment(\.tabRowClearance) private var clearance

    func body(content: Content) -> some View {
        let beside = model.playback.item != nil && side == .right ? Measure.timeline : 0
        content
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Color.clear
                    .frame(height: clearance)
                    .allowsHitTesting(false)
            }
            .scrollEdgeEffectStyle(.soft, for: .top)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    // Keep the large title and back labels while suppressing the inline title (ADR 0023).
                    Color.clear.frame(width: 1, height: 1).accessibilityHidden(true)
                }
            }
            .contentMargins(.trailing, beside, for: .scrollIndicators)
            .toolbarVisibility(.hidden, for: .tabBar)
    }
}

/// A swipe from the left screen edge, as the system back swipe, for a root that has no system back. It acts when
/// the swipe ends, without a peel of the page: one recogniser is all the code that this needs.
struct EdgeSwipe: UIGestureRecognizerRepresentable {
    /// The distance that counts as a swipe, in points.
    static let distance = 60.0

    let isEnabled: Bool
    let action: () -> Void

    func makeUIGestureRecognizer(context: Context) -> UIScreenEdgePanGestureRecognizer {
        let recognizer = UIScreenEdgePanGestureRecognizer()
        recognizer.edges = .left
        recognizer.isEnabled = isEnabled
        return recognizer
    }

    func updateUIGestureRecognizer(_ recognizer: UIScreenEdgePanGestureRecognizer, context: Context) {
        recognizer.isEnabled = isEnabled
    }

    func handleUIGestureRecognizerAction(_ recognizer: UIScreenEdgePanGestureRecognizer, context: Context) {
        guard recognizer.state == .ended, recognizer.translation(in: recognizer.view).x > Self.distance else { return }
        action()
    }
}

/// Tells the listener once that the back button opens a list of the pages behind it.
struct BackTip: Tip {
    var title: Text { Text("Hold Back to Go Further") }
    var message: Text? { Text("Touch and hold the back button to jump to any page behind this one.") }
    var image: Image? { Image(systemName: "chevron.backward") }
    var options: [any TipOption] { [Tips.MaxDisplayCount(1)] }
}

/// The row of the tip in a list. The row takes no ground of its own, so that the tip does not draw as a card
/// on the ground of the page.
struct BackTipRow: View {
    @Environment(\.showsBackTip) private var showsBackTip

    var body: some View {
        if showsBackTip {
            TipView(BackTip())
                .listRowBackground(Color.clear)
        }
    }
}

extension EnvironmentValues {
    @Entry var placeBackTransition: PlaceBackTransition? = nil
    /// True on a page that a pages menu sits behind, which is where the tip makes sense.
    @Entry var showsBackTip = false
    /// The height above the bottom safe area that the tab row takes, with its gap.
    @Entry var tabRowClearance = TabRow.clearance(safeArea: 0)
}
