import SwiftUI

/// A page that a link pushes onto the stack of a place. A page names its thing by ID, so that a page follows
/// the library when a sync changes it.
enum Page: Hashable {
    case settings
    case composers
    case favourites
    case composer(String)
    case work(String)
    case recording(work: String, recording: String)
    case rawTags(work: String, recording: String)
    case sources(work: String)
    case performer(String)
    case albums(classical: Bool)
    case album(String)
    case musicBrainz
    case worksToConfirm
    case worksWithoutMatch
    case classicalRules
    case localStorage
    case serverConnection
    case swipeActions
    case diagnostics
    case licences
    case gaplessTest
    case gaplessAlbum(String)

    @MainActor init?(albumPart part: WorkIndex.Album.Part, in library: Library) {
        guard library.index.work(part.workID) != nil else { return nil }
        self = .recording(work: part.workID, recording: part.recordingID)
    }
}

typealias AppNavigator = Navigator<Page>

extension LibraryRow {
    var page: Page {
        switch self {
        case .composers: .composers
        case .favourites: .favourites
        }
    }
}

extension Library {
    /// A recording of the index, else a whole album: the pages of an album list name the album by its key.
    func recording(work workID: String, recording recordingID: String, playing: QueueItem? = nil) -> (
        work: WorkIndex.Work, recording: WorkIndex.Recording
    )? {
        // The queue can hold only some movements, in another client's order.
        if let playing, playing.work.id == workID, playing.recording.id == recordingID {
            return (playing.work, playing.recording)
        }
        if let work = index.work(workID), let recording = work.recordings.first(where: { $0.id == recordingID }) {
            return (work, recording)
        }
        let prefix = "album|"
        guard recordingID.hasPrefix(prefix) else { return nil }
        return album(String(recordingID.dropFirst(prefix.count))).map { ($0.work, $0.recording) }
    }
}

extension Page {
    init(playing item: QueueItem) {
        if let key = item.recording.albumKey {
            self = .album(key)
        } else {
            self = .recording(work: item.work.id, recording: item.recording.id)
        }
    }

    /// The short name that a back arrow gives to the page behind it.
    @MainActor func backTitle(in library: Library) -> String {
        let index = library.index
        switch self {
        case .settings: return L("Settings")
        case .composers: return L("Composers")
        case .favourites: return L("Favourites")
        case .composer(let name): return name
        case .work(let id): return index.work(id)?.title ?? L("Work")
        case .recording(let work, let recording):
            return library.recording(work: work, recording: recording)?.work.title ?? L("Recording")
        case .rawTags: return L("Tags")
        case .sources: return L("Dates and Sources")
        case .performer(let name): return name
        case .albums(let classical): return classical ? L("Classical Albums") : L("Other Albums")
        case .album(let key): return library.album(key)?.title ?? L("Album")
        case .musicBrainz: return L("MusicBrainz")
        case .worksToConfirm: return L("To Confirm")
        case .worksWithoutMatch: return L("No Match")
        case .classicalRules: return L("Classical Rules")
        case .localStorage: return L("Local Storage")
        case .serverConnection: return L("Server Connection")
        case .swipeActions: return L("Swipe Actions")
        case .diagnostics: return L("Diagnostics")
        case .licences: return L("Licences")
        case .gaplessTest: return "Gapless Test"
        // The page loads the album name, so the arrow cannot name it.
        case .gaplessAlbum: return L("Album")
        }
    }
}

/// A person page needs decoded local pixels before the system starts its push transition.
struct PersonPageLink<Label: View>: View {
    @Environment(AppModel.self) private var model
    @Environment(AppNavigator.self) private var navigator
    let page: Page
    var disclosure = true
    @ViewBuilder let label: Label
    @State private var opening = false

    var body: some View {
        Button {
            guard !opening else { return }
            opening = true
            let place = navigator.selection
            let stack = navigator.pages(in: place)
            Task {
                await model.preparePortrait(for: page, opening: true)
                opening = false
                guard navigator.selection == place, navigator.pages(in: place) == stack else { return }
                navigator.open(page, in: place)
            }
        } label: {
            Group {
                if disclosure {
                    DisclosureRow { label }
                } else {
                    label
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        // A row decodes its picture when the list is about to show it, so a tap finds it ready.
        .task { await model.preparePortrait(for: page) }
    }
}

/// Counts and carets must stay at the trailing edge when a title wraps.
struct DisclosureRow<Label: View>: View {
    @ViewBuilder let label: Label

    var body: some View {
        HStack(spacing: Layout.rowGap) {
            label
                .labeledContentStyle(TrailingValue())
                .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.right")
                .typeStyle(.footnote)
                .fontWeight(.semibold)
                .foregroundStyle(Palette.textTertiary)
                .accessibilityHidden(true)
        }
    }
}

/// Counts must remain aligned when their labels wrap.
struct TrailingValue: LabeledContentStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: Layout.rowGap) {
            configuration.label
                .frame(maxWidth: .infinity, alignment: .leading)
            configuration.content
                .foregroundStyle(.secondary)
                .fixedSize()
        }
    }
}

