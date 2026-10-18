import Foundation

/// The classical tracks ordered by composer, work and recording. Klassik builds it on the device from the tags.
struct WorkIndex: Sendable {
    struct Composer: Identifiable, Sendable {
        var name: String
        var works: [Work]
        var id: String { name }
    }

    struct Work: Identifiable, Sendable {
        var id: String
        var title: String
        var composer: String
        /// False if the tracks carry no WORK tag. Klassik then uses the album as the work.
        var isTagged: Bool
        var recordings: [Recording]

        /// What the track titles and albums say about the work. A WORK tag can be as short as "Op. 67".
        var context: String {
            let first = recordings.first?.songs ?? []
            let albums = Array(Set(recordings.map(\.album))).sorted()
            let parts: [String?] = [WorkIndex.commonTitle(first.map(\.title))] + albums.prefix(2).map(Optional.some)
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

        /// A movement name alone does not say which work of an album it belongs to.
        func title(of song: Song) -> String {
            isAlbum ? song.title : song.movementTitle
        }
    }

    var composers: [Composer] = []

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
                recordings: recordings.sorted { ($0.year ?? .max, $0.performers) < ($1.year ?? .max, $1.performers) })
        }
        composers = Dictionary(grouping: works.values, by: \.composer)
            .map { name, works in
                Composer(name: name, works: works.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending })
            }
            .sorted { Self.sortName($0.name).localizedStandardCompare(Self.sortName($1.name)) == .orderedAscending }
    }

    /// The MusicBrainz work ID if there is one, then composer and work name, then composer and album.
    private static func workKey(_ song: Song) -> String {
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

    /// Soloists and ensembles, then the conductor. Without these tags, the track artist.
    var performers: String {
        let roles = contributors ?? []
        var names: [String] = []
        for name in roles.filter({ $0.role == "performer" }).map(\.artist.name)
            + roles.filter({ $0.role == "conductor" }).map(\.artist.name) where !names.contains(name) {
            names.append(name)
        }
        return names.isEmpty ? artist ?? "" : names.joined(separator: ", ")
    }

    /// The movement name if tagged, else the track title.
    var movementTitle: String {
        if let name = movements?.first?.name, !name.isEmpty { return name }
        return title
    }
}
