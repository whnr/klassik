import SwiftUI

/// The tags behind a recording and why Klassik put its tracks together. Klassik shows what the server sends.
struct RawTagsView: View {
    let work: WorkIndex.Work
    let recording: WorkIndex.Recording

    var body: some View {
        GroupedPageList {
            Section {
                Text(work.groupingReason)
                    .ink()
                LabeledContent("Work key (derived)", value: work.id)
                    .ink()
                LabeledContent("Album ID", value: recording.songs.first?.albumId ?? "None")
                    .ink()
            } header: {
                Text("Grouping (derived by Klassik)")
            } footer: {
                Text("A recording holds the tracks of one work on one album, in disc and track order.")
            }

            ForEach(recording.songs) { song in
                Section(song.title) {
                    if work.id.hasPrefix("album|") {
                        LabeledContent("Own work key (derived)", value: WorkIndex.workKey(song))
                            .ink()
                    }
                    ForEach(Array(song.tagRows.enumerated()), id: \.offset) { _, row in
                        LabeledContent(row.name, value: row.value)
                            .ink()
                    }
                }
            }
        }
        .pageTitle("Tags")
    }
}

extension WorkIndex.Work {
    /// Which tags put the tracks of this work together.
    var groupingReason: String {
        if id.hasPrefix("mbid:") { return "Grouped by the MusicBrainz work ID in the tags." }
        if id.hasPrefix("work:") { return "Grouped by composer and the WORK tag. No MusicBrainz work ID is tagged." }
        if id.hasPrefix("album|") {
            return "A whole album played as one work. Each track below shows its own work key."
        }
        return "The tracks have no WORK tag. Klassik shows the album as one work."
    }
}

extension Song {
    /// Every field that Klassik reads, with the server's value as sent. Empty fields do not show, except the three
    /// fields of a movement: they stay together, and an absent one is an empty row.
    var tagRows: [(name: String, value: String)] {
        var rows: [(name: String, value: String)] = []
        func add(_ name: String, _ value: String?, keepEmpty: Bool = false) {
            if let value, !value.isEmpty { rows.append((name, value)) } else if keepEmpty { rows.append((name, "")) }
        }
        add("Title", title)
        add("Disc", discNumber.map(String.init))
        add("Track", track.map(String.init))
        add("Album", album)
        add("Artist", artist)
        add("Year", year.map(String.init))
        add("Genre", genre)
        for genre in genres ?? [] { add("Genres", genre.name) }
        add("Composer", displayComposer)
        for contributor in contributors ?? [] {
            let role = [contributor.role, contributor.subRole].compactMap(\.self).joined(separator: "/")
            add(role, contributor.artist.name)
        }
        for work in works ?? [] {
            add("Work", work.name)
            add("MusicBrainz work", work.musicBrainzId)
        }
        for grouping in groupings ?? [] { add("Grouping", grouping) }
        for movement in movements ?? [] {
            add("Movement name", movement.name, keepEmpty: true)
            add("Movement number", movement.number.map(String.init), keepEmpty: true)
            add("Movement count", movement.count.map(String.init), keepEmpty: true)
        }
        add("Suffix", suffix)
        if let gain = replayGain {
            add("Track gain (dB)", gain.trackGain.map { String($0) })
            add("Album gain (dB)", gain.albumGain.map { String($0) })
        }
        add("Starred", starred)
        add("ID", id)
        return rows
    }
}
