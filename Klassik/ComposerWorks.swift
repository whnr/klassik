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

    /// The rows A to Z. With chips on, a work shows when it carries any of them ("or"), and a set keeps
    /// only the works that do.
    func rows(filter chips: Set<String> = []) -> [Row] {
        let shown = chips.isEmpty ? works : works.filter { !Self.genres(of: $0).isDisjoint(with: chips) }
        var rows: [Row] = []
        var sets: [String: [WorkIndex.Work]] = [:]
        for work in shown {
            if work.isTagged, let set = work.grouping {
                sets[set, default: []].append(work)
            } else {
                rows.append(.work(work))
            }
        }
        for (name, works) in sets {
            // A set of one work is a work: a row that opens to a single line says nothing.
            rows.append(works.count == 1 ? .work(works[0]) : .set(name: name, works: Self.sorted(works)))
        }
        return rows.sorted { Self.before($0.title, $1.title) }
    }

    static func sorted(_ works: [WorkIndex.Work]) -> [WorkIndex.Work] {
        works.sorted { before($0.title, $1.title) }
    }

    /// Natural order, so "Op. 6" comes before "Op. 17".
    private static func before(_ a: String, _ b: String) -> Bool {
        a.localizedStandardCompare(b) == .orderedAscending
    }
}
