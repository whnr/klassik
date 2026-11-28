import Foundation

/// The Library tab as data: the sections that the rows of the setup give, with their titles, cards and fact lines.
/// Views only draw it. It reads the work index, the listener's favourites, the row setup and a date, and nothing else.
struct LibraryPage {
    /// What the listener marked, as the listener data holds it.
    struct Favourites {
        var composers: [WorkIndex.Composer] = []
        var performers: [WorkIndex.Performer] = []
        var albums: [WorkIndex.Album] = []
        var works: [WorkIndex.Work] = []
        var recordings: [RecordingOrder.Favourite] = []
    }

    struct Card: Identifiable {
        enum Picture {
            case composer(String)
            case performer(String)
            /// The cover of this track's album.
            case cover(Song?)
        }

        var id: String
        var name: String
        /// Exactly one line, of one kind for the whole row.
        var fact: String
        var picture: Picture
        var page: Page
    }

    struct Link: Identifiable {
        var id: String
        var title: String
        var count: Int
        /// Nil for a link whose page the app does not have yet.
        var page: Page?
    }

    /// The pictures of a row: faces for people, covers for the rest, both for a mixed row.
    enum Look { case faces, covers, mixed }

    struct Section: Identifiable {
        var id: String
        /// The stored name of the row kind: it names the title button for tests and VoiceOver.
        var kindName: String
        /// Nil for the link list, which has no heading.
        var title: String?
        /// The page behind the title, when the app has one.
        var titlePage: Page?
        var look: Look = .covers
        var isTiles = false
        var cards: [Card] = []
        var links: [Link] = []
    }

    private(set) var sections: [Section] = []

    /// Link pages that the app does not have yet stay hidden, so that a tile never leads nowhere. A flag shows them
    /// for the work that builds those pages. Nothing sets it yet: the app builds the page with the default, and only
    /// the page model tests pass `true`.
    init(
        index: WorkIndex, favourites: Favourites, rows: [LibraryRowSetup], date: Date,
        calendar: Calendar = .current, unbuiltLinks: Bool = false, searchFilters: SearchFilters? = nil
    ) {
        let day = calendar.dateComponents([.year, .month, .day], from: date)
        let dayKey = "\(day.year ?? 0)-\(day.month ?? 0)-\(day.day ?? 0)"
        let filters = rows.contains { !$0.conditions.isEmpty } ? searchFilters ?? SearchFilters(index: index) : nil
        for row in rows {
            let section: Section?
            switch row.kind {
            case .links:
                section = Self.linkList(
                    row, index: index, favourites: favourites, includesUnbuilt: unbuiltLinks)
            case .composers, .performers, .works, .recordings, .albums, .favourites, .added, .heard:
                section = Self.strip(row, index: index, favourites: favourites, dayKey: dayKey, filters: filters)
            // Other kinds wait for their own work. They keep their place in the setup.
            case .pick, .saved:
                section = nil
            }
            if let section, !(section.cards.isEmpty && section.links.isEmpty) { sections.append(section) }
        }
    }

    // MARK: Strips

    private struct Item {
        var card: Card
        var recordings: [String]
        /// The newest `created` of its tracks, or nil when the server gave none.
        var added: String?
        /// Heard when more than half the movements of a recording have a server play count.
        var isHeard = false
        /// The newest play of what the item stands for; nil when the server gave no date.
        var lastHeard: Date?
    }

    private static func strip(
        _ row: LibraryRowSetup, index: WorkIndex, favourites: Favourites, dayKey: String, filters: SearchFilters?
    ) -> Section {
        let items = filteredItems(row, index: index, favourites: favourites, filters: filters)
        let look: Look =
            switch row.kind {
            case .composers, .performers: .faces
            case .favourites: .mixed
            default: .covers
            }
        let ordered = order(items, by: row.sort, seed: "\(dayKey)|\(row.id)")
        return Section(
            id: row.id, kindName: row.kind.rawValue, title: title(of: row), titlePage: titlePage(of: row.kind),
            look: look, isTiles: row.form == .tiles, cards: Array(ordered.prefix(Self.limit(of: row))).map(\.card))
    }

    /// The source before conditions or the display limit. The filter picker stays inside this source.
    private static func sourceItems(_ row: LibraryRowSetup, index: WorkIndex, favourites: Favourites) -> [Item] {
        var items: [Item]
        switch row.kind {
        case .composers:
            items = index.composers.map(composerItem)
        case .performers:
            items = index.performers.map(performerItem)
        case .works:
            items = index.composers.flatMap(\.works).map(workItem)
        case .recordings, .heard:
            items = index.composers.flatMap(\.works).flatMap { work in
                work.recordings.map { recordingItem(work: work, recording: $0) }
            }
        case .albums:
            items = index.albums.map(albumItem)
        case .added:
            // An album without a date from the server is not "recently" anything.
            items = index.albums.map(albumItem).filter { $0.added != nil }
        default:
            items = mixed(favourites)
        }
        if row.kind == .heard || row.sort == .heard { items = items.filter(\.isHeard) }
        return items
    }

