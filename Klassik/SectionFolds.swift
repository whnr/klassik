import Foundation

/// The result sections that the user folded away. A section is folded by its title key, so a new
/// search keeps the choice; the set lives as long as the results view.
struct SectionFolds: Equatable {
    private var folded: Set<String> = []

    func isFolded(_ section: String) -> Bool { folded.contains(section) }

    mutating func toggle(_ section: String) {
        if !folded.insert(section).inserted { folded.remove(section) }
    }
}
