import SwiftUI

/// Settings, in groups (ADR 0040): what the listener sets first, the technical part behind its switch.
struct SettingsView: View {
    /// The Technical details switch. It stays off until the listener wants the technical part.
    static let technicalDetailsKey = "settings.technicalDetails"

    @Environment(AppModel.self) private var model
    @AppStorage(TimelineSide.storageKey) private var timelineSide = TimelineSide.standard
    @AppStorage(ComposerWorks.separatesPartialKey) private var separatesPartial = true
    @AppStorage(CoverWash.strengthKey) private var tintStrength = 2
    @AppStorage(Self.technicalDetailsKey) private var showsTechnicalDetails = false
    @State private var confirmsDelete = false
    @State private var deleteError: String?

    var body: some View {
        @Bindable var player = model.playback
        GroupedPageList {
            Section {
                Picker("Timeline", selection: $timelineSide) {
                    ForEach(TimelineSide.allCases) { Text($0.title).tag($0) }
                }
                .accessibilityIdentifier("timeline-side")
                Picker("ReplayGain", selection: $player.leveling) {
                    ForEach(VolumeLeveling.allCases) { Text($0.title).tag($0) }
                }
                .accessibilityIdentifier("replaygain")
                Toggle("Scrobbles", isOn: $player.scrobblesEnabled)
                    .accessibilityIdentifier("scrobbles")
            } header: {
                SectionHeading("Playback")
            } footer: {
                Text(
                    "While music plays, the timeline runs on this screen edge. Album keeps the loudness steps between the movements of a work. Scrobbles count played movements on your server. Your server can send them to linked listening services."
                )
            }

            Section {
                Picker("Accent", selection: accent) {
                    ForEach(AccentFamily.allCases) { Text($0.title).tag($0) }
                }
                .accessibilityIdentifier("accent")
                Picker("Player Tint", selection: $tintStrength) {
                    Text("1×").tag(1)
                    Text("2×").tag(2)
                    Text("3×").tag(3)
                }
                .accessibilityIdentifier("player-tint-strength")
            } header: {
                SectionHeading("Colour")
            } footer: {
                Text(
                    "The accent marks links, controls and what plays. Player Tint is a temporary comparison of the cover tint strength."
                )
            }

            Section {
                NavigationLink(value: Page.classicalRules) {
                    InkLabel("Classical Rules", systemImage: "line.3.horizontal.decrease.circle")
                }
                .accessibilityIdentifier("classical-rules")
                Toggle("Separate Partial Works", isOn: $separatesPartial)
                    .accessibilityIdentifier("partial-works")
                NavigationLink(value: Page.swipeActions) {
                    InkLabel("Swipe Actions", systemImage: "arrow.left.arrow.right")
                }
                .accessibilityIdentifier("swipe-actions")
            } header: {
                SectionHeading("Library")
            } footer: {
                Text("A composer page lists a work with no complete recording under Partial works.")
            }

            Section {
                Button("Delete Listening Data", role: .destructive) { confirmsDelete = true }
                    .accessibilityIdentifier("delete-listening-data")
            } header: {
                SectionHeading("Listening data")
            } footer: {
                Text(
                    "Favourite works, the order of favourite recordings, listening notes and the changes that wait stay on this iPhone, for this server and user. Sign-out keeps them."
                )
            }

            Section {
                Toggle("Technical Details", isOn: $showsTechnicalDetails)
                    .accessibilityIdentifier("technical-details")
            } footer: {
                Text("Shows the library counts, the lookups, local storage and diagnostics with the changes that wait.")
            }

            if showsTechnicalDetails { technicalDetails }

            Section {
                NavigationLink(value: Page.licences) {
                    InkLabel("Licences", systemImage: "doc.text")
                }
                .accessibilityIdentifier("licences")
            }
        }
        .pageTitle("Settings")
        .confirmationDialog("Delete Listening Data?", isPresented: $confirmsDelete, titleVisibility: .visible) {
            Button("Delete Listening Data", role: .destructive) {
                do { try model.deleteListeningData() } catch { deleteError = error.localizedDescription }
            }
        } message: {
            Text(
                "This removes the favourite works, the order of favourite recordings, the listening notes and the changes that wait of this server and user from this iPhone. You cannot undo this."
            )
        }
        // A failure of the device file is the one listening data notice (ADR 0058).
        .alert(
            "Listening Data",
            isPresented: Binding(get: { deleteError != nil }, set: { if !$0 { deleteError = nil } })
        ) {
            Button("OK") { deleteError = nil }
        } message: {
            Text(deleteError ?? "")
        }
    }

    private var accent: Binding<AccentFamily> {
        Binding(get: { AccentChoice.shared.family }, set: { AccentChoice.shared.family = $0 })
    }

    @ViewBuilder private var technicalDetails: some View {
        let library = model.library
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
            NavigationLink(value: Page.localStorage) {
                InkLabel("Local Storage", systemImage: "internaldrive")
            }
            .accessibilityIdentifier("local-storage")
            NavigationLink(value: Page.diagnostics) {
                LabeledContent {
                    Text(waitingChanges)
                        .foregroundStyle(Palette.textSecondary)
                } label: {
                    InkLabel("Diagnostics", systemImage: "stethoscope")
                }
            }
            .accessibilityIdentifier("diagnostics")
        } header: {
            SectionHeading("Technical details")
        }
    }

    /// The favourite changes that wait for the server. Diagnostics lists them.
    private var waitingChanges: String {
        let count = model.recordingOrder.pendingChanges.count
        return count == 0 ? "" : "\(count) waiting"
    }

    /// Progress while the lookup runs, else the works that wait for the listener.
    private var lookupState: String {
        let enrichment = model.enrichment
        if let progress = enrichment.progress { return "\(progress.done) of \(progress.total)" }
        let toConfirm = enrichment.summary(of: model.library.index).toConfirm.count
        if toConfirm > 0 { return "\(toConfirm) to confirm" }
        switch model.sweep.state {
        case .running(let done, let total): return "People \(done) of \(total)"
        case .paused: return "Paused"
        case .idle, .upToDate: return ""
        }
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
                .itemActions(album.item, downloads: true, favouriteAlbum: true)
                .accessibilityIdentifier("album")
                .itemSeparator(first: album.id == albums.first?.id, last: album.id == albums.last?.id)
            }
        }
        .overlay {
            if albums.isEmpty { ContentUnavailableView("No Albums", systemImage: "square.stack") }
        }
        .pageTitle(classical ? "Classical Albums" : "Other Albums")
    }
}
