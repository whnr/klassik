import Foundation
import Observation

/// A row of the default Library, in default order. The stored name keeps the order of older builds readable.
enum LibraryRow: String, CaseIterable, Identifiable, Sendable {
    case composers
    case favourites
    case links
    case added

    var id: Self { self }

    var kind: LibraryRowKind {
        switch self {
        case .composers: .composers
        case .favourites: .favourites
        case .links: .links
        case .added: .added
        }
    }
}

/// What a row of the Library shows. The raw value is the stored name; a build that does not know a name lets the
/// row fall away.
enum LibraryRowKind: String, Codable, CaseIterable, Sendable {
    case pick, composers, performers, works, recordings, albums, favourites, added, heard, saved, links
}

/// The kind of item that a row lists, or the whole library for the rows that mix kinds.
enum LibrarySource: String, Codable, Sendable {
    case library, composers, performers, works, recordings, albums
}

enum LibrarySort: String, Codable, Sendable {
    case random, best, newest, heard, az
}

enum LibraryForm: String, Codable, Sendable {
    case faces, covers, tiles
}

/// One configured row of the Library: what it lists, which conditions narrow it, and how it looks.
struct LibraryRowSetup: Codable, Equatable, Identifiable, Sendable {
    /// The links of a new link list, in order.
    nonisolated static let defaultLinks = ["performers", "works", "albums", "genres", "roles", "playlists"]

    var id: String
    var kind: LibraryRowKind
    var source: LibrarySource
    /// The search text of a saved search row, or of the saved search that a Daily pick draws from.
    var searchText: String
    /// Terms in one condition join with "or"; the conditions join with "and". The same shape as a recent search.
    var conditions: [[RecentSearch.Term]]
    var sort: LibrarySort
    var form: LibraryForm
    var count: Int
    /// The checked links of a link list, in the order the tab shows them.
    var links: [String]

    init(kind: LibraryRowKind, id: String = UUID().uuidString) {
        self.id = id
        self.kind = kind
        switch kind {
        case .composers: source = .composers
        case .performers: source = .performers
        case .works: source = .works
        case .recordings: source = .recordings
        case .albums: source = .albums
        default: source = .library
        }
        searchText = ""
        conditions = []
        switch kind {
        case .albums, .added: sort = .newest
        case .heard: sort = .heard
        default: sort = .random
        }
        switch kind {
        case .composers, .performers: form = .faces
        case .links: form = .tiles
        default: form = .covers
        }
        count = 9
        links = kind == .links ? Self.defaultLinks : []
    }

    /// A row of the default Library, with an identity that stays the same between launches.
    fileprivate init(standard row: LibraryRow) {
        self.init(kind: row.kind, id: "default-\(row.rawValue)")
    }

    private enum CodingKeys: String, CodingKey {
        case id, kind, source, searchText, conditions, sort, form, count, links
    }

    /// A field that the file lacks keeps the start value of its kind. A name that this build does not know fails
    /// the row, and the row falls away.
    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let id = try values.decode(String.self, forKey: .id)
        let kind = try values.decode(LibraryRowKind.self, forKey: .kind)
        self.init(kind: kind, id: id)
        source = try values.decodeIfPresent(LibrarySource.self, forKey: .source) ?? source
        searchText = try values.decodeIfPresent(String.self, forKey: .searchText) ?? searchText
        conditions = try values.decodeIfPresent([[RecentSearch.Term]].self, forKey: .conditions) ?? conditions
        sort = try values.decodeIfPresent(LibrarySort.self, forKey: .sort) ?? sort
        form = try values.decodeIfPresent(LibraryForm.self, forKey: .form) ?? form
        count = try values.decodeIfPresent(Int.self, forKey: .count) ?? count
        links = try values.decodeIfPresent([String].self, forKey: .links) ?? links
    }
}

/// The stored form of the Library setup: a version and the rows. It is plain data, so that the sync of the device
/// file can carry it. A setup of a newer version, or one that this build cannot read at all, is kept as read and
/// written back unchanged, so that a save by another module never damages it and never fails the rest of the file.
struct LibrarySetup: Codable, Equatable, Sendable {
    nonisolated static let version = 1

    var version: Int
    var rows: [LibraryRowSetup]
    /// The whole setup as read, when this build does not know its form. Then `rows` is empty and `version` is above
    /// the known one.
    private var kept: JSONValue?

    init(version: Int = LibrarySetup.version, rows: [LibraryRowSetup]) {
        self.version = version
        self.rows = rows
    }

    private enum CodingKeys: String, CodingKey {
        case version, rows
    }

    /// A row of an unknown kind or with an unreadable field falls away, and so does a repeated identity or a
    /// second Daily pick.
    init(from decoder: any Decoder) throws {
        let raw = try JSONValue(from: decoder)
        guard case .object(let object) = raw, case .int(let stored)? = object["version"], stored >= 1 else {
            self = Self.unreadable(raw, version: Int.max)
            return
        }
        guard stored <= Int64(Self.version), case .array? = object["rows"] else {
            self = Self.unreadable(raw, version: stored > Int64(Self.version) ? Int(stored) : Int.max)
            return
        }
        let values = try decoder.container(keyedBy: CodingKeys.self)
        version = Int(stored)
        var seen = Set<String>()
        var hasPick = false
        var accepted: [LibraryRowSetup] = []
        for row in try values.decode([Lossy].self, forKey: .rows).compactMap(\.row) {
            guard seen.insert(row.id).inserted, !(row.kind == .pick && hasPick) else { continue }
            hasPick = hasPick || row.kind == .pick
            accepted.append(row)
        }
        rows = accepted
    }

