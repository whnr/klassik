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
        let playing = model.showsTimeline
        let rowHeight = tabBarFrame?.height ?? TabRow.height
        SystemPlaces(
            model: model, navigator: navigator, selection: navigator.selection, backTransition: backTransition,
            side: side,
            reservedWidth: playing ? MiniPlayer.width(height: rowHeight, edgeInset: pillInset) + Space.s.points : 0,
            playerOpen: navigator.isPlayerOpen,
            accent: AccentChoice.shared.family,
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
                            max(0, display.frame(in: .global).maxY - $0.maxY)
                        } ?? TabRow.gap(safeArea: insets.bottom)
                    // The bar frame stays pinned under a keyboard, so the row position comes from it, not the display.
                    let rowTop =
                        tabBarFrame.map { $0.minY - display.frame(in: .global).minY }
                        ?? display.size.height - gap - rowHeight
                    let inset = MiniPlayer.coverInset(in: display, side: side, bottom: gap, height: rowHeight)
                    ZStack(alignment: .top) {
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
                            // Keyboard safe-area changes must not shorten the timeline above the native bar.
                            .frame(height: max(0, rowTop + rowHeight - insets.top))
                            .padding(.top, insets.top)
                        }
                    }
                    .onChange(of: inset, initial: true) { _, value in pillInset = value }
                }
                .ignoresSafeArea(.container)
            }
        }
        .ignoresSafeArea(.keyboard)
        .environment(navigator)
    }
}

/// A hosting controller starts its own environment, so the root of each host reads the accent pick itself
/// (ADR 0034). The read observes the pick, so every control under it takes a new family at once.
private struct AccentRoot: ViewModifier {
    func body(content: Content) -> some View {
        content
            .tint(Palette.tint)
            .environment(\.accentFamily, AccentChoice.shared.family)
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
    /// A new pick updates the controller, so the tab bar takes the new tint.
    let accent: AccentFamily
    let onLayout: @MainActor (CGRect) -> Void

    func makeUIViewController(context: Context) -> PlacesController {
        let controller = PlacesController()
        controller.delegate = context.coordinator
        controller.tabBar.accessibilityIdentifier = "tab-row"
        controller.tabs = Place.allCases.map { place in
            let root: AnyView
            switch place {
            case .library: root = AnyView(PlaceStack(place: place) { LibraryView() })
            case .chronology: root = AnyView(PlaceStack(place: place) { ChronologyView() })
            case .search: root = AnyView(PlaceStack(place: place) { SearchView() })
            }
            let host = UIHostingController(
                rootView:
                    root
                    .environment(model)
                    .environment(navigator)
                    .environment(\.placeBackTransition, backTransition)
                    .environment(\.tabRowClearance, Space.s.points)
                    .modifier(AccentRoot()))
            return place.tab(host)
        }
        controller.installPlayer(
            AnyView(
                PlayerOverlayLayer().environment(model).environment(navigator)
                    .environment(controller.playerLayout).modifier(AccentRoot())))
        return controller
    }

    func updateUIViewController(_ controller: PlacesController, context: Context) {
        let selected = Place.allCases.firstIndex(of: selection) ?? 0
        if controller.selectedIndex != selected { controller.selectedIndex = selected }
        controller.playerHost?.view.isUserInteractionEnabled = playerOpen
        controller.navigator = navigator
        controller.backTransition = backTransition
        backTransition.onCompletion = { [weak controller] in controller?.view.setNeedsLayout() }
        controller.onLayout = onLayout
        controller.reservedWidth = reservedWidth
        controller.side = side
        controller.tabBar.tintColor = UIColor(named: Palette.tint.assetName(in: accent))
        controller.view.setNeedsLayout()
    }

    func makeCoordinator() -> Coordinator { Coordinator(navigator: navigator) }

    final class Coordinator: NSObject, UITabBarControllerDelegate {
        let navigator: AppNavigator

        init(navigator: AppNavigator) { self.navigator = navigator }

        func tabBarController(_ controller: UITabBarController, shouldSelectTab tab: UITab) -> Bool {
            // The search tab keeps the identifier that UIKit gives it, so the position names the place.
            guard let index = controller.tabs.firstIndex(where: { $0 === tab }) else { return false }
            let place = Place.allCases[index]
            let dismissesCurrent = navigator.isPlayerOpen && navigator.selection == place
            navigator.selectTab(place)
            // UIKit must not pop the selected stack when its tab dismisses the player.
            return !dismissesCurrent
        }
    }
}

private final class PlacesController: UITabBarController, UIGestureRecognizerDelegate {
    var navigator: AppNavigator?
    var backTransition: PlaceBackTransition?
    private var edgePan: UIScreenEdgePanGestureRecognizer?
    private weak var nativePan: UIGestureRecognizer?
    private weak var nativePanView: UIView?
    var reservedWidth: CGFloat = 0
    var side = TimelineSide.right
    var onLayout: (@MainActor (CGRect) -> Void)?
    private var reportedFrame: CGRect?
    private var restingFrame: CGRect?
    private var keyboardVisible = false
    /// Set when the keyboard closes. The tab labels then measure their text again.
    private var remeasuresLabels = false
    /// The pass after the first remeasure: the bar has its final, narrow frame then, and the labels must fit it.
    private var remeasuresAtFinalFrame = false
    private(set) var playerHost: UIHostingController<AnyView>?
    let playerLayout = PlayerOverlayLayout()

