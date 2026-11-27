import SwiftUI

/// The name of the favourite action. On a favourite it takes the favourite away.
enum FavouriteAction {
    static func title(isSet: Bool) -> String { isSet ? L("Unfavourite") : L("Favourite") }
}

/// The actions of a row that stands for one recording or one album. Trailing swipe: the queue. Leading swipe:
/// download and favourites. The long-press menu holds Play, then the page menu of the row's item, then the favourite.
private struct ItemActions: ViewModifier {
    @Environment(AppModel.self) private var model
    @Environment(AppNavigator.self) private var navigator
    let item: QueueItem
    /// Only recordings and albums download, never a whole work.
    let downloads: Bool
    let favourite: Bool
    let favouriteWork: Bool
    let favouriteAlbum: Bool

    private var hasFavourite: Bool { favourite || favouriteWork || favouriteAlbum }
    private var albumID: String? { favouriteAlbum ? item.recording.songs.first?.albumId : nil }

    func body(content: Content) -> some View {
        content
            .swipeActions(edge: .trailing) {
                ForEach(SwipeSettings.actions(model.swipes.trailing)) { button(for: $0) }
            }
            .swipeActions(edge: .leading) {
                ForEach(SwipeSettings.actions(model.swipes.leading)) { button(for: $0) }
            }
            .contextMenu {
                let target = PageMenuTarget(kind: kind, item: item, album: album)
                let player = model.playback
                let isPlaying = player.recording?.id == item.recording.id
                let play = PageMenu.play(isPlaying: isPlaying, isPaused: player.isPaused)
                PageMenuItems(menu: target.menu(model, play: play)) {
                    target.run($0, model: model, navigator: navigator)
                }
                // Rows have no fermata of their own to tap, so the favourite stays in their menu.
                if hasFavourite { Section { favouriteButton } }
            }
    }

    /// The album of an album row: its menu says how many recordings of it are downloaded.
    private var album: WorkIndex.Album? {
        guard kind == .album else { return nil }
        return item.recording.albumKey.flatMap { model.library.album($0) }
    }

    /// Only recordings and albums download and show tags; a work row queues its top recording.
    private var kind: PageMenu.Kind {
        guard downloads else { return .work }
        return item.recording.isAlbum ? .album : .recording
    }

    /// A row that cannot do an action leaves it out: works never download.
    @ViewBuilder private func button(for action: SwipeAction) -> some View {
        switch action {
        case .playNext:
            Button("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward") { playNext() }
                .tint(Palette.swipePlayNext.color)
        case .addToQueue:
            Button("Add to Queue", systemImage: "text.line.last.and.arrowtriangle.forward") { addToQueue() }
                .tint(Palette.swipeAddToQueue.color)
        case .download:
            if downloads { downloadButton.tint(Palette.swipeDownload.color) }
        case .favourite:
            if hasFavourite { favouriteButton.tint(Palette.swipeFavourite.color) }
        }
    }

    @ViewBuilder private var downloadButton: some View {
        let tracks = model.tracks
        if let download = tracks.downloads.first(where: { $0.id == item.recording.id }) {
            Button("Remove Download", systemImage: "trash") { tracks.remove(download) }
        } else if tracks.progress[item.recording.id] != nil {
            Button("Cancel Download", systemImage: "xmark") { tracks.cancelDownload(item.recording.id) }
        } else {
            // A plain glyph, as the queue actions have: a circled glyph draws as a ring inside the pill.
            let title = tracks.failures[item.recording.id] == nil ? L("Download") : L("Download Again")
            Button(title, systemImage: "arrow.down") {
                if let client = model.client {
                    tracks.download(item.recording, title: item.work.title, client: client)
                }
            }
        }
    }

    private var favouriteButton: some View {
        let order = model.recordingOrder
        let isSet: Bool
        if let albumID {
            isSet = order.isFavourite(album: albumID)
        } else if favouriteWork {
            isSet = order.isFavourite(item.work)
        } else {
            isSet = order.isFavourite(item.recording, of: item.work)
        }
        return Button {
            if let albumID {
                order.toggleAtOnce(album: albumID)
            } else if favouriteWork {
                order.toggleAtOnce(item.work)
            } else {
                order.toggleAtOnce(item.recording, of: item.work)
            }
        } label: {
            Label {
                Text(FavouriteAction.title(isSet: isSet))
            } icon: {
                Image(uiImage: FermataShape.icon)
            }
        }
        .accessibilityIdentifier("favourite-action")
        .accessibilityValue(isSet ? "Favourite" : "Not a favourite")
        .disabled(model.recordingOrder.isSaving)
    }

    private func playNext() {
        model.playback.playNext(item)
    }

    private func addToQueue() {
        model.playback.addToQueue(item)
    }
}

extension View {
    @ViewBuilder func itemActions(
        _ item: QueueItem?, downloads: Bool = false, favourite: Bool = false, favouriteWork: Bool = false,
        favouriteAlbum: Bool = false
    ) -> some View {
        if let item {
            modifier(
                ItemActions(
                    item: item, downloads: downloads, favourite: favourite, favouriteWork: favouriteWork,
                    favouriteAlbum: favouriteAlbum))
        } else {
            self
        }
    }
}

extension RecordingOrder {
    /// A favourite changes its mark and its place in the list at once, with no animation. The server call follows.
    func toggleAtOnce(_ recording: WorkIndex.Recording, of work: WorkIndex.Work) {
        guard let confirm = withoutAnimation({ begin(recording, of: work) }) else { return }
        Task { await confirm() }
    }

    func toggleAtOnce(_ work: WorkIndex.Work) {
        withoutAnimation { toggle(work) }
    }

    func toggleAtOnce(album id: String) {
        guard let confirm = withoutAnimation({ begin(album: id) }) else { return }
        Task { await confirm() }
    }

    func toggleAtOnce(person name: String) {
        guard let confirm = withoutAnimation({ begin(person: name) }) else { return }
        Task { await confirm() }
    }
}

/// Runs a change with no animation, also inside a swipe action or a button that animates.
@MainActor func withoutAnimation<Result>(_ change: () -> Result) -> Result {
    var transaction = Transaction()
    transaction.disablesAnimations = true
    return withTransaction(transaction, change)
}

/// A small mark on rows that play without the server.
struct OfflineHint: View {
    let isOffline: Bool

    var body: some View {
        if isOffline {
            Image(systemName: "arrow.down.circle.fill")
                .typeStyle(.caption1)
                .foregroundStyle(Palette.textSecondary)
                .accessibilityLabel("Available offline")
        }
    }
}

struct WorkRow: View {
    @Environment(AppModel.self) private var model
    let work: WorkIndex.Work
    @ScaledMetric(space: .inGroup) private var gap: CGFloat

