import CoreGraphics
import Foundation
import Observation

/// The Chronology place: every composer with life dates as a line in birth order, and one
/// composer among their contemporaries. Inputs are the work index and the person facts. Views draw its output.
struct Chronology: Sendable {
    /// A period of music history, drawn as a band in the overview.
    struct Period: Equatable, Sendable {
        var name: String
        var start: Int
        var end: Int
    }

    /// The conventional boundaries of music history, as the specimen draws them.
    static let periods = [
        Period(name: "Renaissance", start: 1400, end: 1600),
        Period(name: "Baroque", start: 1600, end: 1750),
        Period(name: "Classical", start: 1750, end: 1820),
        Period(name: "Romantic", start: 1820, end: 1910),
        Period(name: "Modern", start: 1910, end: 2030),
    ]

    /// The years before and after the active years of the focus composer.
    static let buffer = 10

    struct Work: Identifiable, Sendable {
        var work: WorkIndex.Work
        /// The composition year. Nil when no source gives one: the work is never placed on a guessed year.
        var year: Int?
        var id: String { work.id }
    }

    /// A composer with life dates from Wikidata. A composer without a birth year stays off the chart.
    struct Composer: Identifiable, Equatable, Sendable {
        var name: String
        var born: Int
        var died: Int?
        /// The work period start (P2031).
        var activeFrom: Int?
        /// Dated works by year and title, then undated works by title.
        var works: [Work]
        var id: String { name }

        static func == (a: Composer, b: Composer) -> Bool { a.name == b.name }

        /// The last year of the line: the death, else the current year.
        func end(now: Int) -> Int { max(died ?? now, born) }

        /// From the work period start to the death. Without a work period start, the whole life.
        func activeYears(now: Int) -> ClosedRange<Int> {
            min(activeFrom ?? born, end(now: now))...end(now: now)
        }

        /// The active years with the buffer before and after. Without a work period start, the whole life with
        /// no buffer.
        func window(now: Int) -> ClosedRange<Int> {
            let active = activeYears(now: now)
            guard activeFrom != nil else { return active }
            return (active.lowerBound - Chronology.buffer)...(active.upperBound + Chronology.buffer)
        }

        var dated: [Work] { works.filter { $0.year != nil } }
        var undated: [Work] { works.filter { $0.year == nil } }
    }

    enum Level: String, Codable, Sendable {
        case overview, composer
    }

    /// What the Chronology shows: the overview, or one composer.
    struct Position: Equatable, Codable, Sendable {
        var level: Level
        var composer: String?
    }

    /// Every composer with life dates, in birth order, then by name.
    let composers: [Composer]
    let now: Int

    init(
        index: WorkIndex, facts: (String) -> PersonFacts?, year: (WorkIndex.Work) -> Int?,
        now: Int = Calendar(identifier: .gregorian).component(.year, from: .now)
    ) {
        self.now = now
        composers = index.composers.compactMap { composer in
            guard let facts = facts(composer.name), let born = facts.born else { return nil }
            let works = composer.works.filter(\.isTagged).map { Work(work: $0, year: year($0)) }
                .sorted { a, b in
                    a.year != b.year ? (a.year ?? .max) < (b.year ?? .max) : Self.precedes(a.work.title, b.work.title)
                }
            return Composer(
                name: composer.name, born: born, died: facts.died, activeFrom: facts.activeFrom, works: works)
        }
        .sorted { a, b in a.born != b.born ? a.born < b.born : Self.precedes(a.name, b.name) }
    }

    /// Names and titles sort as people read them: "Étude" among the E.
    static func precedes(_ a: String, _ b: String) -> Bool {
        a.localizedStandardCompare(b) == .orderedAscending
    }

    func composer(named name: String?) -> Composer? {
        composers.first { $0.name == name }
    }

    /// Composers whose active years overlap the window of the focus composer. Work dates do not decide.
    func contemporaries(of focus: Composer) -> [Composer] {
        let window = focus.window(now: now)
        return composers.filter { $0 != focus && $0.activeYears(now: now).overlaps(window) }
    }

    /// The focus composer and the contemporaries, in overview order, so that a lane never swaps with the focus.
    func lanes(of focus: Composer) -> [Composer] {
        let names = Set(contemporaries(of: focus).map(\.name) + [focus.name])
        return composers.filter { names.contains($0.name) }
    }

    /// The years of the overview: ten before the first birth to five after the last line end.
    var overviewYears: ClosedRange<Int>? {
        guard let first = composers.first else { return nil }
        let last = composers.map { $0.end(now: now) }.max() ?? first.born
        return (first.born - 10)...(last + 5)
    }