    func encode(to encoder: any Encoder) throws {
        if let kept {
            try kept.encode(to: encoder)
            return
        }
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(version, forKey: .version)
        try values.encode(rows, forKey: .rows)
    }

    private static func unreadable(_ raw: JSONValue, version: Int) -> LibrarySetup {
        var setup = LibrarySetup(version: version, rows: [])
        setup.kept = raw
        return setup
    }

    private struct Lossy: Decodable {
        var row: LibraryRowSetup?

        init(from decoder: any Decoder) {
            row = try? LibraryRowSetup(from: decoder)
        }
    }
}

/// The rows of the Library. The listener sets them up, and they stay in the device file of the server account,
/// next to favourites and notes.
@MainActor @Observable
final class LibraryRows {
    /// The key under which older builds kept the row order in UserDefaults.
    nonisolated static let legacyKey = "library.rows"

    private let file: ListenerFile
    private let defaults: UserDefaults

    /// The first launch with the file takes over the row order of UserDefaults, once. A file that does not load, or
    /// that nobody has opened yet, leaves the order where it is, so that nothing is lost.
    init(file: ListenerFile, defaults: UserDefaults = .standard) {
        self.file = file
        self.defaults = defaults
        guard file.isOnDevice, file.loadError == nil else { return }
        guard let stored = defaults.stringArray(forKey: Self.legacyKey) else { return }
        if file.data.library == nil {
            var changed = file.data
            let order = Self.legacyOrder(stored: stored)
            changed.library = LibrarySetup(rows: order.map(LibraryRowSetup.init(standard:)))
            guard (try? file.save(changed)) != nil else { return }
        }
        defaults.removeObject(forKey: Self.legacyKey)
    }

    /// The default rows, with identities that stay the same between launches.
    static var standard: [LibraryRowSetup] { LibraryRow.allCases.map(LibraryRowSetup.init(standard:)) }

    /// The rows in tab order. A file without a setup, or with a newer one, shows the default rows.
    var rows: [LibraryRowSetup] {
        if let setup = file.data.library, setup.version <= LibrarySetup.version { return setup.rows }
        return Self.standard
    }

    /// A newer build wrote the setup. This build leaves it alone.
    private var isLocked: Bool { (file.data.library?.version ?? 0) > LibrarySetup.version }

    /// A tab has at most one Daily pick.
    func canInsert(_ kind: LibraryRowKind) -> Bool {
        !isLocked && (kind != .pick || !rows.contains { $0.kind == .pick })
    }

    /// Puts a new row of `kind` below the row `id`, or at the top when no row has that identity. A second Daily
    /// pick is refused.
    @discardableResult
    func insert(_ kind: LibraryRowKind, below id: String?) -> LibraryRowSetup? {
        guard canInsert(kind) else { return nil }
        let row = LibraryRowSetup(kind: kind)
        change { list in
            let below = id.flatMap { id in list.firstIndex { $0.id == id } }
            list.insert(row, at: below.map { $0 + 1 } ?? 0)
        }
        return rows.contains { $0.id == row.id } ? row : nil
    }

    func delete(_ id: String) {
        change { $0.removeAll { $0.id == id } }
    }

    /// Moves rows as `onMove` of a list says: `destination` counts in the list before the move. A list that shows
    /// only some rows passes their identities in `among`; the other rows stay where they are.
    func move(fromOffsets source: IndexSet, toOffset destination: Int, among visible: [String]? = nil) {
        change { list in
            let present = Set(list.map(\.id))
            let shown = (visible ?? list.map(\.id)).filter { present.contains($0) }
            var order = shown
            let moved = source.filter { order.indices.contains($0) }.map { order[$0] }
            let before = source.filter { $0 < destination }.count
            for index in source.sorted(by: >) where order.indices.contains(index) { order.remove(at: index) }
            order.insert(contentsOf: moved, at: min(max(destination - before, 0), order.count))
            let byID = Dictionary(list.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            let slots = list.indices.filter { shown.contains(list[$0].id) }
            for (slot, id) in zip(slots, order) { list[slot] = byID[id] ?? list[slot] }
        }
    }

    func reset() {
        guard !isLocked else { return }
        defaults.removeObject(forKey: Self.legacyKey)
        var changed = file.data
        changed.library = nil
        try? file.save(changed)
    }

    /// The rows named in `stored`, then the others in their default order. Unknown names and repeats fall away.
    static func legacyOrder(stored: [String]) -> [LibraryRow] {
        var result: [LibraryRow] = []
        for row in stored.compactMap(LibraryRow.init(rawValue:)) + LibraryRow.allCases where !result.contains(row) {
            result.append(row)
        }
        return result
    }

    /// A device file that refuses the write keeps the old rows.
    private func change(_ edit: (inout [LibraryRowSetup]) -> Void) {
        guard !isLocked else { return }
        var list = rows
        edit(&list)
        var changed = file.data
        changed.library = LibrarySetup(rows: list)
        try? file.save(changed)
    }
}
