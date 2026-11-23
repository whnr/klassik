import SwiftUI

/// The items of the ⋯ menu of a page and of the long-press menu of a row (specimen menu.html). Every menu keeps one
/// order and leaves out what its page cannot do: queue, download, tags. A state changes the words of an item and
/// the line below it, never its place.
struct PageMenu: Equatable, Sendable {
    /// What the page or the row shows. A work has several recordings, so it has no download and no tags.
    enum Kind: Sendable {
        case recording, album, work
    }

    /// Where the download of a recording or an album is.
    enum Download: Equatable, Sendable {
        /// `bytes` is nil when the server did not give the size of every track.
        case notDownloaded(bytes: Int64?)
        /// An album of which the listener downloaded some recordings one by one.
        case partly(downloaded: Int, of: Int)
        case downloading(share: Double)
        case downloaded(bytes: Int64)
    }

    enum Action: String, Sendable {
        case play, playNext, addToQueue, download, cancelDownload, removeDownload, tags

        /// UI tests find the items by these identifiers.
        var identifier: String {
            switch self {
            case .play: "menu-play"
            case .playNext: "play-next"
            case .addToQueue: "add-to-queue"
            case .download: "download"
            case .cancelDownload: "cancel-download"
            case .removeDownload: "remove-download"
            case .tags: "raw-tags"
            }
        }
    }

    struct Item: Equatable, Identifiable, Sendable {
        var action: Action
        var title: String
        /// The line below the title. Every download state shows here, never above the item.
        var subtitle: String?
        var systemImage: String
        var isDestructive = false
        var isDisabled = false
        var id: Action { action }
    }

    /// Groups of items, top to bottom. The menu draws a divider between two groups.
    var sections: [[Item]]

    /// - Parameters:
    ///   - download: Ignored for a work.
    ///   - needsServer: True when the server is out of reach. Download then is dimmed and says why.
    ///   - play: Only the long-press menu of a row has it, on top. A page has its own Play button.
    init(kind: Kind, download: Download, needsServer: Bool, play: Item? = nil) {
        var queue = [
            Item(action: .playNext, title: "Play Next", systemImage: "text.line.first.and.arrowtriangle.forward"),
            Item(action: .addToQueue, title: "Add to Queue", systemImage: "text.line.last.and.arrowtriangle.forward"),
        ]
        if let play { queue.insert(play, at: 0) }
        sections = [queue]
        guard kind != .work else { return }
        sections.append([Self.item(for: download, needsServer: needsServer)])
        sections.append([Item(action: .tags, title: "Tags and Grouping", systemImage: "tag")])
    }

    /// The first item of a row's long-press menu. The playing recording pauses and resumes, so its label says that.
    static func play(isPlaying: Bool, isPaused: Bool) -> Item {
        Item(
            action: .play, title: isPlaying ? (isPaused ? "Resume" : "Pause") : "Play",
            systemImage: isPlaying && !isPaused ? "pause" : "play")
    }

    private static func item(for download: Download, needsServer: Bool) -> Item {
        switch download {
        case .downloaded(let bytes):
            return Item(
                action: .removeDownload, title: "Remove Download", subtitle: "Downloaded, \(size(bytes))",
                systemImage: "trash", isDestructive: true)
        case .downloading(let share):
            let percent = Int((share * 100).rounded(.down))
            return Item(
                action: .cancelDownload, title: "Cancel Download",
                subtitle: needsServer ? "Downloading, waits for the server" : "Downloading, \(percent)\u{00A0}%",
                systemImage: "xmark.circle")
        case .notDownloaded, .partly:
            let line: String?
            if needsServer {
                line = "Needs the server"
            } else if case .partly(let done, let total) = download {
                line = "\(done) of \(total) recordings downloaded"
            } else if case .notDownloaded(let bytes?) = download {
                line = size(bytes)
            } else {
                line = nil
            }
            return Item(
                action: .download, title: "Download", subtitle: line, systemImage: "arrow.down.circle",
                isDisabled: needsServer)
        }
    }

