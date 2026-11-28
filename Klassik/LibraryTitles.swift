import Foundation

/// The title of a row of the Library. Each natural title is one whole string of the catalog; no title is built from
/// words. A combination without a natural title uses the one format `Kind, qualifier`, whose order each language owns.
enum LibraryTitles {
    /// The title in `language`, or in the app language.
    static func title(of row: LibraryRowSetup, in language: AppLanguage? = nil) -> String {
        let parts = plan(of: row, in: language)
        guard let qualifier = parts.qualifier else { return parts.head }
        return Localization.shared.string("\(parts.head), \(qualifier)", in: language)
    }

    /// Whether the title already says the sort, so that the subtitle does not repeat it.
    static func namesSort(of row: LibraryRowSetup) -> Bool { plan(of: row, in: nil).namesSort }

    /// The sort in the middle of a line. Code never changes letter case, so it has its own text.
    static func sortWord(_ sort: LibrarySort, in language: AppLanguage? = nil) -> String {
        // swift-format-ignore: AlwaysUseLowerCamelCase
        let L = reader(language)
        return switch sort {
        case .random: L("random")
        case .best: L("best known")
        case .newest: L("newest first")
        case .heard: L("last heard first")
        case .az: L("A to Z")
        }
    }

    // MARK: Plan

    private struct Plan {
        var head: String
        /// The one slot of the fallback format: a term, "filtered" or a sort.
        var qualifier: String?
        var namesSort: Bool
    }

    private static func plan(of row: LibraryRowSetup, in language: AppLanguage?) -> Plan {
        // swift-format-ignore: AlwaysUseLowerCamelCase
        let L = reader(language)
        let terms = row.conditions.flatMap { $0 }
        let sortable = ![.pick, .saved, .links].contains(row.kind)
        let named = sortable && row.sort != LibraryRowSetup(kind: row.kind).sort
        let natural = named ? naturalTitle(kind: row.kind, sort: row.sort, L) : nil
        var plan = Plan(head: natural ?? kindTitle(row.kind, L), qualifier: nil, namesSort: natural != nil)
        if row.kind == .saved, !terms.isEmpty {
            let language = language ?? Localization.shared.language
            plan.qualifier = row.filterSummary(in: language)
        } else if let first = terms.first {
            plan.qualifier = terms.count == 1 ? first.name : L("filtered")
        } else if named, natural == nil {
            plan.qualifier = sortWord(row.sort, in: language)
            plan.namesSort = true
        }
        return plan
    }

    private static func reader(_ language: AppLanguage?) -> (String.LocalizationValue) -> String {
        { Localization.shared.string($0, in: language) }
    }

    /// The titles that read well as one phrase. Tag values never take part.
    // swift-format-ignore: AlwaysUseLowerCamelCase
    private static func naturalTitle(
        kind: LibraryRowKind, sort: LibrarySort, _ L: (String.LocalizationValue) -> String
    ) -> String? {
        switch (kind, sort) {
        case (.composers, .best): L("Best known composers")
        case (.composers, .az): L("Composers A to Z")
        case (.performers, .best): L("Best known performers")
        case (.performers, .az): L("Performers A to Z")
        case (.works, .az): L("Works A to Z")
        case (.works, .newest): L("Newest works")
        case (.recordings, .az): L("Recordings A to Z")
        case (.recordings, .newest): L("Newest recordings")
        case (.albums, .random): L("Random albums")
        case (.albums, .az): L("Albums A to Z")
        case (.favourites, .az): L("Favourites A to Z")
        case (.favourites, .newest): L("Newest favourites")
        default: nil
        }
    }

    // swift-format-ignore: AlwaysUseLowerCamelCase
    private static func kindTitle(_ kind: LibraryRowKind, _ L: (String.LocalizationValue) -> String) -> String {
        switch kind {
        case .composers: L("Composers")
        case .performers: L("Performers")
        case .works: L("Works")
        case .recordings: L("Recordings")
        case .albums: L("Albums")
        case .favourites: L("Favourites")
        case .added: L("Recently added")
        case .heard: L("Recently heard")
        case .pick: L("Daily pick")
        case .saved: L("Saved search")
        case .links: L("Link list")
        }
    }
}