    func installPlayer(_ root: AnyView) {
        let host = UIHostingController(rootView: root)
        addChild(host)
        host.view.backgroundColor = .clear
        host.view.isUserInteractionEnabled = false
        view.addSubview(host.view)
        host.didMove(toParent: self)
        playerHost = host
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        for name in [UIResponder.keyboardWillShowNotification, UIResponder.keyboardDidHideNotification] {
            NotificationCenter.default.addObserver(
                self, selector: #selector(keyboardVisibilityChanged(_:)), name: name, object: nil)
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func keyboardVisibilityChanged(_ notification: Notification) {
        keyboardVisible = notification.name == UIResponder.keyboardWillShowNotification
        if !keyboardVisible { remeasuresLabels = true }
        view.setNeedsLayout()
    }

    /// The timeline is outside the navigation view. The window lets UIKit receive an edge touch through it.
    private func configureBackGesture() {
        guard backTransition?.isTracking != true, let navigator, let window = view.window else { return }
        if nativePan?.state == .began || nativePan?.state == .changed { return }
        if edgePan == nil {
            let pan = UIScreenEdgePanGestureRecognizer(target: self, action: #selector(dragBack(_:)))
            pan.edges = .left
            pan.delegate = self
            window.addGestureRecognizer(pan)
            edgePan = pan
        }
        let root = navigator.pages(in: navigator.selection).isEmpty
        edgePan?.isEnabled = root && !navigator.isPlayerOpen && navigator.backTarget(for: navigator.selection) != nil
        let navigation = navigationController(in: selectedViewController)
        let next =
            !root && side == .left && !navigator.isPlayerOpen
            ? navigation?.interactivePopGestureRecognizer : nil
        if nativePan !== next {
            if let nativePan, let nativePanView, nativePan.view !== nativePanView {
                nativePanView.addGestureRecognizer(nativePan)
            }
            nativePan = next
            nativePanView = next?.view
            if let next { window.addGestureRecognizer(next) }
        }
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let pan = gestureRecognizer as? UIScreenEdgePanGestureRecognizer,
            backTransition?.isRunning != true, let navigator,
            navigator.pages(in: navigator.selection).isEmpty,
            !navigator.isPlayerOpen, navigator.backTarget(for: navigator.selection) != nil
        else { return false }
        let velocity = pan.velocity(in: view)
        return velocity.x > abs(velocity.y)
    }

    /// The timeline keeps taps and vertical scrubs; its horizontal drag must not block a cross-tab Back gesture.
    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
    ) -> Bool {
        // Row taps must fail when Back begins; only the timeline's continuous drag can run beside it.
        (gestureRecognizer === edgePan || other === edgePan) && other is UIPanGestureRecognizer
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer, shouldBeRequiredToFailBy other: UIGestureRecognizer
    ) -> Bool {
        gestureRecognizer === edgePan
    }

    private func navigationController(in controller: UIViewController?) -> UINavigationController? {
        if let navigation = controller as? UINavigationController { return navigation }
        for child in controller?.children ?? [] {
            if let navigation = navigationController(in: child) { return navigation }
        }
        return nil
    }

    @objc private func dragBack(_ pan: UIScreenEdgePanGestureRecognizer) {
        guard let navigator, let backTransition else { return }
        switch pan.state {
        case .began:
            let bottom = view.bounds.maxY - tabBar.frame.minY
            _ = backTransition.begin(bottom: bottom) { navigator.previewBack(from: navigator.selection) }
        case .changed:
            backTransition.update(distance: pan.translation(in: view).x)
        case .ended, .cancelled, .failed:
            backTransition.finish(
                velocity: pan.velocity(in: view).x, cancelled: pan.state != .ended,
                reduceMotion: UIAccessibility.isReduceMotionEnabled)
            // The next Back swipe may start while the page settles, so the gestures follow the new place now.
            view.setNeedsLayout()
        default: break
        }
    }

    /// Marks the views inside the bar for a new measure. The bar keeps its own size: a new size of the bar marks its
    /// container for layout, and that layout gives the bar the full screen width.
    private func invalidateLayout(inside view: UIView) {
        for child in view.subviews {
            child.invalidateIntrinsicContentSize()
            child.setNeedsLayout()
            invalidateLayout(inside: child)
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        configureBackGesture()
        var frame = tabBar.frame
        // UIKit removes the home-indicator inset under a keyboard.
        // Playback controls must keep the resting bar position.
        if keyboardVisible, let restingFrame {
            frame.origin.y = restingFrame.minY
            frame.size.height = restingFrame.height
        } else {
            restingFrame = frame
        }
        frame.origin.x = side == .left ? reservedWidth : 0
        frame.size.width = max(0, view.bounds.width - reservedWidth)
        if remeasuresLabels || remeasuresAtFinalFrame {
            // After a keyboard the labels can stay truncated: the resting frame is unchanged, so UIKit does not lay
            // the items out again. A changed width forces a new layout of each item.
            let first = remeasuresLabels
            remeasuresLabels = false
            remeasuresAtFinalFrame = false
            invalidateLayout(inside: tabBar)
            tabBar.frame = frame.insetBy(dx: 1, dy: 0)
            tabBar.layoutIfNeeded()
            tabBar.frame = frame
            if first {
                // The container of the bar can still lay out after this pass and give the bar the full screen width,
                // which puts the Search tab under the mini player. The next pass puts the bar back beside it and
                // measures the labels at that narrow width, where a label measured at full width would truncate.
                Task { @MainActor [weak self] in
                    self?.remeasuresAtFinalFrame = true
                    self?.view.setNeedsLayout()
                }
            }
        }
        tabBar.frame = frame
        playerHost?.view.frame = view.bounds
        let top = view.window?.safeAreaInsets.top ?? view.safeAreaInsets.top
        let bottom = max(0, view.bounds.maxY - tabBar.convert(tabBar.bounds, to: view).minY)
        if playerLayout.top != top || playerLayout.bottom != bottom {
            Task { @MainActor [layout = playerLayout] in
                layout.top = top
                layout.bottom = bottom
            }
        }
        // UIKit nests the native bar inside a container. The player belongs below that whole container.
        var chrome: UIView = tabBar
        while let parent = chrome.superview, parent !== view { chrome = parent }
        if chrome.superview === view {
            view.bringSubviewToFront(chrome)
            if let playerHost { view.insertSubview(playerHost.view, belowSubview: chrome) }
        }
        // SwiftUI's display reader measures in global coordinates, so the bar reports its window coordinates.
        let bar = tabBar.convert(tabBar.bounds, to: nil)
        // The bar frame also holds the safe-area gap, so its height is not the capsule's. The pill height is the
        // fixed capsule height; only the position and width come from the bar.
        let content = CGRect(x: bar.minX, y: bar.minY, width: bar.width, height: TabRow.height)
        if reportedFrame != content, let onLayout {
            reportedFrame = content
            Task { @MainActor in onLayout(content) }
        }
    }
}

extension Place {
    /// Search is a `UISearchTab` that activates search. iOS 27 draws only such a tab apart from the other tabs, in
    /// its own circle at the trailing end of the bar; without the flag the tab stays in the capsule.
    @MainActor func tab(_ host: UIViewController) -> UITab {
        let tab: UITab
        if self == .search {
            let search = UISearchTab { _ in host }
            search.automaticallyActivatesSearch = true
            tab = search
        } else {
            tab = UITab(title: title, image: image, identifier: rawValue) { _ in host }
        }
        // UITab declares no accessibility identifier. In a Release build a protocol cast of the tab is a forced
        // cast that stops the app at launch. A run-time check of the setter is safe in every build.
        let identifier = #selector(setter: UIAccessibilityIdentification.accessibilityIdentifier)
        if tab.responds(to: identifier) { tab.perform(identifier, with: "tab-\(rawValue)") }
        return tab
    }

    /// Chronology draws the specimen lifelines (specimen.js `ICON.chronology`). It is a template image, so the tab
    /// bar tints it as it tints a system symbol.
    var image: UIImage? {
        switch self {
        case .library: UIImage(systemName: "books.vertical")
        case .chronology: UIImage(named: "Chronology")
        case .search: UIImage(systemName: "magnifyingglass")
        }
    }
}

/// Playback controls align with the native tab bar; their safe-area gap keeps the square cover clear.
enum TabRow {
    // The iOS 27 floating capsule is 62 points high. Its content guide is 49 points high.
    nonisolated static let height: CGFloat = 62

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
        NavigationStack(
            path: Binding(
                get: { navigator.pages(in: place) },
                set: { navigator.setPages($0, in: place) })
        ) {
            root
                .modifier(PlaceInsets())
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
            // The bar shows no title (ADR 0023). The navigation title still names the back button of the next page.
            .toolbar(removing: .title)
            .contentMargins(.trailing, beside, for: .scrollIndicators)
    }
}

/// Tells the listener once that the back button opens a list of the pages behind it.
struct BackTip: Tip {
    var title: Text { Text("Hold Back to Go Further") }
    var message: Text? { Text("Touch and hold the back button to jump to any page behind this one.") }
    var image: Image? { Image(systemName: "chevron.backward") }
    var options: [any TipOption] { [Tips.MaxDisplayCount(1)] }
}

/// The row of the tip in a list. The row takes no ground of its own, and the tip takes the ground of a row, so
/// that it does not draw as TipKit's grey card on the ground of the page.
struct BackTipRow: View {
    @Environment(\.showsBackTip) private var showsBackTip

    var body: some View {
        if showsBackTip {
            TipView(BackTip())
                .tipViewStyle(PageTipStyle())
                .tipBackground(Palette.backgroundRow.color)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        }
    }
}

/// A tip in the type and colours of a page row: the title in ink, the message one level quieter, the mark in
/// the tint of the app.
struct PageTipStyle: TipViewStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.m.points) {
            configuration.image?
                .typeStyle(.headline)
                .foregroundStyle(Palette.tint)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Layout.rowLineGap) {
                configuration.title?
                    .typeStyle(.headline)
                    .foregroundStyle(Palette.textPrimary)
                configuration.message?
                    .typeStyle(.subheadline)
                    .foregroundStyle(Palette.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                configuration.tip.invalidate(reason: .tipClosed)
            } label: {
                Image(systemName: "xmark")
                    .typeStyle(.footnote)
                    .foregroundStyle(Palette.textTertiary)
            }
            .buttonStyle(FlatPress())
            .accessibilityLabel("Close Tip")
            .accessibilityIdentifier("back-tip-close")
        }
        // The row insets of the list give the page edges; the tip adds only its height.
        .padding(.vertical, Space.l.points)
        .accessibilityElement(children: .contain)
    }
}

extension EnvironmentValues {
    @Entry var placeBackTransition: PlaceBackTransition? = nil
    /// True on a page that a pages menu sits behind, which is where the tip makes sense.
    @Entry var showsBackTip = false
    /// The height above the bottom safe area that the tab row takes, with its gap.
    @Entry var tabRowClearance = TabRow.clearance(safeArea: 0)
}
