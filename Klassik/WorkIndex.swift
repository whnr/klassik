import Foundation

/// The classical tracks ordered by composer, work and recording. Klassik builds it on the device from the tags.
struct WorkIndex: Sendable {
    struct Composer: Identifiable, Sendable {
        /// Works that share a GROUPING tag, such as the nocturnes of one opus.
        struct WorkSet: Identifiable, Sendable {
            var name: String
            var works: [Work]
            var id: String { name }
        }

        var name: String
        var works: [Work]
        var id: String { name }

        /// The sets of tagged works in natural order, so "Op. 6" comes before "Op. 17".
        var sets: [WorkSet] {
            Dictionary(grouping: works.filter { $0.isTagged && $0.grouping != nil }, by: { $0.grouping ?? "" })
                .map { WorkSet(name: $0.key, works: $0.value) }
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }

        /// Tagged works that no set holds.
        var looseWorks: [Work] { works.filter { $0.isTagged && $0.grouping == nil } }
    }

    struct Work: Codable, Identifiable, Sendable {
        var id: String
        var title: String
        var composer: String
        /// False if the tracks carry no WORK tag. Klassik then uses the album as the work.
        var isTagged: Bool
        var recordings: [Recording]
        /// The GROUPING tag of its tracks, if any.
        var grouping: String?

        /// The album that an untagged work stands for. A tagged work has no album page of its own.
        var albumKey: String? { isTagged ? nil : recordings.first?.songs.first?.albumKey }

        /// The reference recording, else the oldest.
        var defaultRecording: Recording? { recordings.first { $0.isReference } ?? recordings.first }

        /// What the track titles say about the work. A WORK tag can be as short as "Op. 67".
        var context: String {
            let first = recordings.first?.songs ?? []
            guard let common = WorkIndex.commonTitle(first.map(\.title)), common != title else { return "" }
            return common
        }
    }

    struct Recording: Codable, Identifiable, Sendable {
        var id: String
        var album: String
        var year: Int?
        /// The movements in disc and track order.
        var songs: [Song] { didSet { names = Roles.lines(of: songs) } }
        /// True if this is a whole album, which can hold several works.
        var isAlbum = false

        /// Every name of the tracks, one line per role. Stored: the work list sorts by it and each row reads it on
        /// every render, and reading all tracks is not free.
        private(set) var names: [Roles.Line]

        init(id: String, album: String, year: Int? = nil, songs: [Song], isAlbum: Bool = false) {
            self.id = id
            self.album = album
            self.year = year
            self.songs = songs
            self.isAlbum = isAlbum
            names = Roles.lines(of: songs)
        }

        private enum CodingKeys: String, CodingKey { case id, album, year, songs, isAlbum }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.init(
                id: try container.decode(String.self, forKey: .id),
                album: try container.decode(String.self, forKey: .album),
                year: try container.decodeIfPresent(Int.self, forKey: .year),
                songs: try container.decode([Song].self, forKey: .songs),
                isAlbum: try container.decodeIfPresent(Bool.self, forKey: .isAlbum) ?? false)
        }

        /// The album page of a whole album.
        var albumKey: String? { isAlbum ? songs.first?.albumKey : nil }

        /// The conductor, soloists and ensembles, which tell recordings apart.
        var principalNames: [Roles.Line] { names.filter { $0.kind.isPrincipal } }

        /// The other names: arranger, lyricist and names without a role.
        var otherNames: [Roles.Line] { names.filter { !$0.kind.isPrincipal } }

        /// All names as one text, for the lock screen and other places that need one string.
        var summary: String { Roles.Line.list(names.flatMap(\.names)) }

        /// The conductor, soloists and ensembles, each once.
        var performerNames: [String] { principalNames.flatMap(\.names) }

        /// The listener's reference recording of a work is the one with all tracks starred in the server.
        var isReference: Bool { !songs.isEmpty && songs.allSatisfy { $0.starred != nil } }

        /// How many movements the tags name for the work, if the tags say.
        var movementTotal: Int? {
            songs.compactMap { $0.movements?.first?.count }.max().flatMap { $0 > 0 ? $0 : nil }
        }

        /// "3 of 5 movements" when the recording holds only part of its work.
        var completeness: String? {
            guard !isAlbum, let total = movementTotal else { return nil }
            let present = Set(songs.compactMap { $0.movements?.first?.number }).count
            return present > 0 && present < total ? "\(present) of \(total) movements" : nil
        }

