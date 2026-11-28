import Foundation

extension LibraryRowSetup {
    var searchConditions: [Search.Condition] {
        conditions.map { Search.Condition(terms: $0.map(\.searchTerm)) }
    }

    /// Tag names stay as tagged. The app language supplies the alternatives' joining word.
    var filterSummary: String { filterSummary(locale: Localization.shared.locale) }

    func filterSummary(locale: Locale) -> String {
        conditions.map { $0.map(\.name).formatted(.list(type: .or).locale(locale)) }
            .reduce("") { $0.isEmpty ? $1 : L("\($0), \($1)") }
    }
}
