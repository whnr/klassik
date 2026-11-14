import SwiftUI

/// The Settings place: what the listener sets, and what shows how Klassik reads the library.
struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @AppStorage(TimelineSide.storageKey) private var timelineSide = TimelineSide.standard

    var body: some View {
        let library = model.library
        @Bindable var player = model.playback
        PageList {
            Section {
                if library.syncedAt == nil {
                    if library.isSyncing {
                        LabeledContent("Syncing") {
                            Text("\(library.received) tracks")
                        }
                        .ink()
                    } else {
                        Text("Not synced")
                            .foregroundStyle(Palette.textSecondary)
                    }
                } else {
                    NavigationLink(value: Page.albums(classical: true)) {
                        LabeledContent("Classical Albums", value: library.classicalAlbumCount.formatted())
                            .ink()
                    }
                    .accessibilityIdentifier("classical-albums")
                    LabeledContent("Classical Tracks", value: library.classical.count.formatted())
                        .ink()
                    NavigationLink(value: Page.albums(classical: false)) {
                        LabeledContent(
                            "Other Albums", value: (library.albumCount - library.classicalAlbumCount).formatted()
                        )
                        .ink()
                    }
                    .accessibilityIdentifier("other-albums")
                }
                if !library.index.composers.isEmpty {
                    NavigationLink(value: Page.musicBrainz) {
                        LabeledContent {
                            Text(lookupState)
                                .foregroundStyle(Palette.textSecondary)
                        } label: {
                            InkLabel("MusicBrainz", systemImage: "books.vertical")
                        }
                    }
                    .accessibilityIdentifier("musicbrainz")
                }
            } header: {
                SectionHeading("Library")
            }

            Section {
                Picker("ReplayGain", selection: $player.leveling) {
                    ForEach(VolumeLeveling.allCases) { Text($0.title).tag($0) }
                }
                .accessibilityIdentifier("replaygain")
            } footer: {
                Text("Album keeps the loudness steps between the movements of a work.")
            }

            Section {
                Toggle("Scrobbles", isOn: $player.scrobblesEnabled)
                    .accessibilityIdentifier("scrobbles")
                if let error = player.listeningError {
                    Text(error).foregroundStyle(Palette.textSecondary)
                }
            } footer: {
                Text("Count played movements on your server. Your server can send them to linked listening services.")
            }

            Section {
                Picker("Timeline", selection: $timelineSide) {
                    ForEach(TimelineSide.allCases) { Text($0.title).tag($0) }
                }
                .accessibilityIdentifier("timeline-side")
            } footer: {
                Text("While music plays, the timeline runs on this screen edge.")
            }

            Section {
                NavigationLink(value: Page.classicalFilter) {
                    InkLabel("Classical Filter", systemImage: "line.3.horizontal.decrease.circle")
                }
                .accessibilityIdentifier("classical-filter")
                NavigationLink(value: Page.localStorage) {
                    InkLabel("Local Storage", systemImage: "internaldrive")
                }
                .accessibilityIdentifier("local-storage")
                NavigationLink(value: Page.swipeActions) {
                    InkLabel("Swipe Actions", systemImage: "arrow.left.arrow.right")
                }
                .accessibilityIdentifier("swipe-actions")
                NavigationLink(value: Page.diagnostics) {
                    InkLabel("Diagnostics", systemImage: "stethoscope")
                }
                .accessibilityIdentifier("diagnostics")
                NavigationLink(value: Page.licences) {
                    InkLabel("Licences", systemImage: "doc.text")
                }
                .accessibilityIdentifier("licences")
            }
        }
        .navigationTitle("Settings")
    }

    /// Progress while the lookup runs, else the works that wait for the listener.
    private var lookupState: String {
        let enrichment = model.enrichment
        if let progress = enrichment.progress { return "\(progress.done) of \(progress.total)" }
        let toConfirm = enrichment.summary(of: model.library.index).toConfirm.count
        return toConfirm > 0 ? "\(toConfirm) to confirm" : ""
    }
}

/// Albums of a set of tracks, to check what the filter lets through.
struct AlbumsView: View {
    let classical: Bool

    @Environment(AppModel.self) private var model

    private struct Row: Identifiable {
        var id: String
        var name: String
        var item: QueueItem
    }

    private var songs: [Song] {
        let library = model.library
        if classical { return library.classical }
        let classicalAlbums = Set(library.classical.map(\.albumKey))
        return library.songs.filter { !classicalAlbums.contains($0.albumKey) }
    }

    private var rows: [Row] {
        Dictionary(grouping: songs, by: \.albumKey)
            .compactMap { key, tracks in
                WorkIndex.album(tracks).map { album in
                    Row(
                        id: key, name: album.work.title,
                        item: QueueItem(work: album.work, recording: album.recording))
                }
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        PageList {
            ForEach(rows) { row in
                NavigationLink(value: Page.recording(work: row.item.work.id, recording: row.item.recording.id)) {
                    VStack(alignment: .leading) {
                        HStack {
                            Text(row.name)
                                .ink()
                            OfflineHint(isOffline: model.tracks.isOffline(row.item.recording))
                        }
                        Text(
                            [row.item.recording.performers, "\(row.item.recording.songs.count) tracks"].filter {
                                !$0.isEmpty
                            }.joined(
                                separator: " · ")
                        )
                        .typeStyle(.subheadline)
                        .foregroundStyle(Palette.textSecondary)
                    }
                }
                .itemActions(row.item, downloads: true)
                .accessibilityIdentifier("album")
            }
        }
        .overlay {
            if songs.isEmpty { ContentUnavailableView("No Albums", systemImage: "square.stack") }
        }
        .navigationTitle(classical ? "Classical Albums" : "Other Albums")
    }
}