        /// A movement name alone does not say which work of an album it belongs to.
        func title(of song: Song) -> String {
            isAlbum ? song.title : song.movementTitle
        }
    }

    /// A performer with every recording that names them, grouped by work for the performer page.
    struct Performer: Identifiable, Sendable {
        struct Entry: Identifiable, Sendable {
            var work: Work
            var recording: Recording
            var id: String { recording.id }
        }
        var name: String
        var entries: [Entry]
        var id: String { name }
    }

    /// One album with its tracks in disc order, its works in disc order, and its year. Albums that carry no WORK
    /// tag are in it too, as one entry each.
    struct Album: Identifiable, Sendable {
        /// A work that the album holds, with the recording page of this album's tracks of it.
        struct Part: Identifiable, Sendable {
            var workID: String
            var title: String
            var recordingID: String
            var id: String { workID }
        }

        /// A run of consecutive tracks of the album page. `part` is nil for a plain list and for tracks without a
        /// WORK tag.
        struct Block: Identifiable, Sendable {
            var part: Part?
            /// The position of the first track in the album's tracks.
            var start: Int
            var tracks: [Song]
            var id: Int { start }
        }

        /// The key that groups the tracks, as `Song.albumKey` says.
        var id: String
        /// The whole album as one work with one recording: one queue item.
        var work: Work
        var recording: Recording
        /// The works in the order of their first track. Tracks without a WORK tag name none.
        var parts: [Part]
        /// ADR 0024: only when a work has two movements on consecutive tracks.
        var showsWorkHeadings: Bool

        var title: String { work.title }
        var composer: String { work.composer }
        var year: Int? { recording.year }
        var tracks: [Song] { recording.songs }
        var item: QueueItem { QueueItem(work: work, recording: recording) }

        /// The tracks the page lists, in disc order. With work headings, a block holds the tracks of one work.
        var blocks: [Block] {
            guard showsWorkHeadings else { return [Block(part: nil, start: 0, tracks: tracks)] }
            var blocks: [Block] = []
            var last: String?
            for (position, song) in tracks.enumerated() {
                let key = Self.workKey(of: song)
                if key != nil, key == last, !blocks.isEmpty {
                    blocks[blocks.count - 1].tracks.append(song)
                } else if key == nil, last == nil, let open = blocks.last, open.part == nil {
                    blocks[blocks.count - 1].tracks.append(song)
                } else {
                    blocks.append(
                        Block(part: parts.first { $0.workID == key }, start: position, tracks: [song]))
                }
                last = key
            }
            return blocks
        }

        /// A track under a work heading shows its movement name. Otherwise it shows its title as tagged.
        func title(of song: Song, in block: Block) -> String {
            block.part == nil ? song.title : song.movementTitle
        }

        init?(tracks: [Song]) {
            guard let first = tracks.first, let whole = WorkIndex.album(tracks) else { return nil }
            id = first.albumKey
            work = whole.work
            recording = whole.recording
            let keys = recording.songs.map(Self.workKey)
            showsWorkHeadings = zip(keys, keys.dropFirst()).contains { $0 != nil && $0 == $1 }
            var parts: [Part] = []
            for (song, key) in zip(recording.songs, keys) {
                guard let key, let tag = song.works?.first, !parts.contains(where: { $0.workID == key }) else {
                    continue
                }
                parts.append(Part(workID: key, title: tag.name, recordingID: "\(key)|\(first.albumKey)"))
            }
            self.parts = parts
        }

        /// The key of the track's work, nil without a WORK tag.
        private static func workKey(of song: Song) -> String? {
            song.works?.first == nil ? nil : WorkIndex.workKey(song)
        }
    }

    var composers: [Composer] = []
    var performers: [Performer] = []
    /// By title. Every album of the tracks that built the index.
    private(set) var albums: [Album] = []
    private var albumPositions: [String: Int] = [:]

    init() {}

    func album(_ key: String) -> Album? {
        albumPositions[key].map { albums[$0] }
    }

    /// The albums of some tracks, by title.
    static func albums(of songs: [Song]) -> [Album] {
        Dictionary(grouping: songs, by: \.albumKey).values
            .compactMap { Album(tracks: $0) }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    init(songs: [Song]) {
        albums = Self.albums(of: songs)
        albumPositions = Dictionary(uniqueKeysWithValues: albums.enumerated().map { ($1.id, $0) })
        var works: [String: Work] = [:]
        for (key, tracks) in Dictionary(grouping: songs, by: Self.workKey) {
            let first = tracks[0]
            let tag = first.works?.first
            let recordings = Dictionary(grouping: tracks, by: \.albumKey).map { album, tracks in
                Self.recording(id: "\(key)|\(album)", tracks)
            }
            works[key] = Work(
                id: key, title: tag?.name ?? first.album ?? first.title, composer: first.composerName,
                isTagged: tag != nil,
                recordings: Self.byYearThenNames(recordings),
                grouping: tracks.lazy.compactMap { $0.groupings?.first { !$0.isEmpty } }.first)
        }
        composers = Dictionary(grouping: works.values, by: \.composer)
            .map { name, works in
                Composer(
                    name: name, works: works.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
                )
            }
            .sorted { Self.sortName($0.name).localizedStandardCompare(Self.sortName($1.name)) == .orderedAscending }

        var entries: [String: [Performer.Entry]] = [:]
        for work in composers.flatMap(\.works) {
            for recording in work.recordings {
                for name in recording.performerNames {
                    entries[name, default: []].append(Performer.Entry(work: work, recording: recording))
                }
            }
        }
        performers = entries.map { Performer(name: $0.key, entries: $0.value) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// The oldest first, then by names. The names text is built once for each recording, not once for each comparison.
    private static func byYearThenNames(_ recordings: [Recording]) -> [Recording] {
        recordings.map { (recording: $0, names: $0.summary) }
            .sorted { ($0.recording.year ?? .max, $0.names) < ($1.recording.year ?? .max, $1.names) }
            .map(\.recording)
    }

    /// The MusicBrainz work ID if there is one, then composer and work name, then composer and album.
    static func workKey(_ song: Song) -> String {
        if let work = song.works?.first {
            if let id = work.musicBrainzId, !id.isEmpty { return "mbid:\(id)" }
            return "work:\(song.composerName)|\(work.name)"
        }
        return "album:\(song.composerName)|\(song.albumKey)"
    }

    private static func recording(id: String, _ tracks: [Song]) -> Recording {
        let ordered = tracks.sorted {
            ($0.discNumber ?? 0, $0.track ?? 0, $0.id) < ($1.discNumber ?? 0, $1.track ?? 0, $1.id)
        }
        // A file that the server holds twice must not play twice.
        var seen = Set<String>()
        let songs = ordered.filter { seen.insert("\($0.discNumber ?? 0)|\($0.track ?? 0)|\($0.title)").inserted }
        let first = songs[0]
        return Recording(
            id: id, album: first.album ?? "", year: songs.compactMap(\.year).min(), songs: songs)
    }

    /// A whole album as one work with one recording, to play it from start to end.
    static func album(_ tracks: [Song]) -> (work: Work, recording: Recording)? {
        guard let first = tracks.first else { return nil }
        var whole = Self.recording(id: "album|\(first.albumKey)", tracks)
        whole.isAlbum = true
        let work = Work(
            id: whole.id, title: whole.album.isEmpty ? first.title : whole.album,
            composer: first.composerName, isTagged: false, recordings: [whole])
        return (work, whole)
    }

    /// The part that all movement titles share, such as "Symphonie Nr.5 c-moll" in "Symphonie Nr.5 c-moll (1)".
    static func commonTitle(_ titles: [String]) -> String? {
        guard var prefix = titles.first else { return nil }
        guard titles.count > 1 else { return prefix }
        for title in titles.dropFirst() { prefix = prefix.commonPrefix(with: title) }
        // Drops a partly shared word, such as the "I" that "I. Allegro" and "II. Andante" share.
        guard let cut = prefix.lastIndex(where: { " :(-–,[".contains($0) }) else { return nil }
        let common = prefix[..<cut].trimmingCharacters(in: CharacterSet(charactersIn: " :(-–,.["))
        return common.count >= 3 ? common : nil
    }

    /// Sorts "Ludwig van Beethoven" under B.
    private static func sortName(_ name: String) -> String {
        (name.split(separator: " ").last.map(String.init) ?? name) + " " + name
    }
}

extension Song {
    static let unknownComposer = "Unknown Composer"

    var composerName: String {
        if let name = displayComposer, !name.isEmpty { return name }
        let names = (contributors ?? []).filter { $0.role == "composer" }.map(\.artist.name)
        return names.isEmpty ? Self.unknownComposer : names.joined(separator: ", ")
    }

    /// The movement name if tagged, else the track title.
    var movementTitle: String {
        if let name = movements?.first?.name, !name.isEmpty { return name }
        return title
    }
}

extension WorkIndex.Recording {
    /// The quiet facts in prose (ADR 0031): "Recorded in 1972 on Dvořák Symphonies. 42 minutes, 4 movements."
    /// The album goes out where the page already names it.
    func facts(includingAlbum: Bool = true) -> String {
        var sentences: [String] = []
        let place = includingAlbum && !album.isEmpty ? "on \(album)" : nil
        switch (year, place) {
        case (let year?, let place?): sentences.append("Recorded in \(year) \(place).")
        case (let year?, nil): sentences.append("Recorded in \(year).")
        case (nil, let place?): sentences.append("Recorded \(place).")
        case (nil, nil): break
        }
        var measures: [String] = []
        if let minutes = Self.duration(songs.compactMap(\.duration).reduce(0, +)) { measures.append(minutes) }
        measures.append(completeness ?? Self.count(songs.count, isAlbum ? "track" : "movement"))
        sentences.append(measures.joined(separator: ", ") + ".")
        return sentences.joined(separator: " ")
    }

    /// Rounds to the nearest minute, never under one: 41:58 is "42 minutes".
    static func duration(_ seconds: Int) -> String? {
        guard seconds > 0 else { return nil }
        let minutes = max(1, Int((Double(seconds) / 60).rounded()))
        guard minutes >= 60 else { return count(minutes, "minute") }
        let hours = count(minutes / 60, "hour")
        return minutes % 60 == 0 ? hours : "\(hours) \(count(minutes % 60, "minute"))"
    }

    /// A number never wraps away from its word (ADR 0030).
    static func count(_ number: Int, _ noun: String) -> String {
        "\(number)\u{00A0}\(noun)\(number == 1 ? "" : "s")"
    }
}
