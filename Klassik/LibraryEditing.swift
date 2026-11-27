import Foundation
import Observation

/// A setting that the edit sheet offers for a row, in the order the sheet lists them.
enum LibraryEditField: String, CaseIterable, Hashable, Sendable {
    case source, sort, form, count

    var title: String {
        switch self {
        case .source: L("Source")
        case .sort: L("Sort")
        case .form: L("Form")
        case .count: L("Count")
        }
    }
}

/// One value of a setting. The id is what `choose` takes.
struct LibraryChoice: Identifiable, Equatable, Sendable {
    var id: String
    var title: String
    var isCurrent: Bool
}

extension LibraryRowSetup {
    /// The kinds that Add row offers, in order. A saved search waits for its own work (Flo 2026-11-27).
    static let addable: [LibraryRowKind] = [
        .pick, .composers, .performers, .works, .recordings, .albums, .favourites, .added, .heard, .links,
    ]

    /// These kinds take their kind from Source: the listener turns a Composers row into an Albums row.
    private static let unitKinds: [LibraryRowKind] = [.composers, .performers, .works, .recordings, .albums]

    private var isPeople: Bool { kind == .composers || kind == .performers }

    /// The settings that exist for the row. A link list sets its links elsewhere, a Daily pick draws from the
    /// whole library.
    var fields: [LibraryEditField] {
        switch kind {
        case .pick: [.source]
        case .links: []
        default: LibraryEditField.allCases
        }
    }

    func choices(for field: LibraryEditField) -> [LibraryChoice] {
        func make(_ options: [(id: String, title: String)], current: String) -> [LibraryChoice] {
            options.map { LibraryChoice(id: $0.id, title: $0.title, isCurrent: $0.id == current) }
        }
        switch field {
        case .source:
            return make(sourceOptions, current: kind.rawValue)
        case .sort:
            return make(sortOptions.map { ($0.rawValue, Self.sortLabel($0)) }, current: sort.rawValue)
        case .form:
            return make(formOptions.map { ($0.rawValue, formLabel($0)) }, current: form.rawValue)
        case .count:
            return make(countOptions.map { (String($0), $0.localized()) }, current: String(count))
        }
    }

    /// Sets one value that `choices(for:)` offers, then keeps sort, form and count valid for the kind. Any other
    /// value changes nothing.
    mutating func choose(_ id: String, for field: LibraryEditField) {
        guard choices(for: field).contains(where: { $0.id == id }) else { return }
        switch field {
        case .source:
            guard let chosen = LibraryRowKind(rawValue: id), Self.unitKinds.contains(chosen) else { return }
            kind = chosen
            source = LibrarySource(rawValue: id) ?? source
        case .sort:
            sort = LibrarySort(rawValue: id) ?? sort
        case .form:
            form = LibraryForm(rawValue: id) ?? form
        case .count:
            count = Int(id) ?? count
        }
        fit()
    }

    private var sourceOptions: [(id: String, title: String)] {
        if Self.unitKinds.contains(kind) {
            return Self.unitKinds.map { ($0.rawValue, LibraryPage.title(of: LibraryRowSetup(kind: $0))) }
        }
        switch kind {
        case .added: return [(kind.rawValue, L("Albums"))]
        case .heard: return [(kind.rawValue, L("Recordings"))]
        case .pick: return [(kind.rawValue, L("Whole library"))]
        default: return [(kind.rawValue, LibraryPage.title(of: LibraryRowSetup(kind: kind)))]
        }
    }

    /// Best known and last heard first wait for their data: a row sorted by them has nothing to show yet.
    private var sortOptions: [LibrarySort] {
        switch kind {
        case .composers, .performers: [.random, .az]
        case .works, .recordings: [.random, .az, .newest]
        case .albums: [.newest, .random, .az]
        case .favourites: [.random, .az, .newest]
        case .added: [.newest, .random, .az]
        case .heard: [.heard, .random, .az]
        case .pick, .saved, .links: []
        }
    }

    /// Faces for people, covers or tiles for the rest. Favourites mix faces and covers, so they stay a strip.
    private var formOptions: [LibraryForm] {
        if isPeople { return [.faces] }
        if kind == .favourites { return [.covers] }
        return [.covers, .tiles]
    }

    private var countOptions: [Int] { form == .tiles ? [3, 6, 9] : [6, 9, 12] }

    private mutating func fit() {
        if !sortOptions.contains(sort) { sort = LibraryRowSetup(kind: kind).sort }
        if !formOptions.contains(form) { form = formOptions[0] }
        if !countOptions.contains(count) { count = 9 }
    }

    // MARK: Subtitle

    /// What the row shows in words with commas, minus what the title already says.
    var subtitle: String {
        switch kind {
        case .pick:
            return L("Sentence, from the whole library")
        case .links:
            guard !links.isEmpty else { return L("No links") }
            return Self.joined(links.map(Self.linkTitle))
        default:
            break
        }
        var parts: [String] = []
        if kind == .added || kind == .heard { parts.append(sourceOptions[0].title) }
        if sort == LibraryRowSetup(kind: kind).sort {
            parts.append(parts.isEmpty ? Self.sortLabel(sort) : Self.sortWord(sort))
        }
        parts.append(countText)
        return Self.joined(parts)
    }