    var body: some View {
        if let album = work.albumKey.flatMap({ model.library.index.album($0) }) {
            NavigationLink(value: Page.album(album.id)) {
                VStack(alignment: .leading, spacing: gap) {
                    MarkedTitle(title: album.title, isFavourite: model.recordingOrder.isFavourite(album: album.id))
                        .ink()
                    Text(WorkIndex.Recording.count(album.tracks.count, "track"))
                        .typeStyle(.footnote)
                        .foregroundStyle(Palette.textSecondary)
                }
            }
            .itemActions(album.item, downloads: true, favouriteAlbum: true)
            .accessibilityIdentifier("album")
        } else {
            NavigationLink(value: Page.work(work.id)) {
                VStack(alignment: .leading, spacing: gap) {
                    MarkedTitle(title: work.title, isFavourite: model.recordingOrder.isFavourite(work))
                        .ink()
                    Text(Self.detail(of: work, composed: model.enrichment.composed(work)?.span.text))
                        .typeStyle(.footnote)
                        .foregroundStyle(Palette.textSecondary)
                }
            }
            .itemActions(
                model.recordingOrder.reference(of: work).map { QueueItem(work: work, recording: $0) }, favourite: true,
                favouriteWork: true
            )
            .accessibilityIdentifier("work")
        }
    }

    /// The one line under the title: when the work was composed, then the recordings, as
    /// "Composed 1844, 1 recording". The track titles stay on the work page: in a list they
    /// repeat the title or name one movement.
    nonisolated static func detail(of work: WorkIndex.Work, composed: String?) -> String {
        let recordings = WorkIndex.Recording.count(work.recordings.count, "recording")
        guard let composed else { return recordings }
        return L("Composed\u{00A0}\(composed), \(recordings)")
    }
}

/// The work cover and composer lead the playback capsules and recording list, as work.html draws them.
struct WorkView: View {
    @Environment(AppModel.self) private var model
    let work: WorkIndex.Work

    @AppStorage(ComposerWorks.separatesPartialKey) private var separatesPartial = true

    private var lists: (recordings: [RecordingOrder.Row], partial: [RecordingOrder.Row]) {
        model.recordingOrder.lists(of: work, separatingPartial: separatesPartial)
    }

    private var reference: WorkIndex.Recording? {
        model.recordingOrder.reference(of: work, separatingPartial: separatesPartial)
    }

    var body: some View {
        PageList {
            FavouriteTitle(
                title: work.title, isSet: model.recordingOrder.isFavourite(work),
                action: { model.recordingOrder.toggleAtOnce(work) }
            )
            .disabled(model.recordingOrder.isSaving)
            .typeStyle(Layout.pageTitle)
            .accessibilityAddTraits(.isHeader)
            .accessibilityIdentifier("favourite-work")
            .listRowSeparator(.hidden)
            .pageEdges(top: Layout.headTop, bottom: Layout.metaTop)
            WorkHeader(work: work)
                .listRowSeparator(.hidden)
                .pageEdges(bottom: Layout.headBottom)
            if let recording = reference {
                let player = model.playback
                // While any recording of the work plays, the pill pauses it. Else it plays the top of the list.
                let playsThisWork = player.item?.work.id == work.id
                HStack(spacing: Layout.buttonRowGap) {
                    Button {
                        if playsThisWork {
                            player.togglePause()
                        } else {
                            player.play(queue: [QueueItem(work: work, recording: recording)])
                        }
                    } label: {
                        CapsuleLabel(
                            title: playsThisWork ? (player.isPaused ? "Resume" : "Pause") : "Play top recording",
                            systemImage: playsThisWork && !player.isPaused ? "pause.fill" : "play.fill", filled: true)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("play-work")
                }
                .listRowSeparator(.hidden)
                .pageEdges(top: Layout.buttonRowTop)
            }

            let lists = lists
            if !lists.recordings.isEmpty || lists.partial.isEmpty {
                recordingsSection("Recordings", rows: lists.recordings, footnote: lists.partial.isEmpty)
            }
            if !lists.partial.isEmpty {
                recordingsSection("Partial recordings", rows: lists.partial, footnote: true)
            }
        }
        .navigationTitle(work.title)
        .navigationBarTitleDisplayMode(.inline)
        .environment(\.pageHeading, "")
        .toolbar {
            // The menu queues the recording that Play plays: the top of the list.
            if let recording = reference {
                ToolbarItem(placement: .topBarTrailing) {
                    PageMenuButton(
                        target: PageMenuTarget(kind: .work, item: QueueItem(work: work, recording: recording)))
                }
            }
        }
        .onAppear {
            let lists = lists
            model.sweep.prefer(performers: (lists.recordings + lists.partial).flatMap(\.recording.performerNames))
        }
    }

    private func plays(_ recording: WorkIndex.Recording) -> Bool {
        guard let item = model.playback.item else { return false }
        return item.work.id == work.id && item.recording.id == recording.id
    }

    /// The footnote closes the last list only, so it appears once.
    @ViewBuilder private func recordingsSection(_ title: String, rows: [RecordingOrder.Row], footnote: Bool)
        -> some View
    {
        Section {
            CountedHeading(title, count: rows.count)
            ForEach(rows) { row in
                let recording = row.recording
                let isPlaying = plays(recording)
                NavigationLink(value: Page.recording(work: work.id, recording: recording.id)) {
                    RecordingRow(
                        recording: recording, isFavourite: row.isFavourite, reason: row.reason,
                        isPlaying: isPlaying)
                }
                // The row draws its own trailing control on the top edge (specimen `.row.top`).
                .navigationLinkIndicatorVisibility(.hidden)
                // Tint identifies the playing recording while the listener browses.
                .playingRow(isPlaying)
                .itemActions(QueueItem(work: work, recording: recording), downloads: true, favourite: true)
                .accessibilityIdentifier("recording")
                .itemSeparator(first: row.id == rows.first?.id, last: row.id == rows.last?.id)
            }
            if footnote {
                Text("Favourite recordings come first. Then the newest.")
                    .typeStyle(Layout.footnote)
                    .foregroundStyle(Palette.textSecondary)
                    .listRowSeparator(.hidden)
                    .pageEdges(top: Layout.workFootTop + Layout.footTop)
            }
        }
    }
}

/// A section heading with its count in a lighter step: "Recordings (3)".
/// With `fold`, the heading is a button that folds its section; `fold` says whether the section is folded.
struct CountedHeading: View {
    @Environment(\.isPageList) private var isPageList
    let title: String
    let count: Int
    let fold: (isFolded: Bool, toggle: () -> Void)?

    init(_ title: String, count: Int, fold: (isFolded: Bool, toggle: () -> Void)? = nil) {
        self.title = title
        self.count = count
        self.fold = fold
    }

    var body: some View {
        Group {
            if let fold {
                Button(action: fold.toggle) {
                    HStack(alignment: .firstTextBaseline) {
                        heading
                        Image(systemName: fold.isFolded ? "chevron.right" : "chevron.down")
                            .typeStyle(.footnote)
                            .foregroundStyle(Palette.textSecondary)
                            .accessibilityHidden(true)
                    }
                    .contentShape(Rectangle())
                }
                // A row of a list sends a tap anywhere on it to a bordered button.
                .buttonStyle(.borderless)
                .accessibilityIdentifier("section-fold")
                .accessibilityValue(fold.isFolded ? L("Folded") : L("Open"))
                .accessibilityHint(fold.isFolded ? L("Opens the section") : L("Folds the section"))
            } else {
                heading
            }
        }
        .pageSectionHeader(isPageList)
    }

