import SwiftUI

struct HomeView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let library = model.library
        @Bindable var player = model.player
        NavigationStack {
            PageList {
                if !library.index.composers.isEmpty {
                    Section {
                        NavigationLink {
                            WorkTimelineView()
                        } label: {
                            InkLabel("Timeline", systemImage: "calendar")
                        }
                        .accessibilityIdentifier("timeline")
                        NavigationLink {
                            EnrichmentStatusView()
                        } label: {
                            LabeledContent {
                                Text(lookupState)
                                    .foregroundStyle(Palette.textSecondary)
                            } label: {
                                InkLabel("MusicBrainz", systemImage: "books.vertical")
                            }
                        }
                        .accessibilityIdentifier("musicbrainz")
                    }
                    Section {
                        ForEach(library.index.composers) { composer in
                            NavigationLink {
                                ComposerView(composer: composer)
                            } label: {
                                LabeledContent(composer.name, value: composer.works.count.formatted())
                                    .ink()
                            }
                            .accessibilityIdentifier("composer")
                        }
                    } header: {
                        SectionHeading("Composers")
                    }
                }

                if !library.index.performers.isEmpty {
                    Section {
                        NavigationLink {
                            PerformersView()
                        } label: {
                            LabeledContent("Performers", value: library.index.performers.count.formatted())
                                .ink()
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
                            .ink()
                        } else {
                            Text("Not synced")
                                .foregroundStyle(Palette.textSecondary)
                        }
                    } else {
                        NavigationLink {
                            AlbumsView(title: "Classical Albums", songs: library.classical)
                        } label: {
                            LabeledContent("Classical Albums", value: library.classicalAlbumCount.formatted())
                                .ink()
                        }
                        .accessibilityIdentifier("classical-albums")
                        LabeledContent("Classical Tracks", value: library.classical.count.formatted())
                            .ink()
                        NavigationLink {
                            AlbumsView(title: "Other Albums", songs: otherSongs)
                        } label: {
                            LabeledContent(
                                "Other Albums", value: (library.albumCount - library.classicalAlbumCount).formatted()
                            )
                            .ink()
                        }
                        .accessibilityIdentifier("other-albums")
                    }
                } header: {
                    SectionHeading("Library")
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
                        FilterView()
                    } label: {
                        InkLabel("Classical Filter", systemImage: "line.3.horizontal.decrease.circle")
                    }
                    .accessibilityIdentifier("classical-filter")
                    NavigationLink {
                        LocalStorageView()
                    } label: {
                        InkLabel("Local Storage", systemImage: "internaldrive")
                    }
                    .accessibilityIdentifier("local-storage")
                    NavigationLink {
                        SwipeSettingsView()
                    } label: {
                        InkLabel("Swipe Actions", systemImage: "arrow.left.arrow.right")
                    }
                    .accessibilityIdentifier("swipe-actions")
                    NavigationLink {
                        DiagnosticsView()
                    } label: {
                        InkLabel("Diagnostics", systemImage: "stethoscope")
                    }
                    .accessibilityIdentifier("diagnostics")
                    NavigationLink {
                        LicencesView()
                    } label: {
                        InkLabel("Licences", systemImage: "doc.text")
                    }
                    .accessibilityIdentifier("licences")
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

    /// Progress while the lookup runs, else the works that wait for the listener.
    private var lookupState: String {
        let enrichment = model.enrichment
        if let progress = enrichment.progress { return "\(progress.done) of \(progress.total)" }
        let toConfirm = enrichment.summary(of: model.library.index).toConfirm.count
        return toConfirm > 0 ? "\(toConfirm) to confirm" : ""
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
        var item: Player.Item
    }

    private var rows: [Row] {
        Dictionary(grouping: songs, by: \.albumKey)
            .compactMap { key, tracks in
                WorkIndex.album(tracks).map { album in
                    Row(
                        id: key, name: album.work.title,
                        item: Player.Item(work: album.work, recording: album.recording))
                }
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        PageList {
            ForEach(rows) { row in
                NavigationLink {
                    RecordingView(work: row.item.work, recording: row.item.recording)
                        .miniPlayerInset()
                } label: {
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
        .navigationTitle(title)
        .miniPlayerInset()
    }
}
