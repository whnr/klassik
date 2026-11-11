import SwiftUI
import TipKit
import UIKit

/// The four places in a system tab bar, each with its own stack.
struct PlacesView: View {
    /// Owned here, so that a sign-out takes the stacks away with the places.
    @State private var navigator = AppNavigator()

    var body: some View {
        TabView(selection: Binding(get: { navigator.selection }, set: { navigator.select($0) })) {
            Tab(Place.library.title, systemImage: "books.vertical", value: Place.library) {
                PlaceStack(place: .library) { LibraryView() }
            }
            Tab(Place.chronology.title, systemImage: "calendar", value: Place.chronology) {
                PlaceStack(place: .chronology) { WorkTimelineView() }
            }
            Tab(value: Place.search, role: .search) {
                PlaceStack(place: .search) { SearchView() }
            }
            Tab(Place.settings.title, systemImage: "gearshape", value: Place.settings) {
                PlaceStack(place: .settings) { SettingsView() }
            }
        }
        .environment(navigator)
    }
}

/// The `NavigationStack` of one place. Its pages are the stack of the navigator. The back button of a page is the
/// system one. A root has none, so a root that the listener reached from another place gets an arrow and an
/// edge swipe back to that place (ADR 0038).
struct PlaceStack<Root: View>: View {
    @Environment(AppNavigator.self) private var navigator
    @Environment(AppModel.self) private var model
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
                .gesture(edgeSwipe)
                .toolbar {
                    if let target {
                        ToolbarItem(placement: .topBarLeading) {
                            let name = target.page?.backTitle(in: model.library) ?? target.place.title
                            Button {
                                navigator.goBack(from: place)
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
                    PageView(page: page)
                        .environment(\.showsBackTip, (navigator.pages(in: place).firstIndex(of: page) ?? 0) >= 1)
                }
        }
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
    /// True on a page that a pages menu sits behind, which is where the tip makes sense.
    @Entry var showsBackTip = false
}
