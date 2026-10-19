import SwiftUI

struct HomeView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let library = model.library
        @Bindable var player = model.player
        NavigationStack {
            List {
                if !library.index.composers.isEmpty {
                    Section {
                        NavigationLink {
                            WorkTimelineView()
                        } label: {
                            Label("Timeline", systemImage: "calendar")
                        }
                        .accessibilityIdentifier("timeline")
                    }
                    Section("Composers") {
                        ForEach(library.index.composers) { composer in
                            NavigationLink {
                                ComposerView(composer: composer)
                            } label: {
                                LabeledContent(composer.name, value: composer.works.count.formatted())
                            }
                            .accessibilityIdentifier("composer")
                        }
                    }
                }

                if !library.index.performers.isEmpty {
                    Section {
                        NavigationLink {
                            PerformersView()
                        } label: {
                            LabeledContent("Performers", value: library.index.performers.count.formatted())
                        }
                        .accessibilityIdentifier("performers")
                    }
                }

                Section {
                    if library.syncedAt == nil {
                        if library.isSyncing {
                            LabeledContent("Syncing") {
                                Text("\(library.received) tracks")
                            }
                        } else {
                            Text("Not synced")
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        NavigationLink {
                            AlbumsView(title: "Classical Albums", songs: library.classical)
                        } label: {
                            LabeledContent("Classical Albums", value: library.classicalAlbumCount.formatted())
                        }
                        .accessibilityIdentifier("classical-albums")
                        LabeledContent("Classical Tracks", value: library.classical.count.formatted())
                        NavigationLink {
                            AlbumsView(title: "Other Albums", songs: otherSongs)
                        } label: {
                            LabeledContent(
                                "Other Albums", value: (library.albumCount - library.classicalAlbumCount).formatted())
                        }
                        .accessibilityIdentifier("other-albums")
                    }
                } header: {
                    Text("Library")
                } footer: {
                    if let error = library.syncError {
                        Text(error)
                    } else if let syncedAt = library.syncedAt {
                        Text(
                            library.isSyncing
                                ? "Syncing… \(library.received) tracks"
                                : "Synced \(syncedAt.formatted(.relative(presentation: .named)))."
                        )
                        .accessibilityIdentifier("library-synced")
                    }
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
                    NavigationLink {
                        LocalStorageView()
                    } label: {
                        Label("Local Storage", systemImage: "internaldrive")
                    }
                    .accessibilityIdentifier("local-storage")
                    NavigationLink {
                        SwipeSettingsView()
                    } label: {
                        Label("Swipe Actions", systemImage: "arrow.left.arrow.right")
                    }
                    .accessibilityIdentifier("swipe-actions")
                    NavigationLink {
                        FilterView()
                    } label: {
                        Label("Classical Filter", systemImage: "line.3.horizontal.decrease.circle")
                    }
                    .accessibilityIdentifier("classical-filter")
                    NavigationLink {
                        DiagnosticsView()
                    } label: {
                        Label("Diagnostics", systemImage: "stethoscope")
                    }
                    .accessibilityIdentifier("diagnostics")
                }
            }
            .navigationTitle("Klassik")
            .miniPlayerInset()
            .toolbar {
                ShuffleButton(works: library.index.composers.flatMap(\.works))
            }
            .refreshable {
                guard let client = model.client else { return }
                await library.sync(with: client)
                // The lookup can take minutes; the pull to refresh ends with the sync.
                Task { await model.enrichment.enrich(library.index) }
            }
        }
    }

    private var otherSongs: [Song] {
        let classical = Set(model.library.classical.map(\.albumKey))
        return model.library.songs.filter { !classical.contains($0.albumKey) }
    }
}

/// Albums of a set of tracks, to check what the filter lets through.
struct AlbumsView: View {
    let title: String
    let songs: [Song]

    @Environment(AppModel.self) private var model

    private struct Row: Identifiable {
        var id: String
        var name: String
        var artist: String?
        var item: Player.Item
    }

    private var rows: [Row] {
        Dictionary(grouping: songs, by: \.albumKey)
            .compactMap { key, tracks in
                WorkIndex.album(tracks).map { album in
                    Row(
                        id: key, name: album.work.title, artist: tracks[0].artist,
                        item: Player.Item(work: album.work, recording: album.recording))
                }
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        List(rows) { row in
            NavigationLink {
                RecordingView(work: row.item.work, recording: row.item.recording)
                    .miniPlayerInset()
            } label: {
                VStack(alignment: .leading) {
                    HStack {
                        Text(row.name)
                            .foregroundStyle(Color.primary)
                        OfflineHint(isOffline: model.tracks.isOffline(row.item.recording))
                    }
                    Text(
                        [row.artist, "\(row.item.recording.songs.count) tracks"].compactMap(\.self).joined(
                            separator: " · ")
                    )
                    .font(.subheadline)
                    .foregroundStyle(Color.secondary)
                }
            }
            .itemActions(row.item, downloads: true)
            .accessibilityIdentifier("album")
        }
        .overlay {
            if songs.isEmpty { ContentUnavailableView("No Albums", systemImage: "square.stack") }
        }
        .navigationTitle(title)
        .miniPlayerInset()
    }
}