    static func size(_ bytes: Int64) -> String {
        bytes.formatted(.byteCount(style: .file))
    }

    /// The download state of a recording or an album.
    /// - Parameter parts: The recordings of an album, by ID. Empty for a recording.
    static func download(
        of recording: WorkIndex.Recording, parts: [String], downloads: [TrackStore.Download],
        progress: [String: Double]
    ) -> Download {
        if let stored = downloads.first(where: { $0.id == recording.id }) { return .downloaded(bytes: stored.bytes) }
        if let share = progress[recording.id] { return .downloading(share: share) }
        let stored = Set(downloads.map(\.id))
        let done = parts.filter(stored.contains).count
        if parts.count > 1, done > 0 { return .partly(downloaded: done, of: parts.count) }
        let sizes = recording.songs.map(\.size)
        guard !sizes.isEmpty, sizes.allSatisfy({ $0 != nil }) else { return .notDownloaded(bytes: nil) }
        return .notDownloaded(bytes: sizes.reduce(0) { $0 + ($1 ?? 0) })
    }
}

/// The items of a page menu as system menu buttons, one section for each group.
struct PageMenuItems: View {
    let menu: PageMenu
    let run: (PageMenu.Action) -> Void

    var body: some View {
        ForEach(Array(menu.sections.enumerated()), id: \.offset) { _, items in
            Section {
                ForEach(items) { item in
                    Button(role: item.isDestructive ? .destructive : nil) {
                        run(item.action)
                    } label: {
                        // A system menu reads a plain label: the first text is the title, a second text the line
                        // below it, the image the symbol. Inside a Label it drops the second text.
                        Text(item.title)
                        if let subtitle = item.subtitle { Text(subtitle) }
                        Image(systemName: item.systemImage)
                    }
                    .disabled(item.isDisabled)
                    .accessibilityIdentifier(item.action.identifier)
                }
            }
        }
    }
}

/// What a page menu or a row menu acts on.
struct PageMenuTarget {
    var kind: PageMenu.Kind
    /// For a work, its top recording: Play Next and Add to Queue queue it.
    var item: QueueItem
    var album: WorkIndex.Album?

    @MainActor func menu(_ model: AppModel, play: PageMenu.Item? = nil) -> PageMenu {
        let tracks = model.tracks
        let needsServer = model.client == nil || !tracks.networkAllowed || model.serverTrouble == .unreachable
        let download = PageMenu.download(
            of: item.recording, parts: album?.parts.map(\.recordingID) ?? [], downloads: tracks.downloads,
            progress: tracks.progress)
        return PageMenu(kind: kind, download: download, needsServer: needsServer, play: play)
    }

    /// Each action changes the state at once; the server work runs in the background.
    @MainActor func run(_ action: PageMenu.Action, model: AppModel, navigator: AppNavigator) {
        let tracks = model.tracks
        let recording = item.recording
        switch action {
        case .play: model.playback.play(item)
        case .playNext: model.playback.playNext(item)
        case .addToQueue: model.playback.addToQueue(item)
        case .download:
            if let client = model.client { tracks.download(recording, title: item.work.title, client: client) }
        case .cancelDownload: tracks.cancelDownload(recording.id)
        case .removeDownload:
            if let stored = tracks.downloads.first(where: { $0.id == recording.id }) { tracks.remove(stored) }
        case .tags:
            navigator.open(.rawTags(work: item.work.id, recording: recording.id), in: navigator.selection)
        }
    }
}

/// The ⋯ button at the top right of a recording, album or work page.
struct PageMenuButton: View {
    @Environment(AppModel.self) private var model
    @Environment(AppNavigator.self) private var navigator
    let target: PageMenuTarget

    var body: some View {
        Menu {
            PageMenuItems(menu: target.menu(model)) { target.run($0, model: model, navigator: navigator) }
        } label: {
            Label("More", systemImage: "ellipsis")
        }
        .accessibilityIdentifier("page-menu")
    }
}
