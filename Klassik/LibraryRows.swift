import Foundation
import Observation

/// A row of the Library place. Playlists will be a third one (CONTEXT.md: Library).
enum LibraryRow: String, CaseIterable, Identifiable, Sendable {
    case composers
    case favourites

    var id: Self { self }

    var title: String {
        switch self {
        case .composers: "Composers"
        case .favourites: "Favourites"
        }
    }
}

/// The order of the Library rows. The listener sets it, and it stays on the device.
@MainActor @Observable
final class LibraryRows {
    /// Every row once. A row that the stored order lacks, such as a newer one, comes last.
    private(set) var rows: [LibraryRow]

    private let defaults: UserDefaults
    static let key = "library.rows"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        rows = Self.order(stored: defaults.stringArray(forKey: Self.key) ?? [])
    }

    /// Moves rows as `onMove` of a list says: `destination` counts in the list before the move.
    func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        let moved = source.map { rows[$0] }
        let before = source.filter { $0 < destination }.count
        for index in source.sorted(by: >) { rows.remove(at: index) }
        rows.insert(contentsOf: moved, at: destination - before)
        defaults.set(rows.map(\.rawValue), forKey: Self.key)
    }

    func reset() {
        rows = LibraryRow.allCases
        defaults.removeObject(forKey: Self.key)
    }

    /// The rows named in `stored`, then the others in their default order. Unknown names and repeats fall away.
    static func order(stored: [String]) -> [LibraryRow] {
        var result: [LibraryRow] = []
        for row in stored.compactMap(LibraryRow.init(rawValue:)) + LibraryRow.allCases where !result.contains(row) {
            result.append(row)
        }
        return result
    }
}
