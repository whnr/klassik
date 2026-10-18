import SwiftUI

/// The tags behind a recording and why Klassik put its tracks together. Klassik shows what the server sends.
struct RawTagsView: View {
    let work: WorkIndex.Work
    let recording: WorkIndex.Recording

    var body: some View {
        List {
            Section {
                Text(work.groupingReason)
                LabeledContent("Work key", value: work.id)
                LabeledContent("Album ID", value: recording.songs.first?.albumId ?? "None")
            } header: {
                Text("Grouping")
            } footer: {
                Text("A recording holds the tracks of one work on one album, in disc and track order.")
            }

            ForEach(recording.songs) { song in
                Section(song.title) {
                    ForEach(Array(song.tagRows.enumerated()), id: \.offset) { _, row in
                        LabeledContent(row.name, value: row.value)
                    }
                }
            }
        }
        .navigationTitle("Tags")
        .navigationBarTitleDisplayMode(.inline)
        .miniPlayerInset()
    }
}

extension WorkIndex.Work {
    /// Which tags put the tracks of this work together.
    var groupingReason: String {
        if id.hasPrefix("mbid:") { return "Grouped by the MusicBrainz work ID in the tags." }
        if id.hasPrefix("work:") { return "Grouped by composer and the WORK tag. No MusicBrainz work ID is tagged." }
        return "The tracks have no WORK tag. Klassik shows the album as one work."
    }
}

extension Song {
    /// Every field that Klassik reads, with the server's value. Empty fields do not show.
    var tagRows: [(name: String, value: String)] {
        var rows: [(name: String, value: String)] = []
        func add(_ name: String, _ value: String?) {
            if let value, !value.isEmpty { rows.append((name, value)) }
        }
        add("Title", title)
        add("Disc", discNumber.map(String.init))
        add("Track", track.map(String.init))
        add("Album", album)
        add("Artist", artist)
        add("Year", year.map(String.init))
        add("Genres", allGenres.joined(separator: ", "))
        add("Composer", displayComposer)
        for contributor in contributors ?? [] {
            let role = [contributor.role, contributor.subRole].compactMap(\.self).joined(separator: "/")
            add(role.capitalized, contributor.artist.name)
        }
        for work in works ?? [] {
            add("Work", work.name)
            add("MusicBrainz work", work.musicBrainzId)
        }
        for movement in movements ?? [] {
            let number = movement.number.map(String.init) ?? "-"
            let count = movement.count.map(String.init) ?? "-"
            add("Movement", "\(movement.name) (\(number) of \(count))")
        }
        add("Format", suffix)
        if let gain = replayGain {
            add("Track gain", gain.trackGain.map { "\($0) dB" })
            add("Album gain", gain.albumGain.map { "\($0) dB" })
        }
        add("Starred", starred)
        add("ID", id)
        return rows
    }
}
