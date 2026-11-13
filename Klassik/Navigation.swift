import Foundation
import Observation

/// One of the top-level parts of the app (CONTEXT.md: Place).
enum Place: String, CaseIterable, Hashable, Sendable {
    case library
    case chronology
    case search

    var title: String {
        switch self {
        case .library: "Library"
        case .chronology: "Chronology"
        case .search: "Search"
        }
    }
}

/// Which place shows, the stack of each place (CONTEXT.md: Stack), and where the back arrow of a place goes.
@MainActor @Observable
final class Navigator<Page: Hashable> {
    /// The place and page that the listener left to open another place.
    struct Origin: Equatable {
        var place: Place
        /// Nil when the listener left the root of the place.
        var page: Page?
    }

    private(set) var selection = Place.library
    private var stacks: [Place: [Page]] = [:]
    private var origins: [Place: Origin] = [:]

    func pages(in place: Place) -> [Page] {
        stacks[place] ?? []
    }

    /// Pushes a page. A page that the stack holds already is pushed again: Back is one step back.
    func open(_ page: Page, in place: Place) {
        stacks[place, default: []].append(page)
    }

    /// The player follows the queue in place. A listener who browses another page keeps that page (ADR 0015).
    func followPlayback(from old: Page?, to new: Page?) {
        guard let old, let new, old != new, var pages = stacks[selection], pages.last == old else { return }
        pages[pages.count - 1] = new
        stacks[selection] = pages
    }

    /// Takes the stack from the system after a push or a pop.
    func setPages(_ pages: [Page], in place: Place) {
        stacks[place] = pages
    }

    /// Shows a place. It remembers the page that the listener leaves, for the back arrow of the new place.
    func select(_ place: Place) {
        guard place != selection else { return }
        origins[place] = Origin(place: selection, page: pages(in: selection).last)
        selection = place
    }

    /// Where the back arrow of a place goes: the page it was opened from, else Library. Library at launch has
    /// no place behind it, so it has no arrow (ADR 0038).
    func backTarget(for place: Place) -> Origin? {
        guard place != .library else { return origins[place] }
        return origins[place] ?? Origin(place: .library, page: nil)
    }

    /// Leaves the page on top of the place that shows, or goes back to the place before from its root.
    func back() {
        if pages(in: selection).isEmpty {
            goBack(from: selection)
        } else {
            stacks[selection]?.removeLast()
        }
    }

    /// Returns to the page that the place was opened from.
    func goBack(from place: Place) {
        guard let target = backTarget(for: place) else { return }
        origins[place] = nil
        selection = target.place
    }
}
