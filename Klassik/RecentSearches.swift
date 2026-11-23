import Foundation
import Observation

/// One past search: its text and its conditions. Recent searches stay in the device file and never go to
/// the server.
struct RecentSearch: Codable, Equatable, Identifiable, Sendable {
    /// A search term of a condition, kept by its kind and name so that the file does not depend on the filter sheet.
    struct Term: Codable, Hashable, Sendable {
        enum Kind: String, Codable, Sendable {
            case genre, composer, conductor, performer

            /// The name of the kind, as a recent search reads it: "Composer Antonín Dvořák".
            var label: String {
                switch self {
                case .genre: "Genre"
                case .composer: "Composer"
                case .conductor: "Conductor"
                case .performer: "Performer"
                }
            }
        }

        var kind: Kind
        var name: String
    }

    var id = UUID()
    var text: String
    /// The terms in one condition join with "or"; the conditions join with "and".
    var conditions: [[Term]]

    var isEmpty: Bool { text.isEmpty && conditions.isEmpty }

    /// The conditions as they work: "Composer Antonín Dvořák or Composer Johannes Brahms and Genre Symphony".
    var conditionLine: String {
        conditions.map { terms in terms.map { "\($0.kind.label) \($0.name)" }.joined(separator: " or ") }
            .joined(separator: " and ")
    }

    /// Two entries with the same text and conditions are the same search.
    fileprivate var key: String {
        "\(text.lowercased())|\(conditions.map { terms in terms.map { "\($0.kind.rawValue):\($0.name)" } })"
    }
}

extension RecentSearch.Term {
    init(_ term: Search.Term) {
        switch term.scope {
        case .genres: self.init(kind: .genre, name: term.name)
        case .composers: self.init(kind: .composer, name: term.name)
        case .conductors: self.init(kind: .conductor, name: term.name)
        case .performers: self.init(kind: .performer, name: term.name)
        }
    }

    /// The term as the filter sheet holds it.
    var searchTerm: Search.Term {
        switch kind {
        case .genre: Search.Term(scope: .genres, name: name)
        case .composer: Search.Term(scope: .composers, name: name)
        case .conductor: Search.Term(scope: .conductors, name: name)
        case .performer: Search.Term(scope: .performers, name: name)
        }
    }
}

extension RecentSearch {
    /// The conditions of the filter sheet as a recent search keeps them.
    static func terms(of conditions: [Search.Condition]) -> [[Term]] {
        conditions.map { $0.terms.map(Term.init) }
    }

    /// The conditions as the filter sheet holds them, for a restore.
    var searchConditions: [Search.Condition] {
        conditions.map { Search.Condition(terms: $0.map(\.searchTerm)) }
    }
}

/// The recent searches of the listener, newest first, and the search session that the Search page has open.
/// One session is one entry: each commit replaces the entry of the session, so the list does not fill
/// with fragments.
@MainActor @Observable
final class RecentSearches {
    /// The list keeps no more entries than this; the oldest go first.
    nonisolated static let limit = 42

    private let file: ListenerFile
    /// The entry of the open search session. Nil until the session commits for the first time.
    private(set) var session: UUID?

    init(file: ListenerFile) {
        self.file = file
    }

    convenience init(store: DeviceStore?) {
        self.init(file: ListenerFile(store: store))
    }

    var entries: [RecentSearch] { file.data.recentSearches }

    /// Keeps the search of the open session as the newest entry. A search without text and conditions keeps
    /// nothing.
    func commit(text: String, conditions: [[RecentSearch.Term]] = []) {
        let entry = RecentSearch(
            id: session ?? UUID(), text: text.trimmingCharacters(in: .whitespacesAndNewlines),
            conditions: conditions.filter { !$0.isEmpty })
        guard !entry.isEmpty else { return }
        session = entry.id
        write { Self.committing(entry, into: $0) }
    }

    /// The next commit starts a new entry.
    func endSession() {
        session = nil
    }

    /// A tap on an entry continues its session: the entry comes to the top, and later changes replace it.
    func restore(_ entry: RecentSearch) {
        session = entry.id
        commit(text: entry.text, conditions: entry.conditions)
    }

    func clear() {
        write { _ in [] }
    }

    /// Puts the entry first and removes the earlier entry of its session and any entry of the same search.
    nonisolated static func committing(_ entry: RecentSearch, into list: [RecentSearch]) -> [RecentSearch] {
        let others = list.filter { $0.id != entry.id && $0.key != entry.key }
        return Array(([entry] + others).prefix(limit))
    }

    /// A device file that refuses the write keeps the old list; the Search page has no place for an error.
    private func write(_ change: ([RecentSearch]) -> [RecentSearch]) {
        var changed = file.data
        changed.recentSearches = change(changed.recentSearches)
        try? file.save(changed)
    }
}