    private var countText: String {
        if form == .tiles { return L("\(count) tiles") }
        if isPeople { return L("\(count) faces") }
        if kind == .favourites { return L("\(count) faces and covers") }
        return L("\(count) covers")
    }

    private static func joined(_ parts: [String]) -> String {
        guard let first = parts.first else { return "" }
        return parts.dropFirst().reduce(first) { L("\($0), \($1)") }
    }

    private static func linkTitle(_ id: String) -> String {
        switch id {
        case "composers": L("Composers")
        case "favourites": L("Favourites")
        case "albums": L("Albums")
        case "performers": L("Performers")
        case "works": L("Works")
        case "genres": L("Genres")
        case "roles": L("Roles")
        case "playlists": L("Playlists")
        default: id
        }
    }

    /// The name that starts a line or fills a choice.
    private static func sortLabel(_ sort: LibrarySort) -> String {
        switch sort {
        case .random: L("Random")
        case .best: L("Best known")
        case .newest: L("Newest first")
        case .heard: L("Last heard first")
        case .az: L("A to Z")
        }
    }

    /// The name inside a line. Code never changes letter case, so it has its own text.
    private static func sortWord(_ sort: LibrarySort) -> String {
        switch sort {
        case .random: L("random")
        case .best: L("best known")
        case .newest: L("newest first")
        case .heard: L("last heard first")
        case .az: L("A to Z")
        }
    }

    private func formLabel(_ form: LibraryForm) -> String {
        switch form {
        case .faces: L("Strip of faces")
        case .tiles: L("Tiles of covers")
        case .covers: kind == .favourites ? L("Strip of faces and covers") : L("Strip of covers")
        }
    }
}

extension LibraryPage {
    /// Whether the tab draws the row. A row that it hides has nothing to show yet.
    func shows(_ id: String) -> Bool { sections.contains { $0.id == id } }
}

extension LibraryRows {
    /// Changes one row at once, so that the tab follows. A device file that refuses the write keeps the old row.
    func update(_ id: String, _ edit: (inout LibraryRowSetup) -> Void) {
        change { list in
            guard let index = list.firstIndex(where: { $0.id == id }) else { return }
            edit(&list[index])
        }
    }
}

/// The state of the edit sheet: the level on show and the selected row. The rows themselves live in `LibraryRows`,
/// so every change reaches the tab and the device file at once.
@MainActor @Observable
final class LibraryEditor {
    /// The list of rows, Add row, the settings of one row, or the choices of one setting.
    enum Level: Hashable, Sendable {
        case list
        case add
        case row(String)
        case choice(String, LibraryEditField)
    }

    private let rows: LibraryRows
    var level: Level = .list
    /// The row that the tab tints and scrolls to the top.
    private(set) var selected: String?

    init(rows: LibraryRows) {
        self.rows = rows
    }

    /// The level to draw. A level of a row that is gone shows the list.
    var shownLevel: Level {
        switch level {
        case .row(let id), .choice(let id, _):
            rows.rows.contains { $0.id == id } ? level : .list
        case .list, .add:
            level
        }
    }

    func canAdd(_ kind: LibraryRowKind) -> Bool { rows.canInsert(kind) }

    /// A tap in the list or on the tab: tint the row and open its settings.
    func select(_ id: String) {
        guard rows.rows.contains(where: { $0.id == id }) else { return }
        selected = id
        level = .row(id)
    }

    /// The new row goes below the selected row, or to the top when none is selected. A second Daily pick is refused.
    func add(_ kind: LibraryRowKind) {
        guard let row = rows.insert(kind, below: selected) else { return }
        select(row.id)
    }

    func delete(_ id: String) {
        rows.delete(id)
        if selected == id { selected = nil }
        if case .row(let open) = level, open == id { level = .list }
        if case .choice(let open, _) = level, open == id { level = .list }
    }

    func choose(_ choice: String, for field: LibraryEditField, ofRow id: String) {
        rows.update(id) { $0.choose(choice, for: field) }
    }

    func back() {
        switch shownLevel {
        case .choice(let id, _): level = .row(id)
        case .list, .add, .row: level = .list
        }
    }

    func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        rows.move(fromOffsets: source, toOffset: destination)
    }
}

/// The arithmetic of dragging a line by its handle.
enum LibraryReorder {
    /// The place that a line takes when the finger has moved `translation` points from where the line sits now:
    /// the line whose span holds the centre of the dragged line.
    static func destination(of index: Int, translation: CGFloat, heights: [CGFloat]) -> Int {
        guard heights.indices.contains(index) else { return index }
        let tops = heights.reduce(into: [CGFloat(0)]) { $0.append($0[$0.count - 1] + $1) }
        let centre = tops[index] + heights[index] / 2 + translation
        guard centre > 0 else { return 0 }
        return heights.indices.last { tops[$0] <= centre } ?? index
    }

    /// The `toOffset` of `move(fromOffsets:toOffset:)` that puts the line from `from` at place `to`.
    static func offset(from: Int, to: Int) -> Int { to > from ? to + 1 : to }

    /// How far the dragged line moves in the layout when it goes from `from` to `to`. The drag takes it off the
    /// translation, so the line stays under the finger.
    static func shift(from: Int, to: Int, heights: [CGFloat]) -> CGFloat {
        if to > from { return heights[(from + 1)...to].reduce(0, +) }
        if to < from { return -heights[to..<from].reduce(0, +) }
        return 0
    }
}
