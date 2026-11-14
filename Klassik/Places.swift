import SwiftUI
import TipKit
import UIKit

/// The system tab controller keeps each place and its stack, with room beside its bar for the mini player.
struct PlacesView: View {
    @Environment(AppModel.self) private var model
    @State private var navigator = AppNavigator()
    @AppStorage(TimelineSide.storageKey) private var side = TimelineSide.standard
    @State private var backTransition = PlaceBackTransition()
    @State private var tabBarFrame: CGRect?
    @State private var pillInset = Measure.timeline + Space.xs.points

    var body: some View {
        let playing = model.playback.item != nil
        let rowHeight = tabBarFrame?.height ?? TabRow.height
        SystemPlaces(
            model: model, navigator: navigator, selection: navigator.selection, backTransition: backTransition,
            side: side,
            reservedWidth: playing ? MiniPlayer.width(height: rowHeight, edgeInset: pillInset) + Space.s.points : 0,
            playerOpen: navigator.isPlayerOpen,
            onLayout: { tabBarFrame = $0 }
        )
        .ignoresSafeArea(.container)
        .background { PlaceBackSurface(transition: backTransition) }
        .overlay {
            GeometryReader { safe in
                let insets = safe.safeAreaInsets
                GeometryReader { display in
                    let gap =
                        tabBarFrame.map {
                            max(0, display.size.height - $0.maxY)
                        } ?? TabRow.gap(safeArea: insets.bottom)
                    if playing {
                        VStack(spacing: 0) {
                            TimelineBarView(side: side)
                            HStack(spacing: 0) {
                                if side == .right { Spacer(minLength: 0) }
                                MiniPlayer(side: side, height: rowHeight, edgeInset: pillInset)
                                if side == .left { Spacer(minLength: 0) }
                            }
                            .frame(height: rowHeight)
                            .accessibilityElement(children: .contain)
                        }
                        .padding(.top, insets.top)
                        .padding(.bottom, gap)
                        MiniPlayerCorner(side: side, top: display.size.height - gap - rowHeight)
                            .allowsHitTesting(false)
                    }
                }
                .ignoresSafeArea(.container)
                .onGeometryChange(for: CGFloat.self) { geometry in
                    let corners = geometry.concentricCornerRadii
                    let radius = side == .right ? corners?.bottomTrailing : corners?.bottomLeading
                    let bottom =
                        tabBarFrame.map {
                            max(0, geometry.size.height - $0.maxY)
                        } ?? TabRow.gap(safeArea: insets.bottom)
                    return MiniPlayer.coverInset(radius: radius ?? 0, bottom: bottom)
                } action: {
                    pillInset = $0
                }
            }
            .ignoresSafeArea(.keyboard)
        }
        .environment(navigator)
    }
}

/// UIKit supplies glass selection, drag tracking and accessibility. Only the bar's available width changes.
private struct SystemPlaces: UIViewControllerRepresentable {
    let model: AppModel
    let navigator: AppNavigator
    let selection: Place
    let backTransition: PlaceBackTransition
    let side: TimelineSide
    let reservedWidth: CGFloat
    let playerOpen: Bool
    let onLayout: @MainActor (CGRect) -> Void

    func makeUIViewController(context: Context) -> PlacesController {
        let controller = PlacesController()
        controller.delegate = context.coordinator
        controller.tabBar.accessibilityIdentifier = "tab-row"
        controller.viewControllers = Place.allCases.map { place in
            let root: AnyView
            switch place {
            case .library: root = AnyView(PlaceStack(place: place) { LibraryView() })
            case .chronology: root = AnyView(PlaceStack(place: place) { WorkTimelineView() })
            case .search: root = AnyView(PlaceStack(place: place) { SearchView() })
            }
            let host = UIHostingController(
                rootView:
                    root
                    .environment(model)
                    .environment(navigator)
                    .environment(\.placeBackTransition, backTransition)
                    .environment(\.tabRowClearance, Space.s.points)
                    .tint(Palette.tint))
            host.tabBarItem = UITabBarItem(
                title: place.title, image: UIImage(systemName: place.symbol),
                selectedImage: UIImage(systemName: place == .library ? "books.vertical.fill" : place.symbol))
            host.tabBarItem.accessibilityIdentifier = "tab-\(place.rawValue)"
            return host
        }
        controller.installPlayer(
            AnyView(PlayerOverlayLayer().environment(model).environment(navigator).tint(Palette.tint)))
        return controller
    }

