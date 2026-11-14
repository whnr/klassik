import SwiftUI

/// A page that a link pushes onto the stack of a place. A page names its thing by ID, so that a page follows
/// the library when a sync changes it.
enum Page: Hashable {
    case settings
    case composers
    case favourites
    case performers
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
    case classicalFilter
    case localStorage
    case swipeActions
    case diagnostics
    case licences
    case gaplessTest
    case gaplessAlbum(String)
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

extension WorkIndex {
    func composer(named name: String) -> Composer? {
        composers.first { $0.id == name }
    }

    func work(_ id: String) -> Work? {
        composers.lazy.flatMap(\.works).first { $0.id == id }
    }

    func performer(named name: String) -> Performer? {
        performers.first { $0.id == name }
    }
}

extension Library {
    /// A recording of the index, else a whole album: the pages of an album list name the album by its key.
    func recording(work workID: String, recording recordingID: String) -> (
        work: WorkIndex.Work, recording: WorkIndex.Recording
    )? {
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
        case .settings: return "Settings"
        case .composers: return "Composers"
        case .favourites: return "Favourites"
        case .performers: return "Performers"
        case .composer(let name): return name
        case .work(let id): return index.work(id)?.title ?? "Work"
        case .recording(let work, let recording):
            return library.recording(work: work, recording: recording)?.work.title ?? "Recording"
        case .rawTags: return "Tags"
        case .sources: return "Dates and Sources"
        case .performer(let name): return name
        case .albums(let classical): return classical ? "Classical Albums" : "Other Albums"
        case .album(let key): return library.album(key)?.title ?? "Album"
        case .musicBrainz: return "MusicBrainz"
        case .worksToConfirm: return "To Confirm"
        case .worksWithoutMatch: return "No Match"
        case .classicalFilter: return "Classical Filter"
        case .localStorage: return "Local Storage"
        case .swipeActions: return "Swipe Actions"
        case .diagnostics: return "Diagnostics"
        case .licences: return "Licences"
        case .gaplessTest: return "Gapless Test"
        // The page loads the album name, so the arrow cannot name it.
        case .gaplessAlbum: return "Album"
        }
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
        case .performers:
            PerformersView()
        case .composer(let name):
            if let composer = index.composer(named: name) { ComposerPage(composer: composer) } else { Gone() }
        case .work(let id):
            if let work = index.work(id) { WorkView(work: work) } else { Gone() }
        case .recording(let work, let recording):
            if let found = library.recording(work: work, recording: recording) {
                RecordingView(work: found.work, recording: found.recording)
            } else {
                Gone()
            }
        case .rawTags(let work, let recording):
            if let found = library.recording(work: work, recording: recording) {
                RawTagsView(work: found.work, recording: found.recording)
            } else {
                Gone()
            }
        case .sources(let id):
            if let work = index.work(id) { WorkSourcesView(work: work) } else { Gone() }
        case .performer(let name):
            if let performer = index.performer(named: name) { PerformerView(performer: performer) } else { Gone() }
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
            WorkListView(title: "To Confirm", works: model.enrichment.summary(of: index).toConfirm)
        case .worksWithoutMatch:
            WorkListView(title: "No Match", works: model.enrichment.summary(of: index).unmatched)
        case .classicalFilter:
            FilterView()
        case .localStorage:
            LocalStorageView()
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
