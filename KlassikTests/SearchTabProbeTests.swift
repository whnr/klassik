import Testing
import UIKit

@testable import Klassik

/// Temporary probe: prints how UIKit lays out a search tab in the simulator.
@MainActor
struct SearchTabProbeTests {
    private func describe(_ view: UIView, depth: Int = 0) -> String {
        let frame = view.convert(view.bounds, to: nil)
        var line = String(repeating: "  ", count: depth) + "\(type(of: view)) \(frame.integral)"
        if let label = view.accessibilityLabel { line += " '\(label)'" }
        return ([line] + view.subviews.map { describe($0, depth: depth + 1) }).joined(separator: "\n")
    }

    private func probe(_ name: String, configure: (UITabBarController, UISearchTab) -> Void) {
        let controller = UITabBarController()
        let search = UISearchTab { _ in UINavigationController(rootViewController: UIViewController()) }
        controller.tabs = [
            UITab(title: "Library", image: UIImage(systemName: "books.vertical"), identifier: "library") { _ in
                UIViewController()
            },
            UITab(title: "Chronology", image: UIImage(systemName: "calendar"), identifier: "chronology") { _ in
                UIViewController()
            },
            search,
        ]
        configure(controller, search)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()
        controller.tabBar.layoutIfNeeded()
        var root: UIView = controller.tabBar
        while let parent = root.superview, parent !== controller.view { root = parent }
        print("PROBE \(name)\n" + describe(root))
        window.isHidden = true
    }

    @Test func printsTheSearchTabLayout() {
        probe("plain") { _, _ in }
        probe("search-controller") { _, search in
            let navigation = search.viewController as? UINavigationController
            navigation?.topViewController?.navigationItem.searchController = UISearchController()
        }
        probe("activates") { _, search in search.automaticallyActivatesSearch = true }
        probe("search-selected") { controller, search in controller.selectedTab = search }
        probe("legacy-system-item") { controller, _ in
            let items = [UIViewController(), UIViewController(), UIViewController()]
            items[0].tabBarItem = UITabBarItem(title: "Library", image: UIImage(systemName: "books.vertical"), tag: 0)
            items[1].tabBarItem = UITabBarItem(title: "Chronology", image: UIImage(systemName: "calendar"), tag: 1)
            items[2].tabBarItem = UITabBarItem(tabBarSystemItem: .search, tag: 2)
            controller.viewControllers = items
        }
    }
}
