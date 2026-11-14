import SwiftUI

/// The Settings place: what the listener sets, and what shows how Klassik reads the library.
struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @AppStorage(TimelineSide.storageKey) private var timelineSide = TimelineSide.standard

    var body: some View {
        let library = model.library
        @Bindable var player = model.playback
        GroupedPageList {
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
        .pageTitle("Settings")
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

    private var albums: [WorkIndex.Album] {
        classical ? model.library.index.albums : model.library.otherAlbums
    }

    var body: some View {
        PageList {
            ForEach(albums) { album in
                NavigationLink(value: Page.album(album.id)) {
                    VStack(alignment: .leading) {
                        HStack {
                            Text(album.title)
                                .ink()
                            OfflineHint(isOffline: model.tracks.isOffline(album.recording))
                        }
                        RoleLines(lines: album.recording.names)
                            .ink()
                        Text(album.recording.facts(includingAlbum: false))
                            .typeStyle(.subheadline)
                            .foregroundStyle(Palette.textSecondary)
                    }
                }
                .itemActions(album.item, downloads: true)
                .accessibilityIdentifier("album")
            }
        }
        .overlay {
            if albums.isEmpty { ContentUnavailableView("No Albums", systemImage: "square.stack") }
        }
        .pageTitle(classical ? "Classical Albums" : "Other Albums")
    }
}
