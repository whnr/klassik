import SwiftUI

/// Everyone who plays on a recording, from the performer and conductor tags.
struct PerformersView: View {
    @Environment(AppModel.self) private var model
    @State private var query = ""

    var body: some View {
        let performers = model.library.index.performers.filter {
            query.isEmpty || $0.name.localizedStandardContains(query)
        }
        PageList {
            ForEach(performers) { performer in
                NavigationLink {
                    PerformerView(performer: performer)
                } label: {
                    LabeledContent(performer.name, value: performer.entries.count.formatted())
                        .ink()
                }
                .accessibilityIdentifier("performer")
            }
        }
        .overlay {
            if performers.isEmpty {
                ContentUnavailableView("No Performers", systemImage: "person.2")
            }
        }
        .searchable(text: $query)
        .navigationTitle("Performers")
        .miniPlayerInset()
    }
}

/// The recordings of one performer, grouped by work.
struct PerformerView: View {
    let performer: WorkIndex.Performer

    var body: some View {
        let groups = Dictionary(grouping: performer.entries, by: \.work.id)
            .values.sorted {
                ($0[0].work.composer, $0[0].work.title) < ($1[0].work.composer, $1[0].work.title)
            }
        PageList {
            ForEach(groups, id: \.[0].work.id) { entries in
                Section {
                    ForEach(entries.sorted { ($0.recording.year ?? .max) < ($1.recording.year ?? .max) }) { entry in
                        PerformerRow(entry: entry)
                    }
                } header: {
                    SectionHeading(entries[0].work.title)
                } footer: {
                    Text(entries[0].work.composer)
                }
            }
        }
        .navigationTitle(performer.name)
        .miniPlayerInset()
    }
}

private struct PerformerRow: View {
    @Environment(AppModel.self) private var model
    let entry: WorkIndex.Performer.Entry

    var body: some View {
        NavigationLink {
            RecordingView(work: entry.work, recording: entry.recording)
                .miniPlayerInset()
        } label: {
            VStack(alignment: .leading) {
                HStack {
                    Text(entry.recording.performers)
                        .ink()
                    OfflineHint(isOffline: model.tracks.isOffline(entry.recording))
                }
                Text(
                    [entry.recording.year.map(String.init), entry.recording.album]
                        .compactMap(\.self).joined(separator: " · ")
                )
                .typeStyle(.subheadline)
                .foregroundStyle(Palette.textSecondary)
            }
        }
        .itemActions(Player.Item(work: entry.work, recording: entry.recording), downloads: true, reference: true)
        .accessibilityIdentifier("recording")
    }
}