    private static func filteredItems(
        _ row: LibraryRowSetup, index: WorkIndex, favourites: Favourites, filters: SearchFilters?
    ) -> [Item] {
        let items = sourceItems(row, index: index, favourites: favourites)
        guard !row.conditions.isEmpty, let filters else { return items }
        let passing = filters.recordings(matching: row.searchConditions)
        return items.filter { $0.recordings.contains { passing.contains($0) } }
    }

    /// Counts source items, including those beyond the row's display limit.
    static func matchingCount(
        _ row: LibraryRowSetup, index: WorkIndex, favourites: Favourites, filters: SearchFilters? = nil
    ) -> Int {
        filteredItems(row, index: index, favourites: favourites, filters: filters ?? SearchFilters(index: index)).count
    }

    static func filterPool(
        _ row: LibraryRowSetup, index: WorkIndex, favourites: Favourites, filters: SearchFilters? = nil
    ) -> Search.Pool {
        (filters ?? SearchFilters(index: index)).pool(
            recordings: Set(sourceItems(row, index: index, favourites: favourites).flatMap(\.recordings)))
    }

    private static func limit(of row: LibraryRowSetup) -> Int {
        let allowed = row.form == .tiles ? [3, 6, 9] : [6, 9, 12]
        return allowed.contains(row.count) ? row.count : 9
    }

    private static func order(_ items: [Item], by sort: LibrarySort, seed: String) -> [Item] {
        switch sort {
        case .random:
            var generator = SeededGenerator(seed: seed)
            return items.shuffled(using: &generator)
        case .newest:
            // A stable sort: items without a date keep their order, after the dated ones.
            return items.enumerated().sorted {
                switch ($0.element.added, $1.element.added) {
                case (let a?, let b?): a != b ? a > b : $0.offset < $1.offset
                case (nil, _?): false
                case (_?, nil): true
                case (nil, nil): $0.offset < $1.offset
                }
            }.map(\.element)
        case .heard:
            // A stable sort: a heard item without a date keeps its order, after the dated ones.
            return items.enumerated().sorted {
                switch ($0.element.lastHeard, $1.element.lastHeard) {
                case (let a?, let b?): a != b ? a > b : $0.offset < $1.offset
                case (nil, _?): false
                case (_?, nil): true
                case (nil, nil): $0.offset < $1.offset
                }
            }.map(\.element)
        case .az, .best:
            // Best known has no data yet, so every person is "without data" and the names decide.
            return items.sorted { $0.card.name.localizedStandardCompare($1.card.name) == .orderedAscending }
        }
    }

    // MARK: Items

    private static func composerItem(_ composer: WorkIndex.Composer) -> Item {
        let heard = heardState(of: composer.works.flatMap(\.recordings))
        return Item(
            card: Card(
                id: "composer|\(composer.name)", name: composer.name, fact: L("\(composer.works.count) works"),
                picture: .composer(composer.name), page: .composer(composer.name)),
            recordings: composer.works.flatMap(\.recordings).map(\.id),
            added: nil, isHeard: heard.isHeard, lastHeard: heard.last)
    }

    private static func performerItem(_ performer: WorkIndex.Performer) -> Item {
        let heard = heardState(of: performer.entries.map(\.recording))
        return Item(
            card: Card(
                id: "performer|\(performer.name)", name: performer.name,
                fact: L("\(performer.entries.count) recordings"), picture: .performer(performer.name),
                page: .performer(performer.name)),
            recordings: performer.entries.map { $0.recording.id },
            added: nil, isHeard: heard.isHeard, lastHeard: heard.last)
    }

    private static func workItem(_ work: WorkIndex.Work) -> Item {
        let reference = work.recordings.first
        let heard = heardState(of: work.recordings)
        return Item(
            card: Card(
                id: "work|\(work.id)", name: work.title, fact: work.composer,
                picture: .cover(reference?.songs.first), page: .work(work.id)),
            recordings: work.recordings.map(\.id), added: reference.flatMap(added(of:)), isHeard: heard.isHeard,
            lastHeard: heard.last)
    }

    private static func recordingItem(work: WorkIndex.Work, recording: WorkIndex.Recording) -> Item {
        let heard = heardState(of: [recording])
        return Item(
            card: Card(
                id: "recording|\(recording.id)", name: work.title, fact: lead(of: recording),
                picture: .cover(recording.songs.first), page: .recording(work: work.id, recording: recording.id)),
            recordings: [recording.id], added: added(of: recording), isHeard: heard.isHeard, lastHeard: heard.last)
    }

    private static func albumItem(_ album: WorkIndex.Album) -> Item {
        let heard = heardState(of: [album.recording])
        return Item(
            card: Card(
                id: "album|\(album.id)", name: album.title, fact: lead(of: album.recording),
                picture: .cover(album.tracks.first), page: .album(album.id)),
            recordings: Array(Set(album.tracks.map { "\(WorkIndex.workKey($0))|\($0.albumKey)" })),
            added: added(of: album.recording), isHeard: heard.isHeard, lastHeard: heard.last)
    }