    /// Where the Chronology opens: on the composer of what plays, else where the listener left it,
    /// else on the overview. A composer that has left the chart falls back to the overview.
    func opening(playing: WorkIndex.Work?, left: Position?) -> Position {
        if let name = playing?.composer, composer(named: name) != nil {
            return Position(level: .composer, composer: name)
        }
        guard let left, left.level == .composer else { return Position(level: .overview, composer: left?.composer) }
        return composer(named: left.composer) == nil ? Position(level: .overview, composer: nil) : left
    }

    // MARK: Composer level

    /// The years of the focus composer down the chart: the life fills the height above the undated row.
    struct Scale: Sendable {
        var years: ClosedRange<Int>
        var height: CGFloat
        var rowHeight: CGFloat

        /// The bottom of the dated part. The undated row sits one row below it.
        var span: CGFloat { height - rowHeight * 1.5 }

        func y(_ year: Int) -> CGFloat { y(Double(year)) }

        func y(_ year: Double) -> CGFloat {
            let length = Double(max(1, years.upperBound - years.lowerBound))
            return rowHeight / 2 + CGFloat((year - Double(years.lowerBound)) / length) * (span - rowHeight / 2)
        }

        var undatedY: CGFloat { span + rowHeight }
    }

    func scale(of focus: Composer, height: CGFloat, rowHeight: CGFloat) -> Scale {
        Scale(years: focus.born...focus.end(now: now), height: height, rowHeight: rowHeight)
    }

    /// A row in the column of works. One work, or a year or span of years with a count, or the undated works.
    struct Row: Identifiable, Equatable, Sendable {
        var from: Int?
        var to: Int?
        var works: [WorkIndex.Work]
        /// The centre of the row on the chart.
        var y: CGFloat
        var id: String { from.map { "row:\($0)" } ?? "row:undated" }

        static func == (a: Row, b: Row) -> Bool {
            a.id == b.id && a.y == b.y && a.works.map(\.id) == b.works.map(\.id)
        }

        /// "1829", "1829–32" in one century, "1898–1901" across two, or "No date".
        var years: String {
            guard let from, let to else { return "No date" }
            if from == to { return String(from) }
            let start = String(from)
            let end = String(to)
            return start.prefix(2) == end.prefix(2) && end.count == 4 ? "\(start)–\(end.suffix(2))" : "\(start)–\(end)"
        }

        var opensList: Bool { from == nil || works.count != 1 }

        /// Undated works always have a count and open a list.
        var title: String {
            opensList ? "\(works.count) \(works.count == 1 ? "work" : "works")" : works[0].title
        }
    }

    /// The rows of the focus composer: one per year while they fit; else one row stands for the span of years that
    /// share its place, with a count. Undated works are one row at the end. A row sits at the middle of
    /// its years, at least one row below the row before it, and never below the last year of the life.
    func rows(of focus: Composer, scale: Scale) -> [Row] {
        var rows: [Row] = []
        // Source dates can fall outside the life. Keep their labels, but fit their rows inside the chart.
        func rowY(_ year: Double) -> CGFloat {
            scale.y(min(max(year, Double(scale.years.lowerBound)), Double(scale.years.upperBound)))
        }
        let dated = focus.dated
        let years = dated.compactMap(\.year).reduce(into: [Int]()) { if $0.last != $1 { $0.append($1) } }
        for year in years {
            let works = dated.filter { $0.year == year }.map(\.work)
            let y = rowY(Double(year))
            let floor = rows.dropLast().last.map { $0.y + scale.rowHeight } ?? -CGFloat.infinity
            if var last = rows.last, y < last.y + scale.rowHeight || last.y + scale.rowHeight > scale.span {
                last.to = year
                last.works += works
                last.y = max(rowY((Double(last.from ?? year) + Double(year)) / 2), floor)
                rows[rows.count - 1] = last
                continue
            }
            rows.append(
                Row(from: year, to: year, works: works, y: max(y, rows.last.map { $0.y + scale.rowHeight } ?? y)))
        }
        let undated = focus.undated.map(\.work)
        if !undated.isEmpty { rows.append(Row(from: nil, to: nil, works: undated, y: scale.undatedY)) }
        return rows
    }

    /// The line of a composer at the composer level: dim before the work period start, bright from it.
    /// Without a work period start the line has no shading.
    struct Segment: Equatable, Sendable {
        var from: Int
        var to: Int
        var dim: Bool
    }

