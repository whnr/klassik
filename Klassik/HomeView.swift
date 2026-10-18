import SwiftUI

struct HomeView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let library = model.library
        NavigationStack {
            List {
                if !library.index.composers.isEmpty {
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
                            LabeledContent("Other Albums", value: (library.albumCount - library.classicalAlbumCount).formatted())
                        }
                        .accessibilityIdentifier("other-albums")
                    }
                } header: {
                    Text("Library")
                } footer: {
                    if let error = library.syncError {
                        Text(error)
                    } else if let syncedAt = library.syncedAt {
                        Text(library.isSyncing ? "Syncing… \(library.received) tracks" : "Synced \(syncedAt.formatted(.relative(presentation: .named))).")
                            .accessibilityIdentifier("library-synced")
                    }
                }

                Section {
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
            .refreshable {
                if let client = model.client { await library.sync(with: client) }
            }
        }
        .safeAreaInset(edge: .bottom) { MiniPlayer() }
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

    private struct Row: Identifiable {
        var id: String
        var name: String
        var artist: String?
        var tracks: Int
    }

    private var rows: [Row] {
        Dictionary(grouping: songs, by: \.albumKey)
            .map { key, tracks in Row(id: key, name: tracks[0].album ?? tracks[0].title, artist: tracks[0].artist, tracks: tracks.count) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        List(rows) { row in
            VStack(alignment: .leading) {
                Text(row.name)
                Text([row.artist, "\(row.tracks) tracks"].compactMap(\.self).joined(separator: " · "))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .overlay {
            if songs.isEmpty { ContentUnavailableView("No Albums", systemImage: "square.stack") }
        }
        .navigationTitle(title)
    }
}
