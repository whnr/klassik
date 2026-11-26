import KlassikEngine
import SwiftUI

/// Settings, in groups, in the order Flo set: Playback, Library, Colour, Advanced settings, About.
struct SettingsView: View {
    /// Klassik is open source. The link opens in the browser.
    static let sourceCode = URL(string: "https://github.com/whnr/klassik")!

    /// Version and build, as the bundle reports them. A missing or empty value shows as "?", never as blank.
    nonisolated static func version(from info: [String: Any]?) -> String {
        func value(_ key: String) -> String {
            let text = (info?[key] as? String)?.trimmingCharacters(in: .whitespaces) ?? ""
            return text.isEmpty ? "?" : text
        }
        return "\(value("CFBundleShortVersionString")) (\(value("CFBundleVersion")))"
    }

    static var version: String { version(from: Bundle.main.infoDictionary) }

    @Environment(AppModel.self) private var model
    @AppStorage(TimelineSide.storageKey) private var timelineSide = TimelineSide.standard
    @AppStorage(ComposerWorks.separatesPartialKey) private var separatesPartial = true
    @AppStorage(CoverWash.strengthKey) private var tintStrength = CoverWash.defaultStrength
    @State private var deleteError: String?

    private var tintLabel: String { "\(tintStrength.localized())×" }