    func segments(of composer: Composer) -> [Segment] {
        let end = composer.end(now: now)
        guard let active = composer.activeFrom, active > composer.born, active < end else {
            return [Segment(from: composer.born, to: end, dim: false)]
        }
        return [Segment(from: composer.born, to: active, dim: true), Segment(from: active, to: end, dim: false)]
    }

    /// The lane under a point of a sideways scrub: the chart width maps onto the lines in order.
    static func lane(at x: CGFloat, width: CGFloat, count: Int) -> Int? {
        guard count > 0, width > 0 else { return nil }
        return min(count - 1, max(0, Int((x / width * CGFloat(count)).rounded(.down))))
    }
}

/// Where the listener left the Chronology, kept on the device, and the playing work it last opened on.
@MainActor @Observable
final class ChronologyPlace {
    static let storageKey = "chronology.position"

    private(set) var left: Chronology.Position?
    /// The playing work that the place last opened on. A new work opens it again on its composer.
    private var openedOn: String?
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        left = defaults.data(forKey: Self.storageKey).flatMap {
            try? JSONDecoder().decode(Chronology.Position.self, from: $0)
        }
    }

    /// The composer that the listener last opened, for its mark in the overview.
    var lastOpened: String? { left?.composer }

    /// The place opens: on the composer of a newly playing work, else where the listener left it.
    func open(_ chronology: Chronology, playing: WorkIndex.Work?) -> Chronology.Position {
        let fresh = playing.map(\.id) != openedOn ? playing : nil
        // Missing person facts must not consume the request to open the playing composer.
        if playing == nil || chronology.composer(named: playing?.composer) != nil {
            openedOn = playing?.id
        }
        let position = chronology.opening(playing: fresh, left: left)
        if position != left { keep(position) }
        return position
    }

    /// The listener moves to a composer or to the overview.
    func keep(_ position: Chronology.Position) {
        left = position
        if let data = try? JSONEncoder().encode(position) { defaults.set(data, forKey: Self.storageKey) }
    }

    /// The Chronology button of a composer page opens on that composer.
    func show(composer name: String, playing: WorkIndex.Work?) {
        openedOn = playing?.id
        keep(Chronology.Position(level: .composer, composer: name))
    }

    func clear() {
        left = nil
        openedOn = nil
        defaults.removeObject(forKey: Self.storageKey)
    }
}

extension Chronology {
    /// The placements of the chronology page that live in its script, not in a CSS rule.
    enum Chart {
        /// The column of decade years and its gap to the first lane.
        static let gutter: CGFloat = 44
        /// The overview starts its lines this far after the gutter.
        static let overviewInset: CGFloat = 40
        /// The first lane at the composer level starts this far after the gutter.
        static let laneInset: CGFloat = 8
        /// The lanes take this share of the chart after the gutter; the rows of works take the rest.
        static let laneShare: CGFloat = 0.42
        /// The gap from the last lane to the rows of works.
        static let rowGap: CGFloat = 8
        /// A row of works is its footnote line plus this padding.
        static let rowPadding: CGFloat = 8
        /// The gap from the top of a period band to its name.
        static let bandLabelTop: CGFloat = 4
        /// The centre of the scrub label keeps this distance from each chart edge.
        static let pickInset: CGFloat = 90
        /// A tap this close to the focus line picks its nearest dot.
        static let focusReach: CGFloat = 22
        /// The nearest dot counts only this close to the tap.
        static let dotReach: CGFloat = 24
        /// A drag longer than this, more sideways than down, is a scrub.
        static let scrubStart: CGFloat = 10
        /// A finger that lifts after a scrub must not also tap a row.
        static let tapAfterScrub: TimeInterval = 0.4

        static func overviewX(_ index: Int, count: Int, width: CGFloat) -> CGFloat {
            let left = gutter + overviewInset
            return left + (CGFloat(index) + 0.5) * ((width - left) / CGFloat(max(1, count)))
        }

        static func lanesRight(width: CGFloat) -> CGFloat {
            gutter + (width - gutter) * laneShare
        }

        static func laneX(_ index: Int, count: Int, width: CGFloat) -> CGFloat {
            let left = gutter + laneInset
            return left + (CGFloat(index) + 0.5) * ((lanesRight(width: width) - left) / CGFloat(max(1, count)))
        }

        static func rowsX(width: CGFloat) -> CGFloat {
            lanesRight(width: width) + rowGap
        }

        /// The overview maps its years onto the whole chart height.
        static func y(_ year: Int, in years: ClosedRange<Int>, height: CGFloat) -> CGFloat {
            CGFloat(year - years.lowerBound) / CGFloat(max(1, years.upperBound - years.lowerBound)) * height
        }
    }
}