extension AppModel {
    /// Only local decoding can delay a push. The first image pass must never block browsing on a network request.
    func preparePortrait(for page: Page, opening: Bool = false) async {
        let portrait: PersonPortrait?
        switch page {
        case .composer(let name): portrait = people.facts(ofComposer: name)?.portrait
        case .performer(let name): portrait = people.facts(ofPerformer: name)?.portrait
        default: return
        }
        guard let portrait, PortraitLoader.ready(portrait) == nil else { return }
        let local = PortraitLoader.stored({ _ in throw URLError(.notConnectedToInternet) }, in: { .pictures })
        _ = await PortraitLoader.load(portrait, screen: PortraitLoader.deviceScreen, fetch: local, opening: opening)
    }
}

/// The view of a page. A page whose thing a sync has removed says so.
struct PageView: View {
    @Environment(AppModel.self) private var model
    let page: Page

    var body: some View {
        let library = model.library
        let index = library.index
        switch page {
        case .settings:
            SettingsView()
        case .composers:
            ComposersView()
        case .favourites:
            FavouritesView()
        case .composer(let name):
            if let composer = index.composer(named: name) { ComposerPage(composer: composer) } else { Gone() }
        case .work(let id):
            if let work = index.work(id) { WorkView(work: work) } else { Gone() }
        case .recording(let work, let recording):
            if let found = library.recording(work: work, recording: recording, playing: model.playback.item) {
                RecordingView(work: found.work, recording: found.recording)
            } else {
                Gone()
            }
        case .rawTags(let work, let recording):
            if let found = library.recording(work: work, recording: recording, playing: model.playback.item) {
                RawTagsView(work: found.work, recording: found.recording)
            } else {
                Gone()
            }
        case .sources(let id):
            if let work = index.work(id) { WorkSourcesView(work: work) } else { Gone() }
        case .performer(let name):
            if let performer = index.performer(named: name) { PerformerPage(performer: performer) } else { Gone() }
        case .albums(let classical):
            AlbumsView(classical: classical)
        case .album(let key):
            if let album = library.album(key) {
                RecordingView(work: album.work, recording: album.recording, album: album)
            } else {
                Gone()
            }
        case .musicBrainz:
            EnrichmentStatusView()
        case .worksToConfirm:
            WorkListView(title: L("To Confirm"), works: model.enrichment.summary(of: index).toConfirm)
        case .worksWithoutMatch:
            WorkListView(title: L("No Match"), works: model.enrichment.summary(of: index).unmatched)
        case .classicalRules:
            ClassicalRulesView()
        case .localStorage:
            LocalStorageView()
        case .serverConnection:
            ServerConnectionView()
        case .swipeActions:
            SwipeSettingsView()
        case .diagnostics:
            DiagnosticsView()
        case .licences:
            LicencesView()
        case .gaplessTest:
            GaplessTestView()
        case .gaplessAlbum(let id):
            GaplessAlbumView(albumID: id)
        }
    }
}

private struct Gone: View {
    var body: some View {
        ContentUnavailableView("Page Not Found", systemImage: "questionmark.folder")
    }
}

/// A page as the URL of a link inside text, such as a name in a role line. Text runs cannot hold an action, so the
/// page that shows the text opens the page of the URL.
enum PageLink {
    static let scheme = "klassik-page"

    static func url(_ page: Page) -> URL? {
        let target: (host: String, id: String)
        switch page {
        case .composer(let name): target = ("composer", name)
        case .performer(let name): target = ("performer", name)
        case .album(let key): target = ("album", key)
        default: return nil
        }
        var parts = URLComponents()
        parts.scheme = scheme
        parts.host = target.host
        parts.queryItems = [URLQueryItem(name: "id", value: target.id)]
        return parts.url
    }

    static func page(_ url: URL) -> Page? {
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false), parts.scheme == scheme,
            let value = parts.queryItems?.first(where: { $0.name == "id" })?.value
        else { return nil }
        switch parts.host {
        case "composer": return .composer(value)
        case "performer": return .performer(value)
        case "album": return .album(value)
        default: return nil
        }
    }
}