    /// An item is heard when one of its recordings is; its date is the newest play of those.
    private static func heardState(of recordings: [WorkIndex.Recording]) -> (isHeard: Bool, last: Date?) {
        let heard = recordings.filter(\.isHeard)
        return (!heard.isEmpty, heard.compactMap(\.lastHeard).max())
    }

    /// Composers, performers, albums, works, recordings: faces and covers in one row, each with its kind.
    private static func mixed(_ favourites: Favourites) -> [Item] {
        var items = favourites.composers.map(composerItem).map { relabelled($0, L("Composer")) }
        items += favourites.performers.map(performerItem).map { relabelled($0, L("Performer")) }
        items += favourites.albums.map(albumItem).map { relabelled($0, L("Album")) }
        items += favourites.works.map(workItem).map { relabelled($0, L("Work")) }
        items += favourites.recordings.map { recordingItem(work: $0.work, recording: $0.recording) }
            .map { relabelled($0, L("Recording")) }
        return items
    }

    private static func relabelled(_ item: Item, _ fact: String) -> Item {
        var item = item
        item.card.fact = fact
        return item
    }

    /// The first conductor or soloist, else the album artist, which tells recordings apart.
    private static func lead(of recording: WorkIndex.Recording) -> String {
        if let name = recording.performerNames.first { return name }
        let song = recording.songs.first
        return song?.displayAlbumArtist ?? song?.artist ?? L("Various artists")
    }

    /// `created` is an ISO 8601 date in the one form that the server writes, so the text compares as the date does.
    private static func added(of recording: WorkIndex.Recording) -> String? {
        recording.songs.compactMap(\.created).max()
    }

    // MARK: Titles

    /// Each kind has one whole string. Tag values keep their case; the fallback format places qualifiers for the app language.
    static func title(of row: LibraryRowSetup) -> String {
        let base = baseTitle(of: row.kind)
        var qualifiers: [String] = []
        let terms = row.conditions.flatMap { $0 }
        if let first = terms.first { qualifiers.append(terms.count == 1 ? first.name : L("filtered")) }
        if row.sort != LibraryRowSetup(kind: row.kind).sort { qualifiers.append(sortName(row.sort)) }
        return qualifiers.reduce(base) { L("\($0), \($1)") }
    }

    private static func baseTitle(of kind: LibraryRowKind) -> String {
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

    private static func sortName(_ sort: LibrarySort) -> String {
        switch sort {
        case .random: L("random")
        case .best: L("best known")
        case .newest: L("newest first")
        case .heard: L("last heard first")
        case .az: L("A to Z")
        }
    }

    /// The pages that exist behind a row title.
    private static func titlePage(of kind: LibraryRowKind) -> Page? {
        switch kind {
        case .composers: .composers
        case .favourites: .favourites
        case .albums, .added: .albums(classical: true)
        default: nil
        }
    }

    // MARK: Links

    private static func linkList(
        _ row: LibraryRowSetup, index: WorkIndex, favourites: Favourites, includesUnbuilt: Bool
    ) -> Section {
        let favouriteCount =
            favourites.composers.count + favourites.performers.count + favourites.albums.count
            + favourites.works.count + favourites.recordings.count
        let known: [String: Link] = [
            "composers": Link(id: "composers", title: L("Composers"), count: index.composers.count, page: .composers),
            "favourites": Link(id: "favourites", title: L("Favourites"), count: favouriteCount, page: .favourites),
            "albums": Link(
                id: "albums", title: L("Albums"), count: index.albums.count, page: .albums(classical: true)),
            "performers": Link(id: "performers", title: L("Performers"), count: index.performers.count, page: nil),
            "works": Link(
                id: "works", title: L("Works"), count: index.composers.reduce(0) { $0 + $1.works.count }, page: nil),
            "genres": Link(id: "genres", title: L("Genres"), count: 0, page: nil),
            "roles": Link(id: "roles", title: L("Roles"), count: 0, page: nil),
            "playlists": Link(id: "playlists", title: L("Playlists"), count: 0, page: nil),
        ]
        let links = row.links.compactMap { known[$0] }.filter { includesUnbuilt || $0.page != nil }
        return Section(id: row.id, kindName: row.kind.rawValue, title: nil, titlePage: nil, links: links)
    }
}

/// A repeatable shuffle: the same seed gives the same order. The seed is the day and the row, so a row keeps its
/// cards for a day and draws new ones the next day.
nonisolated struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    /// FNV-1a over the seed text, then SplitMix64 steps. `hashValue` differs between launches, so it cannot seed this.
    init(seed: String) {
        state = seed.utf8.reduce(14_695_981_039_346_656_037) { ($0 ^ UInt64($1)) &* 1_099_511_628_211 }
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