    var body: some View {
        @Bindable var player = model.playback
        // A menu picker keeps the tint that it got when it was made. A new identity for each family remakes it.
        let family = AccentChoice.shared.family
        GroupedPageList {
            Section {
                Picker("Fallback Language", selection: fallbackSetting) {
                    ForEach(TextFallback.all) { Text($0.title).tag($0) }
                }
                .accessibilityIdentifier("text-fallback")
                .id(family)
            } header: {
                SectionHeading("Language")
            } footer: {
                Text(
                    "Descriptions and biographies come from Wikidata and Wikipedia in the app language. Where they have none, Klassik shows the fallback language, or nothing when it is off. Composer names, work titles and tags stay as your music tags them. Change the app language in the iOS Settings app, under Klassik."
                )
            }

            Section {
                Picker("Timeline", selection: $timelineSide) {
                    ForEach(TimelineSide.allCases) { Text($0.title).tag($0) }
                }
                .accessibilityIdentifier("timeline-side")
                .id(family)
                Picker("ReplayGain", selection: $player.leveling) {
                    ForEach(VolumeLeveling.allCases) { Text($0.title).tag($0) }
                }
                .accessibilityIdentifier("replaygain")
                .id(family)
                Toggle("Show Audio Quality", isOn: $player.showsAudioQuality)
                    .accessibilityIdentifier("audio-quality-setting")
                Toggle("Scrobbles", isOn: $player.scrobblesEnabled)
                    .accessibilityIdentifier("scrobbles")
            } header: {
                SectionHeading("Playback")
            } footer: {
                Text(
                    "While music plays, the timeline runs on this screen edge. Album keeps the loudness steps between the movements of a work. ReplayGain Off removes the gain stage from the signal path. Show Audio Quality adds a line under the playback bar: the file format, the output rate, and whether anything changes the samples. Scrobbles count played movements on your server. Your server can send them to linked listening services."
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
                NavigationLink(value: Page.localStorage) {
                    InkLabel("Local Storage", systemImage: "internaldrive")
                }
                .accessibilityIdentifier("local-storage")
                DeleteListeningDataButton(failure: $deleteError)
            } header: {
                SectionHeading("Library")
            } footer: {
                Text(
                    "A composer page lists a work with no complete recording under Partial works. Favourite works, listening notes, recent searches and the changes that wait stay on this iPhone, for this server and user. Sign-out keeps them."
                )
            }

            Section {
                Picker("Accent", selection: accent) {
                    ForEach(AccentFamily.allCases) { Text($0.title).tag($0) }
                }
                .accessibilityIdentifier("accent")
                .id(family)
                VStack {
                    LabeledContent("Player Tint") {
                        Text(tintLabel)
                    }
                    .accessibilityHidden(true)
                    Slider(
                        value: $tintStrength, in: CoverWash.strengthRange, step: CoverWash.strengthStep
                    ) {
                        Text("Player Tint")
                    }
                    // VoiceOver reads the strength, not the slider percentage.
                    .accessibilityValue(tintLabel)
                    .accessibilityIdentifier("player-tint-strength")
                }
            } header: {
                SectionHeading("Colour")
            } footer: {
                Text(
                    "The accent marks links, controls and what plays. Player Tint is a temporary comparison of the cover tint strength."
                )
            }

            Section {
                if !model.library.index.composers.isEmpty {
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
                NavigationLink(value: Page.diagnostics) {
                    LabeledContent {
                        Text(waitingChanges)
                            .foregroundStyle(Palette.textSecondary)
                    } label: {
                        InkLabel("Diagnostics", systemImage: "stethoscope")
                    }
                }
                .accessibilityIdentifier("diagnostics")
                NavigationLink(value: Page.serverConnection) {
                    LabeledContent {
                        Text(model.connectionState)
                            .foregroundStyle(Palette.textSecondary)
                    } label: {
                        InkLabel("Server Connection", systemImage: "server.rack")
                    }
                }
                .accessibilityIdentifier("server-connection")
                NavigationLink(value: Page.licences) {
                    InkLabel("Licences", systemImage: "doc.text")
                }
                .accessibilityIdentifier("licences")
            } header: {
                SectionHeading("Advanced settings")
            } footer: {
                Text("Shows the lookups and diagnostics with the changes that wait.")
            }

            Section {
                Link(destination: Self.sourceCode) {
                    InkLabel("Source Code on GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
                }
                .accessibilityIdentifier("source-code")
            } header: {
                SectionHeading("About")
            } footer: {
                Text("Klassik \(Self.version)")
                    .accessibilityIdentifier("app-version")
            }
        }
        .pageTitle(L("Settings"))
        // A failure of the device file is the one listening data notice.
        .alert(
            "Listening Data",
            isPresented: Binding(get: { deleteError != nil }, set: { if !$0 { deleteError = nil } })
        ) {
            Button("OK") { deleteError = nil }
        } message: {
            Text(deleteError ?? "")
        }
    }

    private var fallbackSetting: Binding<TextFallback> {
        Binding(get: { Localization.shared.fallbackSetting }, set: { Localization.shared.select(fallback: $0) })
    }

    private var accent: Binding<AccentFamily> {
        Binding(get: { AccentChoice.shared.family }, set: { AccentChoice.shared.family = $0 })
    }

    /// The favourite changes that wait for the server. Diagnostics lists them.
    private var waitingChanges: String {
        let count = model.recordingOrder.pendingChanges.count
        return count == 0 ? "" : L("\(count) waiting")
    }

    /// Progress while the lookup runs, else the works that wait for the listener.
    private var lookupState: String {
        let enrichment = model.enrichment
        if let progress = enrichment.progress { return L("\(progress.done) of \(progress.total)") }
        let toConfirm = enrichment.summary(of: model.library.index).toConfirm.count
        if toConfirm > 0 { return L("\(toConfirm) to confirm") }
        switch model.sweep.state {
        case .running(let done, let total): return L("People \(done) of \(total)")
        case .paused: return L("Paused")
        case .idle, .upToDate: return ""
        }
    }
}

/// Delete Listening Data with its confirmation. The dialog hangs on the button, so iOS points its popover at the
/// row that the listener tapped.
private struct DeleteListeningDataButton: View {
    @Environment(AppModel.self) private var model
    @Binding var failure: String?
    @State private var confirms = false

    var body: some View {
        Button("Delete Listening Data", role: .destructive) { confirms = true }
            .accessibilityIdentifier("delete-listening-data")
            .confirmationDialog("Delete Listening Data?", isPresented: $confirms, titleVisibility: .visible) {
                Button("Delete Listening Data", role: .destructive) {
                    do { try model.deleteListeningData() } catch { failure = error.localizedDescription }
                }
            } message: {
                Text(
                    "This removes the favourite works, the listening notes, the recent searches and the changes that wait of this server and user from this iPhone. You cannot undo this."
                )
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
        .pageTitle(classical ? L("Classical Albums") : L("Other Albums"))
    }
}
