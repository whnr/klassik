import Foundation

/// The tagged works in the order they were composed, in sections by period.
/// A work without a date sits inside its composer's lifetime and is marked approximate.
struct Timeline: Sendable {
    enum Period: Int, CaseIterable, Comparable, Sendable {
        case early, baroque, classical, romantic, modern, contemporary

        var title: String {
            switch self {
            case .early: "Early Music"
            case .baroque: "Baroque"
            case .classical: "Classical"
            case .romantic: "Romantic"
            case .modern: "Modern"
            case .contemporary: "Contemporary"
            }
        }

        /// The first year of each period; the conventional boundaries of music history.
        var start: Int? { [nil, 1600, 1750, 1820, 1910, 1975][rawValue] }

        var years: String {
            let end = Period(rawValue: rawValue + 1)?.start
            switch (start, end) {
            case (nil, let end?): return "before \(end)"
            case (let start?, nil): return "since \(start)"
            case (let start?, let end?): return "\(start)–\(end)"
            default: return ""
            }
        }

        static func of(year: Int) -> Period {
            allCases.last { ($0.start ?? .min) <= year } ?? .early
        }

        /// A composer belongs to the period of the year they turned 35, or of their death if it came first.
        static func of(born: Int?, died: Int?) -> Period? {
            switch (born, died) {
            case (let born?, let died?): of(year: min(born + 35, died))
            case (let born?, nil): of(year: born + 35)
            case (nil, let died?): of(year: died)
            default: nil
            }
        }

        static func < (a: Period, b: Period) -> Bool { a.rawValue < b.rawValue }
    }

    struct Entry: Identifiable, Sendable {
        var work: WorkIndex.Work
        /// The composition years, or the composer's lifetime if the work has no date.
        var span: YearSpan
        var isApproximate: Bool
        var id: String { work.id }

        /// Where the entry sorts: the composition year, or the middle of the lifetime.
        var sortYear: Int { isApproximate ? (span.start + span.end) / 2 : span.start }
    }

    struct Section: Identifiable, Sendable {
        var period: Period
        var entries: [Entry]
        var id: Int { period.rawValue }
    }

    var sections: [Section] = []
    /// Works that have no date and whose composer has no known dates.
    var undated: [WorkIndex.Work] = []

    init() {}

    init(
        index: WorkIndex, composed: (WorkIndex.Work) -> YearSpan?,
        lifetime: (String) -> (born: Int?, died: Int?)?
    ) {
        var byPeriod: [Period: [Entry]] = [:]
        for composer in index.composers {
            let works = composer.works.filter(\.isTagged)
            let dates = lifetime(composer.name)
            let dated = works.compactMap { work in composed(work).map { (work, $0) } }
            // Without dates of the composer, the median work year places them.
            let period =
                Period.of(born: dates?.born, died: dates?.died)
                ?? dated.map(\.1.start).sorted().dropFirst(dated.count / 2).first.map { Period.of(year: $0) }
            guard let period else {
                undated += works
                continue
            }
            let band = dates.flatMap { dates in
                dates.born.flatMap { born in dates.died.map { YearSpan(born, $0) } }
            }
            for work in works {
                if let span = composed(work) {
                    byPeriod[period, default: []].append(Entry(work: work, span: span, isApproximate: false))
                } else if let band {
                    byPeriod[period, default: []].append(Entry(work: work, span: band, isApproximate: true))
                } else {
                    undated.append(work)
                }
            }
        }
        sections = byPeriod.keys.sorted().map { period in
            Section(
                period: period,
                entries: byPeriod[period, default: []].sorted {
                    ($0.sortYear, $0.isApproximate ? 1 : 0, $0.work.composer, $0.work.title)
                        < ($1.sortYear, $1.isApproximate ? 1 : 0, $1.work.composer, $1.work.title)
                })
        }
        undated.sort { ($0.composer, $0.title) < ($1.composer, $1.title) }
    }
}