    private var heading: some View {
        Text("\(Text(LocalizedStringKey(title))) \(Text("(\(count))").foregroundStyle(Palette.textSecondary))")
            .typeStyle(Layout.sectionHeading)
            .foregroundStyle(Palette.textPrimary)
            .textCase(nil)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: fold == nil ? .infinity : nil, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("section-heading")
    }
}

/// Under the title: the composer as a link, when the work was composed, and what the tracks add to the title.
private struct WorkHeader: View {
    @Environment(AppModel.self) private var model
    let work: WorkIndex.Work
    @ScaledMetric(space: .inGroup) private var gap: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: gap) {
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                PersonPageLink(page: .composer(work.composer), disclosure: false) {
                    Text(work.composer)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Palette.tint)
                .accessibilityIdentifier("work-composer")
                if work.isTagged {
                    composed
                }
            }
            .typeStyle(.subheadline)
            if !work.context.isEmpty {
                Text(work.context)
                    .typeStyle(.subheadline)
                    .foregroundStyle(Palette.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// When the work was composed, as plain text.
    private var composed: some View {
        let enrichment = model.enrichment
        let text =
            if let composed = enrichment.composed(work) {
                composed.span.text
            } else {
                enrichment.isRunning ? "…" : L("unknown")
            }
        return Text(", composed\u{00A0}\(text)")
            .foregroundStyle(Palette.textSecondary)
            .accessibilityIdentifier("composed")
    }
}

/// A recording on the work page: the principal names first, then the ensembles and other names, then the facts in
/// prose. No role labels, and no truncation: a long name wraps.
private struct RecordingRow: View {
    let recording: WorkIndex.Recording
    let isFavourite: Bool
    let reason: String?
    let isPlaying: Bool
    @Environment(AppModel.self) private var model
    @ScaledMetric(relativeTo: .body) private var cover = Layout.rowCover
    @ScaledMetric(space: .inGroup) private var gap: CGFloat
    @ScaledMetric(relativeTo: .body) private var fermataGap = Layout.fermataGap * TypeStyle.body.size

    /// The conductor and soloists tell recordings apart. Without them the ensembles lead.
    private var lead: [String] {
        let people = recording.principalNames.filter { $0.kind != .ensemble }
        return (people.isEmpty ? recording.principalNames : people).flatMap(\.names)
    }

    private var rest: [String] {
        let people = recording.principalNames.filter { $0.kind != .ensemble }
        let ensembles = people.isEmpty ? [] : recording.principalNames.filter { $0.kind == .ensemble }
        return (ensembles + recording.otherNames).flatMap(\.names)
    }

    var body: some View {
        HStack(alignment: .top, spacing: Layout.rowGap) {
            CoverImage(song: recording.songs.first, points: cover)
                .frame(width: cover, height: cover)
                .clipShape(.rect(cornerRadius: Layout.coverCorner))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: gap) {
                title
                if !rest.isEmpty {
                    Text(Roles.Line.list(rest))
                        .typeStyle(.subheadline)
                        .ink()
                }
                Text(recording.facts())
                    .typeStyle(.subheadline)
                    .foregroundStyle(Palette.textSecondary)
                if let reason {
                    Text(reason).typeStyle(.footnote).foregroundStyle(Palette.textSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // Every row keeps the room of the round button, so the playing row tints in place and its text does not
            // rewrap.
            Group {
                if isPlaying {
                    slot
                } else {
                    Image(systemName: "chevron.right")
                        .typeStyle(.footnote)
                        .fontWeight(.semibold)
                        .foregroundStyle(Palette.textTertiary)
                        .accessibilityHidden(true)
                }
            }
            .frame(width: Layout.roundButton, alignment: .trailing)
        }
    }

    private var title: some View {
        HStack(alignment: .firstTextBaseline, spacing: fermataGap) {
            Text(lead.isEmpty ? recording.album : Roles.Line.list(lead))
                .ink()
                .fixedSize(horizontal: false, vertical: true)
            if isFavourite {
                FermataMark(isSet: true)
            }
        }
    }

    /// The round button of the playing row pauses and resumes it, so the listener need not leave the page.
    private var slot: some View {
        let player = model.playback
        return Button {
            player.togglePause()
        } label: {
            Image(systemName: player.isPaused ? "play.fill" : "pause.fill")
                .typeStyle(.caption1)
                .foregroundStyle(Palette.tint)
                .frame(width: Layout.roundButton, height: Layout.roundButton)
                .background(Palette.fillQuiet, in: .circle)
                .contentShape(.rect.inset(by: (Layout.roundButton - Measure.hitTarget) / 2))
                // The button must not make the row taller than its text (specimen `.row .round`).
                .padding(.vertical, Layout.roundInRow)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(player.isPaused ? "Resume" : "Pause")
        .accessibilityIdentifier("recording-slot")
    }
}

/// The page of a recording or album, and the content of the player overlay: the header holds what every
/// track shares, and a row holds what differs. Only the overlay is the player. It alone shows the playing
/// row with its playback bar, and the next queue item at its end.
struct RecordingView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppNavigator.self) private var navigator
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let work: WorkIndex.Work
    let recording: WorkIndex.Recording
    /// Set on the album page, which lists the tracks of the album.
    var album: WorkIndex.Album?
    var isOverlay = false
    /// The drag that the heading of the player takes to close it. Set on the overlay only.
    var closeDrag: PlayerCloseDrag?
    /// The rows that the listener opened, by track position.
    @State private var opened: Set<Int> = []
    @State private var spell = QuietSpell()
    /// The note that the listener writes in the playing row. It stays while the listener scrubs.
    @State private var draft: NoteDraft?
    /// Where the notes of each row live, by track position.
    @State private var places: [NotePlace?] = []
    /// True while a drag that began with the rows at the top runs. Only such a drag closes the player.
    @State private var dragFromTop = false

    private var isPlayingThis: Bool { model.playback.recording?.id == recording.id }

    /// The whole album, if it holds more than this recording.
    private var wholeAlbum: QueueItem? {
        guard !recording.isAlbum, let key = recording.songs.first?.albumKey,
            let whole = model.library.album(key), whole.tracks.count > recording.songs.count
        else { return nil }
        return whole.item
    }

    var body: some View {
        let player = model.playback
        let page = PlayerPage(recording: recording)
        ScrollViewReader { proxy in
            PageList {
                Section {
                    hero(page)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    if isPlayingThis, let error = player.error {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(Palette.textPrimary)
                            .listRowSeparator(.hidden)
                    }
                }

                if let album, album.showsWorkHeadings {
                    ForEach(album.blocks) { block in
                        Section {
                            heading(of: block)
                                .pageSectionHeader(true)
                            ForEach(Array(block.tracks.enumerated()), id: \.element.id) { offset, song in
                                movementRow(
                                    song, at: block.start + offset, page: page,
                                    title: album.title(of: song, in: block)
                                )
                                .itemSeparator(first: offset == 0, last: offset == block.tracks.count - 1)
                            }
                        }
                    }
                } else {
                    // The rows follow the header with no heading.
                    Section {
                        ForEach(Array(recording.songs.enumerated()), id: \.element.id) { index, song in
                            movementRow(song, at: index, page: page, title: recording.title(of: song))
                                .itemSeparator(first: index == 0, last: index == recording.songs.count - 1)
                        }
                    }
                }

                if isOverlay { tail }
            }
            // A finger on the page, or a scroll that it started, holds the rows. The spell begins when the page is still.
            // A scroll by the app itself is not a touch. The list has no tap gesture of its own, so row controls keep their
            // taps. Each control touches the spell itself.
            .onScrollPhaseChange { old, phase, context in
                spell.touching(phase == .tracking || phase == .interacting || phase == .decelerating)
                // A drag that starts at the top and pulls past it closes the player, as a system sheet closes. A
                // drag that scrolls up to the top only bounces. The rubber band halves the drag, so 60 points of
                // pull ask for about 120 points of finger travel, the travel that closes the player at its handle.
                let pull = -(context.geometry.contentOffset.y + context.geometry.contentInsets.top)
                if phase == .interacting, old != .interacting { dragFromTop = pull >= -1 }
                if isOverlay, dragFromTop, old == .interacting, phase != .interacting, pull > 60 {
                    navigator.closePlayer()
                }
            }
            .onChange(of: model.isScrubbing) { _, scrubbing in spell.hold(scrubbing) }
            .onChange(of: draft != nil) { _, writing in spell.writing(writing) }
            // Each second, after a quiet spell, the player brings the playing row back.
            .task(id: isOverlay && isPlayingThis) {
                guard isOverlay, isPlayingThis else { return }
                // Opening the player counts as a touch, so its header shows for one spell.
                spell.touch()
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(1))
                    guard let movement = player.movement, recording.songs.indices.contains(movement),
                        spell.follow()
                    else { continue }
                    withAnimation(Motion.glide.animation(reduceMotion: reduceMotion)) {
                        proxy.scrollTo(recording.songs[movement].id, anchor: UnitPoint(x: 0.5, y: 0.2))
                    }
                }
            }
            // The bar moves from row to row in one motion, so the rows do not jump when a movement starts.
            .animation(
                Motion.inPlace.animation(reduceMotion: reduceMotion), value: isPlayingThis ? player.movement : nil)
        }
        // A name in the header or in a row opens its page in the place below, also from the overlay.
        .environment(
            \.openURL,
            OpenURLAction { url in
                guard let target = PageLink.page(url) else { return .systemAction }
                follow(target)
                return .handled
            }
        )
        // The hero draws the title, so the list draws no heading. The bar keeps the name for Back and VoiceOver.
        .environment(\.pageHeading, "")
        .navigationTitle(isOverlay ? "" : work.title)
        .navigationBarTitleDisplayMode(.inline)
        // The specimen page has no settings rows. The queue, the download and the tags are in the page menu.
        .toolbar {
            if !isOverlay {
                ToolbarItem(placement: .topBarTrailing) {
                    PageMenuButton(
                        target: PageMenuTarget(
                            kind: recording.isAlbum ? .album : .recording,
                            item: QueueItem(work: work, recording: recording), album: album))
                }
            }
        }
        .onAppear { model.sweep.prefer(performers: recording.performerNames) }
        .task(id: placesKey) { places = NotePlace.places(in: recording, index: model.library.index) }
    }

    /// Changes when a sync or a new classical filter can move a track to another recording.
    private var placesKey: String {
        "\(recording.id)|\(model.library.classical.count)|\(model.library.syncedAt?.timeIntervalSince1970 ?? 0)"
    }

    /// The favourite of the page: the album on an album page, else the recording (ADR 0013).
    private var favourite: FavouriteHeading? {
        let order = model.recordingOrder
        if recording.isAlbum {
            guard let id = recording.songs.first?.albumId else { return nil }
            return FavouriteHeading(
                isSet: order.isFavourite(album: id), action: { order.toggleAtOnce(album: id) },
                identifier: "favourite-album", isDisabled: order.isSaving)
        }
        return FavouriteHeading(
            isSet: order.isFavourite(recording, of: work), action: { order.toggleAtOnce(recording, of: work) },
            identifier: "favourite-recording", isDisabled: order.isSaving)
    }

    @ViewBuilder private var heroTitle: some View {
        if let favourite {
            FavouriteTitle(
                title: work.title, isSet: favourite.isSet, action: favourite.action, textIdentifier: "player-title"
            )
            .disabled(model.recordingOrder.isSaving)
            .accessibilityIdentifier(favourite.identifier)
        } else {
            Text(work.title).typeStyle(Layout.pageTitle).ink()
                .accessibilityIdentifier("player-title")
        }
    }

    /// The end of the player: the next queue item, or where the queue ends.
    @ViewBuilder private var tail: some View {
        let player = model.playback
        switch PlayerTail(isPlaying: isPlayingThis, upNext: player.upNext.map(\.id)) {
        case .next:
            if let next = player.upNext.first {
                Section {
                    SectionHeading("Next")
                    Button {
                        player.nextItem()
                    } label: {
                        NextItemRow(item: next)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("up-next")
                    .pageRow()
                }
            }
        case .endsHere:
            Section {
                SectionHeading("Next")
                Text("The queue ends here.")
                    .typeStyle(.body)
                    .foregroundStyle(Palette.textSecondary)
                    .frame(maxWidth: .infinity, minHeight: Measure.hitTarget, alignment: .leading)
                    .pageRow()
                    .accessibilityIdentifier("up-next-end")
            }
        case .nothing:
            EmptyView()
        }
    }

    /// The player is the overlay only. The page of the playing item shows no playing row.
    private var showsPlayer: Bool { isOverlay && isPlayingThis }

    /// The cover, the title, then what every track shares in centred lines, the facts and the Play buttons. Names with a page are links.
    @ViewBuilder private func hero(_ page: PlayerPage) -> some View {
        let content = heroContent(page)
        if let drag = closeDrag {
            // The zone covers the cover, the title, the subtitle and the names. The links in it keep their taps: the
            // pan begins only after a downward move.
            content.contentShape(.rect).gesture(drag.heroGesture)
        } else {
            content
        }
    }

    private func heroContent(_ page: PlayerPage) -> some View {
        VStack(spacing: Layout.heroGap) {
            heading()
            if let composer = page.composer {
                RoleLines(
                    lines: [Roles.Line(kind: .unlabelled, label: "", names: [composer])], alignment: .center,
                    style: .subheadline,
                    link: { _, name in model.library.index.composer(named: name) == nil ? nil : .composer(name) }
                )
                .ink()
                .accessibilityIdentifier("hero-composer")
            }
            RoleLines(lines: page.header, alignment: .center, style: .subheadline, link: headerLink)
                .ink()
                .accessibilityIdentifier("hero-roles")
            if !page.facts.isEmpty {
                Text(page.facts)
                    .typeStyle(.subheadline)
                    .foregroundStyle(Palette.textSecondary)
                    .padding(.top, Layout.heroFactsTop)
                    .accessibilityIdentifier("hero-facts")
            }
            actions
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
    }

    /// The cover and the title.
    @ViewBuilder private func heading() -> some View {
        CoverImage(
            song: isPlayingThis ? model.playback.coverSong : recording.songs.first,
            points: Layout.bigCover, playback: isPlayingThis
        )
        .frame(width: Layout.bigCover, height: Layout.bigCover)
        .clipShape(.rect(cornerRadius: Layout.bigCoverCorner))
        .accessibilityElement()
        .accessibilityLabel("Cover")
        .accessibilityIdentifier("hero-cover")
        .padding(.bottom, Layout.bigCoverBottom)
        heroTitle
            .accessibilityAddTraits(.isHeader)
    }

    /// The album line opens the album; a performer with a page opens it.
    private func headerLink(_ line: Roles.Line, _ name: String) -> Page? {
        if line.kind == .other, line.label == "album" {
            guard let key = recording.songs.first?.albumKey, model.library.album(key) != nil else { return nil }
            return .album(key)
        }
        return model.library.index.performer(named: name) == nil ? nil : .performer(name)
    }

    /// A name in a row opens its page as in the header.
    private func rowLink(_ line: Roles.Line, _ name: String) -> Page? {
        if line.kind == .other, line.label == PlayerPage.composerLabel {
            return model.library.index.composer(named: name) == nil ? nil : .composer(name)
        }
        return model.library.index.performer(named: name) == nil ? nil : .performer(name)
    }

    /// A link of the overlay opens in the place below and closes the player. The player never owns a page stack.
    private func follow(_ target: Page) {
        let place = navigator.selection
        if isOverlay { navigator.closePlayer() }
        Task {
            // A person page waits for its local picture, as every person link does.
            await model.preparePortrait(for: target)
            navigator.open(target, in: place)
        }
    }

    /// Play and Play Album while the item does not play. While it plays, the page offers the player.
    /// The overlay shows neither.
    @ViewBuilder private var actions: some View {
        let player = model.playback
        if !isPlayingThis {
            // Play is the accent capsule; Play Album is muted beside it.
            HStack(spacing: Layout.buttonRowGap) {
                Button {
                    play(from: 0)
                } label: {
                    CapsuleLabel(title: "Play", systemImage: "play.fill", filled: true)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("play-recording")
                if let wholeAlbum {
                    // The playing album pauses and resumes, so the button says that.
                    let playsAlbum = player.recording?.id == wholeAlbum.recording.id
                    let title = playsAlbum ? (player.isPaused ? L("Resume Album") : L("Pause Album")) : L("Play Album")
                    Button {
                        spell.touch()
                        player.play(wholeAlbum)
                    } label: {
                        CapsuleLabel(
                            title: title,
                            systemImage: playsAlbum && !player.isPaused ? "pause.fill" : "play.fill",
                            filled: false)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("play-album")
                }
            }
            .padding(.top, Layout.buttonRowTop)
        } else if !isOverlay {
            Button {
                navigator.openPlayer()
            } label: {
                CapsuleLabel(title: "Show the player", systemImage: nil, filled: true)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("show-player")
            .modifier(ShareOfWidth(share: Layout.showPlayerShare))
            .padding(.top, Layout.showPlayerTop)
        }
    }

    /// A player link belongs to the place below the overlay. The player never owns a page stack.
    @ViewBuilder private func pageLink<Label: View>(to page: Page, @ViewBuilder label: () -> Label) -> some View {
        if isOverlay {
            Button {
                navigator.open(page, in: navigator.selection)
                navigator.closePlayer()
            } label: {
                // A plain button takes touches on drawn content only; the whole row must take them.
                label().contentShape(.rect)
            }
            .buttonStyle(.plain)
        } else {
            NavigationLink(value: page) { label() }
        }
    }

    /// The work of a block opens its recording page, so the listener reaches the work from the disc.
    @ViewBuilder private func heading(of block: WorkIndex.Album.Block) -> some View {
        if let part = block.part {
            if let page = Page(albumPart: part, in: model.library) {
                pageLink(to: page) {
                    HStack {
                        SectionHeading(part.title)
                        Spacer()
                        if isOverlay {
                            Image(systemName: "chevron.right")
                                .foregroundStyle(Palette.textSecondary)
                                .accessibilityIdentifier("album-work-disclosure")
                        }
                    }
                }
                .accessibilityIdentifier("album-work")
            } else {
                SectionHeading(part.title)
            }
        }
    }

    private func movementRow(_ song: Song, at index: Int, page: PlayerPage, title: String) -> some View {
        let place = places.indices.contains(index) ? places[index] : nil
        return MovementRow(
            song: song, row: index, title: title,
            names: page.differing.indices.contains(index) ? page.differing[index] : [],
            link: rowLink,
            notes: place.map { model.notes.notes(at: $0) } ?? [],
            place: place,
            isPlaying: showsPlayer && model.playback.movement == index,
            isCurrent: isPlayingThis && !isOverlay && model.playback.movement == index,
            isOpen: opened.contains(index),
            draft: Binding(
                get: { draft?.row == index ? draft : nil },
                set: { draft = $0 }),
            toggle: {
                spell.touch()
                if opened.contains(index) { opened.remove(index) } else { opened.insert(index) }
            },
            play: { play(from: index) },
            jump: { note, plays in jump(to: note, row: index, plays: plays) }
        )
        .playingRow(isPlayingThis && !isOverlay && model.playback.movement == index)
        .id(song.id)
    }

    private func play(from index: Int) {
        spell.touch()
        opened.removeAll()
        model.playback.play(QueueItem(work: work, recording: recording), from: index)
    }

    /// A tap on a note moves to its time; a tap on its time also plays. A note of a page that does not
    /// play starts that page there.
    private func jump(to note: ListeningNote, row: Int, plays: Bool) {
        spell.touch()
        let player = model.playback
        if isPlayingThis && !plays {
            player.seek(movement: row, to: note.at)
        } else {
            player.play(QueueItem(work: work, recording: recording), from: row, at: note.at)
        }
    }
}

/// One movement or track. A row that does not play has a faint play button at its trailing edge. It opens only when
/// it holds names that differ from the header or listening notes, and then shows the disclosure chevron. The playing
/// row stays open, holds the only playback bar and takes a new note.
private struct MovementRow: View {
    @Environment(AppModel.self) private var model
    let song: Song
    /// The position of the row on its page.
    let row: Int
    let title: String
    /// The names that differ from the header.
    let names: [Roles.Line]
    /// The page of a name, if it has one.
    let link: (Roles.Line, String) -> Page?
    let notes: [ListeningNote]
    /// Where a new note of this row goes. A row without a place takes no note.
    let place: NotePlace?
    let isPlaying: Bool
    /// The movement that plays while the page shows the recording: it keeps its row and its button pauses it.
    let isCurrent: Bool
    let isOpen: Bool
    @Binding var draft: NoteDraft?
    let toggle: () -> Void
    let play: () -> Void
    /// Moves to a note; true also plays.
    let jump: (ListeningNote, Bool) -> Void
    @ScaledMetric(space: .m) private var gap: CGFloat

    private var hasNames: Bool { names.contains { !$0.names.isEmpty } }
    private var opens: Bool { hasNames || !notes.isEmpty }

    var body: some View {
        if isPlaying {
            playing
        } else {
            VStack(alignment: .leading, spacing: gap) {
                HStack {
                    head
                    playButton
                }
                if opens && isOpen {
                    if hasNames {
                        RoleLines(lines: names, style: .subheadline, link: link)
                            .ink()
                    }
                    NoteList(notes: notes, jump: jump)
                }
            }
        }
    }

    /// The title and the duration. A row with nothing to show is plain text, so a tap does nothing.
    @ViewBuilder private var head: some View {
        if opens {
            Button(action: toggle) { label }
                .buttonStyle(.still)
                .accessibilityHint(hint)
        } else {
            label
        }
    }

    private var hint: String {
        switch (isOpen, hasNames, notes.isEmpty) {
        case (true, true, true): return L("Hides the names")
        case (true, true, false): return L("Hides the names and notes")
        case (true, false, _): return L("Hides the notes")
        case (false, true, true): return L("Shows the names")
        case (false, true, false): return L("Shows the names and notes")
        case (false, false, _): return L("Shows the notes")
        }
    }

    private var label: some View {
        HStack {
            MovementTitle(title: title, style: .body)
            if let duration = song.duration {
                Text(Duration.seconds(duration).localizedTime(.minuteSecond))
                    .foregroundStyle(Palette.textSecondary)
            }
            if opens {
                Image(systemName: "chevron.right")
                    .typeStyle(.footnote)
                    .fontWeight(.semibold)
                    .foregroundStyle(Palette.tint)
                    .rotationEffect(.degrees(isOpen ? 90 : 0))
                    .motion(.inPlace, value: isOpen)
                    .accessibilityHidden(true)
            }
        }
        .contentShape(.rect)
    }

    private var playButton: some View {
        let player = model.playback
        let pauses = isCurrent && !player.isPaused
        return Button {
            if isCurrent { player.togglePause() } else { play() }
        } label: {
            Image(systemName: pauses ? "pause.fill" : "play.fill")
                .typeStyle(.caption1)
                .foregroundStyle(isCurrent ? Palette.tint : Palette.textSecondary)
                .frame(width: Layout.roundButton, height: Layout.roundButton)
                .background(Palette.fillQuiet, in: .circle)
                // The circle, not its hit frame, ends on the page edge, as the specimen `.round` does.
                .frame(width: Measure.hitTarget, height: Measure.hitTarget, alignment: .trailing)
                .contentShape(.rect)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(isCurrent ? (player.isPaused ? "Resume" : "Pause") : "Play from here")
        .accessibilityIdentifier(isCurrent ? "movement-slot" : "play-movement")
    }

    /// The playing row: its title, the names that differ, the playback bar with the note marks, the controls, the
    /// notes and the note that the listener writes.
    private var playing: some View {
        let player = model.playback
        return VStack(alignment: .leading, spacing: gap) {
            // The bold title marks the playing row. VoiceOver hears it too.
            HStack {
                MovementTitle(title: title, style: .headline)
                    .accessibilityLabel("Now playing, \(title)")
                if player.isLoading {
                    ProgressView()
                }
            }
            RoleLines(lines: names, style: .subheadline, link: link)
                .ink()
            PlaybackProgress(player: player, notes: notes, jump: { jump($0, false) })
            PlayerControls(player: player)
            NoteList(notes: notes, jump: jump)
            if let place {
                NoteEditor(
                    draft: $draft, row: row, place: place, elapsed: { player.progress?.elapsed ?? player.position })
            }
        }
        .accessibilityIdentifier("movement")
    }
}

/// The controls of the playing row, centred in ink. Next Work and Stop follow
/// Next: the specimen has neither, but the queue needs them.
private struct PlayerControls: View {
    let player: PlaybackSession
    @ScaledMetric(relativeTo: .title2) private var icon = Layout.playerControlIcon
    @ScaledMetric(relativeTo: .title2) private var mainIcon = Layout.playerMainIcon

    var body: some View {
        HStack(spacing: 0) {
            control("Previous", "backward.fill") { player.previous() }
            gap
            control(player.isPaused ? "Resume" : "Pause", player.isPaused ? "play.fill" : "pause.fill", main: true) {
                player.togglePause()
            }
            gap
            control("Next", "forward.fill") { player.next() }
                .disabled(!player.hasNext)
            gap
            control("Next Work", "forward.end.fill") { player.nextItem() }
                .disabled(player.upNext.isEmpty)
            gap
            control("Stop", "stop.fill") { player.stop() }
        }
        .frame(maxWidth: .infinity)
        .buttonStyle(.borderless)
    }

    /// The specimen gap, closed on a narrow row so that all controls fit.
    private var gap: some View {
        Spacer(minLength: 0).frame(maxWidth: Layout.playerControlGap)
    }

    private func control(
        _ title: String, _ systemImage: String, main: Bool = false, action: @escaping () -> Void
    ) -> some View {
        Control(title: title, systemImage: systemImage, size: main ? mainIcon : icon, action: action)
    }

    /// An explicit ink replaces the dimming of a disabled button, so an off control takes the disabled colour.
    private struct Control: View {
        @Environment(\.isEnabled) private var isEnabled
        let title: String
        let systemImage: String
        let size: CGFloat
        let action: () -> Void

        var body: some View {
            Button(action: action) {
                Image(systemName: systemImage)
                    .font(.system(size: size))
                    .foregroundStyle(isEnabled ? Palette.textPrimary : Palette.textTertiary)
                    .frame(width: Measure.hitTarget, height: Measure.hitTarget)
                    .contentShape(.rect)
            }
            .accessibilityLabel(LocalizedStringKey(title))
        }
    }
}

/// The notes of a movement, earliest first. The time is a prefix in the tint. A tap
/// on the text moves to the note; a tap on its time moves there and plays.
private struct NoteList: View {
    let notes: [ListeningNote]
    let jump: (ListeningNote, Bool) -> Void
    @ScaledMetric(space: .xs) private var lineGap: CGFloat
    @ScaledMetric(space: .s) private var gap: CGFloat

    var body: some View {
        if !notes.isEmpty {
            VStack(alignment: .leading, spacing: lineGap) {
                ForEach(notes) { note in
                    HStack(alignment: .firstTextBaseline, spacing: gap) {
                        Button(ListeningNotes.time(of: note)) { jump(note, true) }
                            .monospacedDigit()
                            .foregroundStyle(Palette.tint)
                            .accessibilityLabel("Play from \(ListeningNotes.time(of: note))")
                            .accessibilityIdentifier("note-time")
                        Button {
                            jump(note, false)
                        } label: {
                            Text(note.text)
                                .ink()
                                .multilineTextAlignment(.leading)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(.rect)
                        }
                        .accessibilityHint("Moves to \(ListeningNotes.time(of: note))")
                        .accessibilityIdentifier("note-text")
                    }
                    .buttonStyle(.borderless)
                    .typeStyle(.subheadline)
                }
            }
            // A container keeps the identifiers of its buttons inside the row's identifier.
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("notes")
        }
    }
}

/// "Add a note here", then the note in the row: never a modal. The note stays open until Save or Return,
/// so the listener can scrub the bar or the timeline to find the end.
private struct NoteEditor: View {
    @Environment(AppModel.self) private var model
    @Binding var draft: NoteDraft?
    let row: Int
    let place: NotePlace
    /// The playing time of the row.
    let elapsed: () -> Double
    @FocusState private var isWriting: Bool
    @ScaledMetric(space: .xs) private var lineGap: CGFloat
    @ScaledMetric(space: .s) private var gap: CGFloat
    @ScaledMetric(space: .l) private var actionGap: CGFloat
    @ScaledMetric(space: .xxs) private var fieldPadding: CGFloat

    var body: some View {
        // A container keeps the identifiers of its controls inside the row's identifier.
        editor
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("note-editor")
    }

    @ViewBuilder private var editor: some View {
        if let current = draft {
            VStack(alignment: .leading, spacing: lineGap) {
                HStack(alignment: .firstTextBaseline, spacing: gap) {
                    Text(ListeningNotes.time(at: current.at, end: current.end))
                        .typeStyle(.subheadline)
                        .monospacedDigit()
                        .foregroundStyle(Palette.tint)
                        .accessibilityIdentifier("note-draft-time")
                    TextField("Write the note", text: text)
                        .typeStyle(.body)
                        .foregroundStyle(Palette.textPrimary)
                        .focused($isWriting)
                        .submitLabel(.done)
                        .onSubmit(save)
                        .padding(.vertical, fieldPadding)
                        .overlay(alignment: .bottom) { Divider().overlay(Palette.separator) }
                        .accessibilityIdentifier("note-field")
                }
                HStack(spacing: actionGap) {
                    Spacer()
                    Button("End here") { draft?.end(at: elapsed()) }
                        .typeStyle(.subheadline)
                        .accessibilityIdentifier("end-note")
                    Button("Cancel") { draft = nil }
                        .typeStyle(.subheadline)
                        .accessibilityIdentifier("cancel-note")
                    Button("Save", action: save)
                        .typeStyle(.headline)
                        .accessibilityIdentifier("save-note")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(Palette.tint)
                if let error = model.notes.error {
                    Text(error)
                        .typeStyle(.footnote)
                        .foregroundStyle(Palette.textSecondary)
                }
            }
            .onAppear { isWriting = true }
        } else {
            Button("Add a note here") { draft = NoteDraft(row: row, at: elapsed()) }
                .typeStyle(.subheadline)
                .foregroundStyle(Palette.tint)
                .buttonStyle(.borderless)
                .accessibilityIdentifier("add-note")
        }
    }

    private var text: Binding<String> {
        Binding(get: { draft?.text ?? "" }, set: { draft?.text = $0 })
    }

    /// A failed write keeps the draft, so the text is not lost.
    private func save() {
        guard let current = draft, model.notes.save(current, at: place) else { return }
        draft = nil
    }
}

/// The title of a movement row. A long title wraps into plain left-aligned lines and never ends in an ellipsis, also
/// while the row opens or starts to play.
private struct MovementTitle: View {
    let title: String
    let style: TypeStyle

    var body: some View {
        Text(title)
            .typeStyle(style)
            .ink()
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A button that does not dim its label while a finger is down. A row that opens must not flash its duration and its
/// offline mark.
struct StillButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
    }
}

extension ButtonStyle where Self == StillButtonStyle {
    static var still: StillButtonStyle { StillButtonStyle() }
}

/// How far the playing movement has played.
struct PlaybackProgress: View {
    let player: PlaybackSession
    /// The listening notes of the movement, as marks on the bar.
    var notes: [ListeningNote] = []
    var jump: (ListeningNote) -> Void = { _ in }
    @ScaledMetric(space: .xs) private var lineGap: CGFloat

    var body: some View {
        Group {
            if let progress = player.progress {
                PositionBar(
                    player: player, elapsed: progress.elapsed, duration: progress.duration, notes: notes, jump: jump
                )
                .id(progress.movement)
                .padding(.vertical, lineGap)
            }
        }
        // A container keeps the identifiers of its children, such as the position bar.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("playback-progress")
    }

    static func times(_ elapsed: Double, of duration: Double) -> some View {
        HStack {
            Text(time(elapsed))
            Spacer()
            Text("−" + time(max(duration - elapsed, 0)))
        }
        .typeStyle(.caption1)
        .foregroundStyle(Palette.textSecondary)
    }

    /// The times, or the slow-connection line in their place (ADR 0060). Hidden copies of both messages reserve
    /// their wrapped height at every width and text size, so the controls never move when the line appears.
    static func under(_ elapsed: Double, of duration: Double, line: String?) -> some View {
        ZStack {
            Text(SlowConnectionLine.startText).hidden()
            Text(SlowConnectionLine.resumeText).hidden()
            times(elapsed, of: duration)
                .opacity(line == nil ? 1 : 0)
                .accessibilityHidden(line != nil)
            if let line {
                Text(line)
                    .typeStyle(.caption1)
                    .foregroundStyle(Palette.textSecondary)
                    .accessibilityIdentifier("slow-connection")
            }
        }
        .typeStyle(.caption1)
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity)
    }

    static func time(_ seconds: Double) -> String {
        Duration.seconds(seconds.rounded()).localizedTime(seconds >= 3600 ? .hourMinuteSecond : .minuteSecond)
    }
}

/// The position in the current movement: a bar with no handle, as specimen player.html `.mv-bar`. A drag moves
/// playback when the finger lifts, so the movement does not restart for every step of the drag.
private struct PositionBar: View {
    @Environment(AppModel.self) private var model
    let player: PlaybackSession
    let elapsed: Double
    let duration: Double
    let notes: [ListeningNote]
    let jump: (ListeningNote) -> Void
    @State private var scrub = PositionScrub()
    @State private var width = 0.0
    @GestureState private var isTouching = false
    @ScaledMetric(space: .xs) private var lineGap: CGFloat

    var body: some View {
        let shown = min(scrub.shown(elapsed: elapsed), duration)
        VStack(alignment: .leading, spacing: lineGap) {
            bar(shown)
            PlaybackProgress.under(shown, of: duration, line: player.slowLine)
            if let quality = player.qualityLine {
                Text(quality)
                    .typeStyle(.caption1)
                    .foregroundStyle(Palette.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier("audio-quality")
            }
        }
        .onChange(of: elapsed) { _, now in scrub.observe(elapsed: now) }
        // A cancelled drag never calls onEnded, and a new movement replaces this bar while a finger holds it.
        .onChange(of: isTouching) { _, touching in
            if !touching { stopScrubbing() }
        }
        .onDisappear { stopScrubbing() }
    }

    private func stopScrubbing() {
        scrub.cancel()
        if model.isScrubbing { model.isScrubbing = false }
    }

    private func bar(_ shown: Double) -> some View {
        let lanes = ListeningNotes.lanes(notes, reach: reach)
        let room = ListeningNotes.room(notes, duration: duration, width: width)
        return ZStack(alignment: .leading) {
            Capsule().fill(Palette.fillStandard)
            Capsule().fill(Palette.tint)
                .frame(width: width * PositionScrub.share(shown, of: duration))
        }
        .frame(height: Layout.positionBar)
        .overlay(alignment: .topLeading) { marks(lanes) }
        .onGeometryChange(for: Double.self) {
            Double($0.size.width)
        } action: {
            width = $0
        }
        // The touch area is the height of a system slider, plus the marks above it so that they stay tappable.
        // The layout keeps the thin bar and the room of the marks, so they never cover the text above.
        .padding(.vertical, -Layout.positionBarInset)
        .modifier(NoteRoom(notes: notes, duration: duration))
        .contentShape(.rect)
        .gesture(
            DragGesture(minimumDistance: 0)
                .updating($isTouching) { _, state, _ in state = true }
                .onChanged { value in
                    if !model.isScrubbing { model.isScrubbing = true }
                    scrub.drag(to: PositionScrub.seconds(at: value.location.x, width: width, duration: duration))
                }
                .onEnded { value in
                    model.isScrubbing = false
                    if let note = tapped(value, above: room - Layout.positionBarInset) {
                        scrub.cancel()
                        jump(note)
                        return
                    }
                    scrub.drag(to: PositionScrub.seconds(at: value.location.x, width: width, duration: duration))
                    if let target = scrub.release() { player.seek(to: target) }
                }
        )
        .padding(.vertical, Layout.positionBarInset)
        .accessibilityRepresentation {
            Slider(
                value: Binding(get: { shown }, set: { player.seek(to: $0) }),
                in: 0...max(duration, 1))
        }
        .accessibilityLabel("Position")
        .accessibilityValue(PlaybackProgress.time(shown))
        .accessibilityIdentifier("position")
    }
}

extension PositionBar {
    /// A note mark is this many seconds wide on the bar.
    private var reach: Double { ListeningNotes.reach(width: width, duration: duration) }

    /// Dots for moments and lines for spans above the bar. Notes that overlap stack in lanes.
    private func marks(_ lanes: [UUID: Int]) -> some View {
        let pitch = -Layout.noteDotTop
        return ZStack(alignment: .topLeading) {
            ForEach(notes) { note in
                let lift = pitch * CGFloat(lanes[note.id] ?? 0)
                let from = CGFloat(width * PositionScrub.share(note.at, of: duration))
                if let end = note.end {
                    let to = CGFloat(width * PositionScrub.share(end, of: duration))
                    Capsule()
                        .fill(Palette.textSecondary)
                        .frame(width: max(to - from, Layout.noteSpan), height: Layout.noteSpan)
                        .position(x: (from + to) / 2, y: Layout.noteSpanTop + Layout.noteSpan / 2 - lift)
                } else {
                    Circle()
                        .fill(Palette.textSecondary)
                        .frame(width: Layout.noteDot, height: Layout.noteDot)
                        .position(x: from, y: Layout.noteDotTop + Layout.noteDot / 2 - lift)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// The note of a tap above the bar, where the marks are. A tap or a drag on the bar itself scrubs.
    /// `top` is the distance from the top of the touch area to the top of the bar.
    private func tapped(_ value: DragGesture.Value, above top: CGFloat) -> ListeningNote? {
        let still = max(abs(value.translation.width), abs(value.translation.height)) <= Layout.noteDot
        guard still, value.startLocation.y < top else { return nil }
        return ListeningNotes.note(
            atX: value.startLocation.x, rise: top - value.startLocation.y, in: notes, width: width, duration: duration)
    }
}

/// Room above the playback bar for its note lanes. The room comes from the width that the layout proposes, so the
/// row has its final height in the first pass and does not grow when the bar learns its width.
struct NoteRoom: ViewModifier {
    let notes: [ListeningNote]
    let duration: Double

    func body(content: Content) -> some View {
        Room(notes: notes, duration: duration) { content }
    }

    private struct Room: SwiftUI.Layout {
        let notes: [ListeningNote]
        let duration: Double

        func sizeThatFits(proposal: ProposedViewSize, subviews: LayoutSubviews, cache: inout ()) -> CGSize {
            guard let bar = subviews.first else { return .zero }
            let size = bar.sizeThatFits(ProposedViewSize(width: proposal.width, height: nil))
            let room = ListeningNotes.room(notes, duration: duration, width: size.width)
            return CGSize(width: size.width, height: size.height + room)
        }

        func placeSubviews(
            in bounds: CGRect, proposal: ProposedViewSize, subviews: LayoutSubviews, cache: inout ()
        ) {
            subviews.first?.place(
                at: CGPoint(x: bounds.minX, y: bounds.maxY), anchor: .bottomLeading,
                proposal: ProposedViewSize(width: bounds.width, height: nil))
        }
    }
}

/// Proposes a share of the offered width to its one subview and centres it (specimen `width: 60%`).
private struct ShareOfWidth: ViewModifier {
    let share: CGFloat

    func body(content: Content) -> some View {
        Share(share: share) { content }
    }

    private struct Share: SwiftUI.Layout {
        let share: CGFloat

        func sizeThatFits(proposal: ProposedViewSize, subviews: LayoutSubviews, cache: inout ()) -> CGSize {
            guard let view = subviews.first else { return .zero }
            let width = proposal.width.map { $0 * share }
            let size = view.sizeThatFits(ProposedViewSize(width: width, height: nil))
            return CGSize(width: proposal.width ?? size.width, height: size.height)
        }

        func placeSubviews(
            in bounds: CGRect, proposal: ProposedViewSize, subviews: LayoutSubviews, cache: inout ()
        ) {
            subviews.first?.place(
                at: CGPoint(x: bounds.midX, y: bounds.minY), anchor: .top,
                proposal: ProposedViewSize(width: bounds.width * share, height: nil))
        }
    }
}

/// The row of the next queue item at the end of the player. It shows the cover, title and album.
/// A tap on the row skips to the item at once; the row itself only shows what comes.
private struct NextItemRow: View {
    let item: QueueItem

    var body: some View {
        HStack(spacing: Space.m.points) {
            CoverImage(song: item.recording.songs.first, points: Measure.coverRow)
                .frame(width: Measure.coverRow, height: Measure.coverRow)
                .clipShape(.rect(cornerRadius: Radius.s))
            VStack(alignment: .leading, spacing: Space.inGroup.points) {
                Text(item.work.title)
                    .typeStyle(.body)
                    .foregroundStyle(Palette.textPrimary)
                if !item.recording.album.isEmpty {
                    Text(item.recording.album)
                        .typeStyle(.subheadline)
                        .foregroundStyle(Palette.textSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minHeight: Measure.hitTarget)
        .accessibilityElement(children: .combine)
    }
}

/// A capsule button face: filled in the accent, or muted on the quiet fill.
struct CapsuleLabel: View {
    let title: String
    let systemImage: String?
    let filled: Bool

    var body: some View {
        HStack(spacing: Layout.capsuleGap) {
            if let systemImage {
                Image(systemName: systemImage)
                    .accessibilityHidden(true)
            }
            Text(LocalizedStringKey(title))
                .fixedSize(horizontal: false, vertical: true)
        }
        .typeStyle(Layout.capsuleLabel)
        .multilineTextAlignment(.center)
        .foregroundStyle(filled ? Palette.onAccent : Palette.tint)
        .padding(.horizontal, Layout.capsuleInset)
        .frame(maxWidth: .infinity, minHeight: Layout.capsuleHeight)
        .background(filled ? Palette.accentFill : Palette.fillQuiet, in: .capsule)
        .contentShape(.capsule)
    }
}
