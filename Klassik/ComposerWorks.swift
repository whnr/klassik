import Foundation

/// The Works tab of a composer page: rows A to Z, sets folded into one row, genre chips (ADR 0017).
struct ComposerWorks: Sendable {
    /// One row of the list: a work, or the works of one set.
    enum Row: Identifiable, Sendable {
        case work(WorkIndex.Work)
        case set(name: String, works: [WorkIndex.Work])

        var id: String {
            switch self {
            case .work(let work): "work:" + work.id
            case .set(let name, _): "set:" + name
            }
        }

        var title: String {
            switch self {
            case .work(let work): work.title
            case .set(let name, _): name
            }
        }

        var works: [WorkIndex.Work] {
            switch self {
            case .work(let work): [work]
            case .set(_, let works): works
            }
        }
    }

    /// The user default that lists partial works apart. Flo's setting is on by default.
    static let separatesPartialKey = "composerWorks.separatePartial"

    let works: [WorkIndex.Work]

    init(_ composer: WorkIndex.Composer) {
        works = composer.works
    }

    /// The genres of a work: every genre tag of every track of every recording.
    static func genres(of work: WorkIndex.Work) -> Set<String> {
        Set(work.recordings.flatMap(\.songs).flatMap(\.allGenres))
    }

    /// The chips: genres that some, but not all, works carry. A genre that every work carries tells nothing.
    /// The most common genre comes first. Klassik reads genres as plain labels and gives no meaning to their order.
    var genres: [String] {
        let sets = works.map(Self.genres(of:))
        var counts: [String: Int] = [:]
        for genre in sets.joined() { counts[genre, default: 0] += 1 }
        return counts.filter { $0.value < works.count }
            .sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
            .map(\.key)
    }

    /// A partial work has no recording that holds the whole work.
    static func isPartial(_ work: WorkIndex.Work) -> Bool {
        !work.recordings.isEmpty && work.recordings.allSatisfy(\.isPartial)
    }

    /// The rows A to Z. With chips on, a work shows when it carries any of them ("or"), and a set keeps
    /// only the works that do. Sets stay in Works because their completeness is unknown.
    /// `partial` nil keeps every row, true keeps only partial works, false keeps the rest and every set.
    func rows(filter chips: Set<String> = [], partial: Bool? = nil) -> [Row] {
        let shown = works.filter { work in
            chips.isEmpty || !Self.genres(of: work).isDisjoint(with: chips)
        }
        var rows: [Row] = []
        var sets: [String: [WorkIndex.Work]] = [:]
        for work in shown {
            if work.isTagged, let set = work.grouping {
                sets[set, default: []].append(work)
            } else {
                rows.append(.work(work))
            }
        }
        for (name, works) in sets.sorted(by: { Self.before($0.key, $1.key) }) {
            // A set of one work is a work: a row that opens to a single line says nothing.
            rows.append(works.count == 1 ? .work(works[0]) : .set(name: name, works: Self.sorted(works)))
        }
        return rows.filter { row in
            guard let partial else { return true }
            switch row {
            case .set: return !partial
            case .work(let work): return partial == Self.isPartial(work)
            }
        }.sorted { Self.before($0.title, $1.title) }
    }

    /// One section of the Works tab under its own heading.
    struct Part: Identifiable, Sendable {
        var title: String
        var rows: [Row]
        var id: String { title }

        func setID(named name: String) -> SetID {
            SetID(section: id, name: name)
        }
    }

    /// The section and name identify an open set.
    struct SetID: Hashable, Sendable {
        let section: String
        let name: String
    }

    /// The sections of the Works tab. With `separatingPartial`, works that no recording holds whole follow under
    /// "Partial works". An empty section does not show, unless no work shows at all.
    func parts(filter chips: Set<String> = [], separatingPartial: Bool) -> [Part] {
        guard separatingPartial else { return [Part(title: "Works", rows: rows(filter: chips))] }
        let parts = [
            Part(title: "Works", rows: rows(filter: chips, partial: false)),
            Part(title: "Partial works", rows: rows(filter: chips, partial: true)),
        ]
        let shown = parts.filter { !$0.rows.isEmpty }
        return shown.isEmpty ? [parts[0]] : shown
    }

    static func sorted(_ works: [WorkIndex.Work]) -> [WorkIndex.Work] {
        works.sorted { before($0.title, $1.title) }
    }

    /// Natural order, so "Op. 6" comes before "Op. 17".
    private static func before(_ a: String, _ b: String) -> Bool {
        a.localizedStandardCompare(b) == .orderedAscending
    }
}
