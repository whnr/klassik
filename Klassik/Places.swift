import SwiftUI
import TipKit

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

/// The `NavigationStack` of one place. Its pages are the stack of the navigator, so that a link to a page
/// that the stack holds goes back to it. The back button of a page is the system one.
struct PlaceStack<Root: View>: View {
    @Environment(AppNavigator.self) private var navigator
    @Environment(AppModel.self) private var model
    let place: Place
    @ViewBuilder let root: Root

    var body: some View {
        NavigationStack(
            path: Binding(
                get: { navigator.pages(in: place) },
                set: { navigator.setPages($0, in: place) })
        ) {
            root
                .toolbar {
                    // The root of a stack has no system back button. The arrow here goes to the page that
                    // the listener came from.
                    if let target = navigator.backTarget(for: place) {
                        ToolbarItem(placement: .topBarLeading) {
                            let name = target.page?.backTitle(in: model.library) ?? target.place.title
                            Button {
                                navigator.goBack(from: place)
                            } label: {
                                // iOS 27 drops the title of a `Label` in a toolbar item, so the text is drawn here.
                                HStack(spacing: Space.xs.points) {
                                    Image(systemName: "chevron.backward")
                                    Text(name)
                                        .lineLimit(1)
                                }
                            }
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