    func updateUIViewController(_ controller: PlacesController, context: Context) {
        let selected = Place.allCases.firstIndex(of: selection) ?? 0
        if controller.selectedIndex != selected { controller.selectedIndex = selected }
        controller.playerHost?.view.isUserInteractionEnabled = playerOpen
        controller.onLayout = onLayout
        controller.reservedWidth = reservedWidth
        controller.side = side
        controller.tabBar.tintColor = Palette.tint.uiColor
        controller.view.setNeedsLayout()
    }

    func makeCoordinator() -> Coordinator { Coordinator(navigator: navigator) }

    final class Coordinator: NSObject, UITabBarControllerDelegate {
        let navigator: AppNavigator

        init(navigator: AppNavigator) { self.navigator = navigator }

        func tabBarController(_ controller: UITabBarController, shouldSelect viewController: UIViewController) -> Bool {
            guard let index = controller.viewControllers?.firstIndex(of: viewController) else { return false }
            navigator.selectTab(Place.allCases[index])
            // UIKit must not pop the selected stack when its tab dismisses the player.
            return false
        }
    }
}

private final class PlacesController: UITabBarController {
    var reservedWidth: CGFloat = 0
    var side = TimelineSide.right
    var onLayout: (@MainActor (CGRect) -> Void)?
    private var reportedFrame: CGRect?
    private(set) var playerHost: UIHostingController<AnyView>?

    func installPlayer(_ root: AnyView) {
        let host = UIHostingController(rootView: root)
        addChild(host)
        host.view.backgroundColor = .clear
        host.view.isUserInteractionEnabled = false
        view.insertSubview(host.view, belowSubview: tabBar)
        host.didMove(toParent: self)
        playerHost = host
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        var frame = tabBar.frame
        frame.origin.x = side == .left ? reservedWidth : 0
        frame.size.width = max(0, view.bounds.width - reservedWidth)
        tabBar.frame = frame
        playerHost?.view.frame = view.bounds
        let bottom = max(0, view.bounds.maxY - frame.minY - view.safeAreaInsets.bottom)
        if playerHost?.additionalSafeAreaInsets.bottom != bottom {
            playerHost?.additionalSafeAreaInsets.bottom = bottom
        }
        view.bringSubviewToFront(tabBar)
        let content = tabBar.safeAreaLayoutGuide.layoutFrame.offsetBy(dx: frame.minX, dy: frame.minY)
        if reportedFrame != content, let onLayout {
            reportedFrame = content
            Task { @MainActor in onLayout(content) }
        }
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

/// Playback controls align with the native tab bar; their safe-area gap keeps the square cover clear.
enum TabRow {
    nonisolated static let height = MiniPlayer.item + 2 * Space.xs.points

    nonisolated static func gap(safeArea bottom: CGFloat) -> CGFloat {
        max(bottom, Space.s.points)
    }

    nonisolated static func clearance(safeArea bottom: CGFloat) -> CGFloat {
        max(0, gap(safeArea: bottom) + height + Space.s.points - bottom)
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
                                    backTransition.perform(
                                        reduceMotion: reduceMotion, bottom: TabRow.height + clearance
                                    ) {
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
        .accessibilityHidden(navigator.isPlayerOpen)
    }
}

/// Keeps the last rows of a page clear of the tab row, and the scroll indicator clear of the timeline (ADR 0029).
/// Each page needs its own inset: an inset on the `NavigationStack` does not move the last rows of a pushed List.
/// UIKit keeps the native tab bar visible as the page stack changes.
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
