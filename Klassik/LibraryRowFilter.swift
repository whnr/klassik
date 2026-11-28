import Foundation

extension LibraryRowSetup {
    var searchConditions: [Search.Condition] {
        conditions.map { Search.Condition(terms: $0.map(\.searchTerm)) }
    }

    /// Tag names stay as tagged. The language supplies the alternatives' joining word.
    var filterSummary: String { filterSummary(in: Localization.shared.language) }

    func filterSummary(in language: AppLanguage) -> String {
        let locale = Localization.shared.locale(for: language)
        return conditions.map { $0.map(\.name).formatted(.list(type: .or).locale(locale)) }
            .reduce("") { $0.isEmpty ? $1 : Localization.shared.string("\($0), \($1)", in: language) }
    }
}
