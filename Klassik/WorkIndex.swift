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

    struct Work: Identifiable, Sendable {
        var id: String
        var title: String
        var composer: String
        /// False if the tracks carry no WORK tag. Klassik then uses the album as the work.
        var isTagged: Bool
        var recordings: [Recording]
        /// The GROUPING tag of its tracks, if any.
        var grouping: String?

        /// The reference recording, else the oldest.
        var defaultRecording: Recording? { recordings.first { $0.isReference } ?? recordings.first }

        /// What the track titles and albums say about the work. A WORK tag can be as short as "Op. 67".
        var context: String {
            let first = recordings.first?.songs ?? []
            let albums = Array(Set(recordings.map(\.album))).sorted()
            let parts: [String?] =
                [WorkIndex.commonTitle(first.map(\.title))] + albums.prefix(2).map(Optional.some)
                + [albums.count > 2 ? "+\(albums.count - 2) more" : nil]
            var seen: Set<String> = [title]
            return parts.compactMap(\.self).filter { !$0.isEmpty && seen.insert($0).inserted }.joined(separator: " · ")
        }
    }

    struct Recording: Identifiable, Sendable {
        var id: String
        var album: String
        var year: Int?
        var performers: String
        /// The movements in disc and track order.
        var songs: [Song]
        /// True if this is a whole album, which can hold several works.
        var isAlbum = false

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

    var composers: [Composer] = []
    var performers: [Performer] = []

    init() {}

    init(songs: [Song]) {
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
                recordings: recordings.sorted { ($0.year ?? .max, $0.performers) < ($1.year ?? .max, $1.performers) },
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
                for name in recording.songs.first?.performerNames ?? [] {
                    entries[name, default: []].append(Performer.Entry(work: work, recording: recording))
                }
            }
        }
        performers = entries.map { Performer(name: $0.key, entries: $0.value) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
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
        let ordered = tracks.sorted { ($0.discNumber ?? 0, $0.track ?? 0) < ($1.discNumber ?? 0, $1.track ?? 0) }
        // A file that the server holds twice must not play twice.
        var seen = Set<String>()
        let songs = ordered.filter { seen.insert("\($0.discNumber ?? 0)|\($0.track ?? 0)|\($0.title)").inserted }
        let first = songs[0]
        return Recording(
            id: id, album: first.album ?? "", year: songs.compactMap(\.year).min(), performers: first.performers,
            songs: songs)
    }

    /// A whole album as one work with one recording, to play it from start to end.
    static func album(_ tracks: [Song]) -> (work: Work, recording: Recording)? {
        guard let first = tracks.first else { return nil }
        var whole = Self.recording(id: "album|\(first.albumKey)", tracks)
        whole.isAlbum = true
        whole.performers = first.artist ?? whole.performers
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
    var composerName: String {
        if let name = displayComposer, !name.isEmpty { return name }
        let names = (contributors ?? []).filter { $0.role == "composer" }.map(\.artist.name)
        return names.isEmpty ? "Unknown Composer" : names.joined(separator: ", ")
    }

    /// Soloists, then ensembles, then the conductor. Without these tags, the track artist.
    /// Navidrome returns the contributors of a track in a different order after each scan, so each group sorts by name.
    var performerNames: [String] {
        let roles = contributors ?? []
        let performers = roles.filter { $0.role == "performer" }
        let ensembles = performers.filter(\.isEnsemble)
        let groups = [
            performers.filter { !$0.isEnsemble }, ensembles, roles.filter { $0.role == "conductor" },
        ]
        var names: [String] = []
        for group in groups {
            for name in group.map(\.artist.name).sorted(by: { $0.localizedStandardCompare($1) == .orderedAscending })
            where !names.contains(name) {
                names.append(name)
            }
        }
        return names.isEmpty ? [artist].compactMap(\.self).filter { !$0.isEmpty } : names
    }

    var performers: String { performerNames.joined(separator: ", ") }

    /// The movement name if tagged, else the track title.
    var movementTitle: String {
        if let name = movements?.first?.name, !name.isEmpty { return name }
        return title
    }
}

extension Song.Contributor {
    /// The tag names an instrument for a soloist and a group for an ensemble.
    var isEnsemble: Bool {
        let ensembleWords = ["orchestra", "choir", "chorus", "ensemble", "quartet", "quintet", "trio", "consort"]
        let sub = (subRole ?? "").lowercased()
        return ensembleWords.contains { sub.contains($0) }
    }
}
