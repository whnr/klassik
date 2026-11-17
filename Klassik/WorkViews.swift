import SwiftUI

/// Plays works in random order. The movements of each work stay in order.
struct ShuffleButton: View {
    @Environment(AppModel.self) private var model
    let works: [WorkIndex.Work]

    var body: some View {
        Button("Shuffle Works", systemImage: "shuffle") {
            let items = works.shuffled().compactMap { work in
                model.recordingOrder.reference(of: work).map { QueueItem(work: work, recording: $0) }
            }
            model.playback.play(queue: items)
        }
        .disabled(works.isEmpty)
        .accessibilityIdentifier("shuffle")
    }
}

/// The name of the favourite action. On a favourite it takes the favourite away.
enum FavouriteAction {
    static func title(isSet: Bool) -> String { isSet ? "Unfavourite" : "Favourite" }
}

/// The actions of a row that stands for one recording or one album. Trailing swipe: the queue. Leading swipe:
/// download and favourites. The context menu holds all of them, as in Apple Music.
private struct ItemActions: ViewModifier {
    @Environment(AppModel.self) private var model
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
                playButton
                Button("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward") { playNext() }
                Button("Add to Queue", systemImage: "text.line.last.and.arrowtriangle.forward") { addToQueue() }
                if downloads { downloadButton }
                if hasFavourite { favouriteButton }
            }
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
            Button("Download", systemImage: "arrow.down") {
                if let client = model.client {
                    tracks.download(item.recording, title: item.work.title, client: client)
                }
            }
        }
    }

    /// The playing recording pauses and resumes, so its label says that.
    private var playButton: some View {
        let player = model.playback
        let isPlaying = player.recording?.id == item.recording.id
        return Button(
            isPlaying ? (player.isPaused ? "Resume" : "Pause") : "Play",
            systemImage: isPlaying && !player.isPaused ? "pause" : "play"
        ) {
            player.play(item)
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
                    HStack {
                        Text(album.title)
                            .ink()
                        OfflineHint(isOffline: model.tracks.isOffline(album.recording))
                    }
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
                    HStack {
                        Text(work.title)
                            .ink()
                        OfflineHint(isOffline: work.recordings.contains { model.tracks.isOffline($0) })
                    }
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
    /// "Composed 1844, 1 recording" (person.html workRow). The track titles stay on the work page: in a list they
    /// repeat the title or name one movement.
    nonisolated static func detail(of work: WorkIndex.Work, composed: String?) -> String {
        let recordings = WorkIndex.Recording.count(work.recordings.count, "recording")
        guard let composed else { return recordings }
        return "Composed\u{00A0}\(composed), \(recordings)"
    }
}

/// A work's page as work.html draws it: composer under the title, a Play pill, then the recordings on plain rows.
struct WorkView: View {
    @Environment(AppModel.self) private var model
    let work: WorkIndex.Work

    private var recordings: [RecordingOrder.Row] { model.recordingOrder.rows(of: work) }

    var body: some View {
        PageList {
            WorkHeader(work: work)
                .listRowSeparator(.hidden)
                .pageEdges(bottom: Layout.headBottom)
            if let recording = model.recordingOrder.reference(of: work) {
                let player = model.playback
                // While any recording of the work plays, the pill pauses it. Else it plays the top of the list.
                let playsThisWork = player.item?.work.id == work.id
                Button {
                    if playsThisWork {
                        player.togglePause()
                    } else {
                        player.play(queue: [QueueItem(work: work, recording: recording)])
                    }
                } label: {
                    Label(
                        playsThisWork ? (player.isPaused ? "Resume" : "Pause") : "Play",
                        systemImage: playsThisWork && !player.isPaused ? "pause.fill" : "play.fill"
                    )
                    .typeStyle(Layout.capsuleLabel)
                    .foregroundStyle(Palette.onAccent)
                    .frame(maxWidth: .infinity, minHeight: Layout.capsuleHeight)
                    .background(Palette.accentFill, in: .capsule)
                    .contentShape(.capsule)
                }
                .buttonStyle(.plain)
                .listRowSeparator(.hidden)
                .pageEdges(top: Layout.buttonRowTop)
                .accessibilityIdentifier("play-work")
            }

            Section {
                CountedHeading("Recordings", count: work.recordings.count)
                ForEach(recordings) { row in
                    let recording = row.recording
                    let isPlaying = plays(recording)
                    NavigationLink(value: Page.recording(work: work.id, recording: recording.id)) {
                        RecordingRow(
                            recording: recording, isFavourite: row.isFavourite, reason: row.reason,
                            isOffline: model.tracks.isOffline(recording),
                            playsFirst: recording.id == model.recordingOrder.reference(of: work)?.id,
                            isPlaying: isPlaying)
                    }
                    // Tint identifies the playing recording while the listener browses.
                    .listRowBackground(isPlaying ? Palette.tint.color.opacity(0.12) : Color.clear)
                    .itemActions(QueueItem(work: work, recording: recording), downloads: true, favourite: true)
                    .accessibilityIdentifier("recording")
                    .moveDisabled(!row.isFavourite)
                }
                .onMove { model.recordingOrder.moveFavourites(of: work, from: $0, to: $1) }
                Text("Favourite recordings come first, in your order. Then the newest.")
                    .typeStyle(Layout.footnote)
                    .foregroundStyle(Palette.textSecondary)
                    .listRowSeparator(.hidden)
                    .pageEdges(top: Layout.workFootTop + Layout.footTop)
            }
        }
        .pageTitle(work.title)
        .environment(\.pageHeadingBottom, Layout.metaTop)
        .environment(
            \.pageFavourite,
            FavouriteHeading(
                isSet: model.recordingOrder.isFavourite(work),
                action: { model.recordingOrder.toggleAtOnce(work) }, identifier: "favourite-work")
        )
        .toolbar { if recordings.filter(\.isFavourite).count > 1 { EditButton() } }
    }

    private func plays(_ recording: WorkIndex.Recording) -> Bool {
        guard let item = model.playback.item else { return false }
        return item.work.id == work.id && item.recording.id == recording.id
    }
}

/// A section heading with its count in a lighter step: "Recordings (3)".
struct CountedHeading: View {
    @Environment(\.isPageList) private var isPageList
    let title: String
    let count: Int

    init(_ title: String, count: Int) {
        self.title = title
        self.count = count
    }

    var body: some View {
        Text("\(title) \(Text("(\(count))").foregroundStyle(Palette.textSecondary))")
            .typeStyle(Layout.sectionHeading)
            .foregroundStyle(Palette.textPrimary)
            .textCase(nil)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("section-heading")
            .pageSectionHeader(isPageList)
    }
}

/// Under the title: the composer as a link, when the work was composed, and what the tracks add to the title.
private struct WorkHeader: View {
    @Environment(AppModel.self) private var model
    @Environment(AppNavigator.self) private var navigator
    let work: WorkIndex.Work
    @ScaledMetric(space: .inGroup) private var gap: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: gap) {
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Button(work.composer) {
                    navigator.open(.composer(work.composer), in: navigator.selection)
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
            if case .candidates = model.enrichment.link(of: work), work.isTagged {
                Button("Confirm the MusicBrainz Work", systemImage: "questionmark.circle") {
                    navigator.open(.sources(work: work.id), in: navigator.selection)
                }
                .typeStyle(.subheadline)
                .buttonStyle(.plain)
                .foregroundStyle(Palette.tint)
                .accessibilityIdentifier("composed")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// When the work was composed. It opens the sources of the date.
    private var composed: some View {
        let enrichment = model.enrichment
        let text =
            if let composed = enrichment.composed(work) {
                composed.span.text
            } else {
                enrichment.isRunning ? "…" : "unknown"
            }
        return Button(", composed\u{00A0}\(text)") {
            navigator.open(.sources(work: work.id), in: navigator.selection)
        }
        .buttonStyle(.plain)
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
    let isOffline: Bool
    let playsFirst: Bool
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
            CoverImage(id: recording.songs.first?.coverArt, points: cover)
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
                if playsFirst {
                    Text("Plays first")
                        .typeStyle(.footnote)
                        .foregroundStyle(Palette.tint)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // Every row keeps the room of the slot, so the playing row tints in place and its text does not rewrap.
            // The offline mark sits in that room too: playback stores the recording, and the mark then appears.
            VStack(spacing: gap) {
                slot
                    .opacity(isPlaying ? 1 : 0)
                    .disabled(!isPlaying)
                    .accessibilityHidden(!isPlaying)
                OfflineHint(isOffline: isOffline)
            }
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

    /// The slot at the trailing edge of the playing row pauses and resumes it, so the listener need not leave the page.
    private var slot: some View {
        let player = model.playback
        return Button {
            player.togglePause()
        } label: {
            Image(systemName: player.isPaused ? "play.fill" : "pause.fill")
                .typeStyle(.title3)
                .foregroundStyle(Palette.tint)
                .frame(width: Measure.hitTarget, height: Measure.hitTarget)
                .contentShape(.rect)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(player.isPaused ? "Resume" : "Pause")
        .accessibilityIdentifier("recording-slot")
    }
}

/// The page of a recording or album. While it plays, it is the player (ADR 0015): the header holds what every track
/// shares, a row holds what differs, and only the playing movement has a playback bar (ADR 0027). The same content
/// fills the player overlay (ADR 0014).
struct RecordingView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppNavigator.self) private var navigator
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let work: WorkIndex.Work
    let recording: WorkIndex.Recording
    /// Set on the album page, which lists the tracks of the album.
    var album: WorkIndex.Album?
    var isOverlay = false
    /// The rows that the listener opened, by track position.
    @State private var opened: Set<Int> = []
    @State private var spell = QuietSpell()

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
                    if isOverlay {
                        VStack(spacing: Layout.bigCoverBottom) {
                            CoverImage(id: recording.songs.first?.coverArt, points: Layout.bigCover)
                                .frame(width: Layout.bigCover, height: Layout.bigCover)
                                .clipShape(.rect(cornerRadius: Layout.bigCoverCorner))
                            overlayTitle
                        }
                        .frame(maxWidth: .infinity)
                        .multilineTextAlignment(.center)
                        .listRowBackground(Color.clear)
                    }
                    header(page)
                    if isPlayingThis, let error = player.error {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(Palette.textPrimary)
                    }
                    if !isPlayingThis {
                        Button("Play", systemImage: "play.fill") { play(from: 0) }
                            .accessibilityIdentifier("play-recording")
                        if let wholeAlbum {
                            // The playing album pauses and resumes, so the button says that.
                            let playsAlbum = player.recording?.id == wholeAlbum.recording.id
                            let verb = playsAlbum ? (player.isPaused ? "Resume" : "Pause") : "Play"
                            Button(
                                "\(verb) Whole Album",
                                systemImage: playsAlbum && !player.isPaused ? "pause.fill" : "square.stack"
                            ) {
                                spell.touch()
                                player.play(wholeAlbum)
                            }
                            .accessibilityIdentifier("play-album")
                        }
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
                                    title: album.title(of: song, in: block))
                            }
                        }
                    }
                } else {
                    Section {
                        SectionHeading(recording.isAlbum ? "Tracks" : "Movements")
                        ForEach(Array(recording.songs.enumerated()), id: \.element.id) { index, song in
                            movementRow(song, at: index, page: page, title: recording.title(of: song))
                        }
                    }
                }

                Section {
                    pageLink(to: .rawTags(work: work.id, recording: recording.id)) {
                        HStack {
                            Text("Tags and Grouping").ink()
                            if isOverlay {
                                Spacer()
                                Image(systemName: "chevron.right").foregroundStyle(Palette.textSecondary)
                            }
                        }
                    }
                    .accessibilityIdentifier("raw-tags")
                }

                Section {
                    SectionHeading("Offline")
                    OfflineControls(recording: recording, title: work.title)
                }

                if isPlayingThis, !player.upNext.isEmpty {
                    Section {
                        SectionHeading("Up next")
                        ForEach(player.upNext) { item in
                            Button {
                                player.playQueued(item.id)
                            } label: {
                                VStack(alignment: .leading) {
                                    Text(item.work.title)
                                        .ink()
                                    Text(item.work.composer)
                                        .typeStyle(.subheadline)
                                        .foregroundStyle(Palette.textSecondary)
                                    RoleLines(lines: item.recording.principalNames, style: .subheadline)
                                        .foregroundStyle(Palette.textSecondary)
                                }
                            }
                            .accessibilityIdentifier("up-next")
                        }
                        .onDelete { player.removeFromQueue(at: $0) }
                        .onMove { player.moveInQueue(from: $0, to: $1) }
                    }
                }

                // The end takes the place of the next items, at the foot of the player (specimen player.html).
                if isOverlay, player.item == nil {
                    Section {
                        Text(player.queueEnded ? "The queue has ended." : "Playback stopped.")
                            .typeStyle(.subheadline)
                            .foregroundStyle(Palette.textSecondary)
                            .listRowSeparator(.hidden)
                            .accessibilityIdentifier("player-ended")
                    }
                }
            }
            // A finger on the page, or a scroll that it started, holds the rows. The spell begins when the page is still.
            // A scroll by the app itself is not a touch. The list has no tap gesture of its own, so row controls keep their
            // taps. Each control touches the spell itself.
            .onScrollPhaseChange { _, phase in
                spell.touching(phase == .tracking || phase == .interacting || phase == .decelerating)
            }
            .onChange(of: model.isScrubbing) { _, scrubbing in spell.hold(scrubbing) }
            // specimen player.html: each second, after a quiet spell, the player brings the playing row back.
            .task(id: isOverlay && isPlayingThis) {
                guard isOverlay, isPlayingThis else { return }
                // Opening the player counts as a touch, so its header shows for one spell.
                spell.touch()
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(1))
                    guard let movement = player.movement, recording.songs.indices.contains(movement),
                        spell.follow(movement)
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
        .pageTitle(isOverlay ? "" : work.title)
        .environment(\.pageFavourite, isOverlay ? nil : favourite)
    }

    /// The favourite of the page: the album on an album page, else the recording (ADR 0013, 0017).
    private var favourite: FavouriteHeading? {
        let order = model.recordingOrder
        if recording.isAlbum {
            guard let id = recording.songs.first?.albumId else { return nil }
            return FavouriteHeading(
                isSet: order.isFavourite(album: id), action: { order.toggleAtOnce(album: id) },
                identifier: "favourite-album")
        }
        return FavouriteHeading(
            isSet: order.isFavourite(recording, of: work), action: { order.toggleAtOnce(recording, of: work) },
            identifier: "favourite-recording")
    }

    @ViewBuilder private var overlayTitle: some View {
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

    /// What every track shares, in centred lines.
    private func header(_ page: PlayerPage) -> some View {
        VStack(spacing: Layout.heroGap) {
            if let composer = page.composer {
                Text(composer)
                    .typeStyle(.headline)
                    .ink()
            }
            RoleLines(lines: page.header, alignment: .center, style: .subheadline)
                .ink()
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
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
                        Image(systemName: "chevron.right")
                            .foregroundStyle(Palette.textSecondary)
                    }
                }
                .accessibilityIdentifier("album-work")
            } else {
                SectionHeading(part.title)
            }
        }
    }

    private func movementRow(_ song: Song, at index: Int, page: PlayerPage, title: String) -> some View {
        MovementRow(
            song: song, title: title, names: page.differing.indices.contains(index) ? page.differing[index] : [],
            isPlaying: isPlayingThis && model.playback.movement == index,
            isOpen: opened.contains(index),
            toggle: {
                spell.touch()
                if opened.contains(index) { opened.remove(index) } else { opened.insert(index) }
            },
            play: { play(from: index) }
        )
        .id(song.id)
    }

    private func play(from index: Int) {
        spell.touch()
        opened.removeAll()
        model.playback.play(QueueItem(work: work, recording: recording), from: index)
    }
}

/// One movement or track. A row that does not play has a faint play button at its trailing edge. It opens only when
/// it holds names that differ from the header, and then shows the disclosure chevron. The playing row stays open and
/// holds the only playback bar (ADR 0027).
private struct MovementRow: View {
    @Environment(AppModel.self) private var model
    let song: Song
    let title: String
    /// The names that differ from the header.
    let names: [Roles.Line]
    let isPlaying: Bool
    let isOpen: Bool
    let toggle: () -> Void
    let play: () -> Void
    @ScaledMetric(space: .m) private var gap: CGFloat

    private var opens: Bool { names.contains { !$0.names.isEmpty } }

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
                    RoleLines(lines: names, style: .subheadline)
                        .ink()
                }
            }
            .accessibilityIdentifier("movement")
        }
    }

    /// The title and the duration. A row with nothing to show is plain text, so a tap does nothing.
    @ViewBuilder private var head: some View {
        if opens {
            Button(action: toggle) { label }
                .buttonStyle(.still)
                .accessibilityHint(isOpen ? "Hides the names" : "Shows the names")
        } else {
            label
        }
    }

    private var label: some View {
        HStack {
            MovementTitle(title: title, style: .body)
            OfflineHint(isOffline: model.tracks.isOffline(song))
            if let duration = song.duration {
                Text(Duration.seconds(duration).formatted(.time(pattern: .minuteSecond)))
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
        Button(action: play) {
            Image(systemName: "play.fill")
                .typeStyle(.caption1)
                .foregroundStyle(Palette.textSecondary)
                .frame(width: Layout.roundButton, height: Layout.roundButton)
                .background(Palette.fillQuiet, in: .circle)
                // The circle, not its hit frame, ends on the page edge, as the specimen `.round` does.
                .frame(width: Measure.hitTarget, height: Measure.hitTarget, alignment: .trailing)
                .contentShape(.rect)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel("Play from here")
        .accessibilityIdentifier("play-movement")
    }

    /// The playing row: its title, the names that differ, the playback bar and the controls.
    private var playing: some View {
        let player = model.playback
        return VStack(alignment: .leading, spacing: gap) {
            HStack {
                MovementTitle(title: title, style: .headline)
                if player.isLoading {
                    ProgressView()
                } else {
                    Image(systemName: "speaker.wave.2.fill")
                        .foregroundStyle(Palette.tint)
                        .accessibilityLabel("Now playing")
                }
            }
            RoleLines(lines: names, style: .subheadline)
                .ink()
            PlaybackProgress(player: player)
            HStack {
                Button("Previous", systemImage: "backward.fill") { player.previous() }
                Spacer()
                Button(
                    player.isPaused ? "Resume" : "Pause",
                    systemImage: player.isPaused ? "play.fill" : "pause.fill"
                ) {
                    player.togglePause()
                }
                Spacer()
                Button("Next", systemImage: "forward.fill") { player.next() }
                    .disabled(!player.hasNext)
                Spacer()
                Button("Next Work", systemImage: "forward.end.fill") { player.nextItem() }
                    .disabled(player.upNext.isEmpty)
                Spacer()
                Button("Stop", systemImage: "stop.fill") { player.stop() }
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .typeStyle(.title2)
            .padding(.horizontal)
        }
        .accessibilityIdentifier("movement")
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
/// offline mark (specimen player.html `.track .row`).
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
    @ScaledMetric(space: .xs) private var lineGap: CGFloat

    var body: some View {
        Group {
            if let progress = player.progress {
                PositionBar(player: player, elapsed: progress.elapsed, duration: progress.duration)
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

    static func time(_ seconds: Double) -> String {
        Duration.seconds(seconds.rounded()).formatted(
            .time(pattern: seconds >= 3600 ? .hourMinuteSecond : .minuteSecond))
    }
}

/// The position in the current movement: a bar with no handle, as specimen player.html `.mv-bar`. A drag moves
/// playback when the finger lifts, so the movement does not restart for every step of the drag.
private struct PositionBar: View {
    @Environment(AppModel.self) private var model
    let player: PlaybackSession
    let elapsed: Double
    let duration: Double
    @State private var scrub = PositionScrub()
    @State private var width = 0.0
    @GestureState private var isTouching = false
    @ScaledMetric(space: .xs) private var lineGap: CGFloat

    var body: some View {
        let shown = min(scrub.shown(elapsed: elapsed), duration)
        VStack(alignment: .leading, spacing: lineGap) {
            bar(shown)
            PlaybackProgress.times(shown, of: duration)
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
        ZStack(alignment: .leading) {
            Capsule().fill(Palette.fillStandard)
            Capsule().fill(Palette.tint)
                .frame(width: width * PositionScrub.share(shown, of: duration))
        }
        .frame(height: Layout.positionBar)
        .onGeometryChange(for: Double.self) {
            Double($0.size.width)
        } action: {
            width = $0
        }
        // The touch area is the height of a system slider; the layout keeps the thin bar.
        .padding(.vertical, -Layout.positionBarInset)
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

/// Download a recording, follow the download, or remove it.
private struct OfflineControls: View {
    @Environment(AppModel.self) private var model
    let recording: WorkIndex.Recording
    let title: String

    var body: some View {
        let tracks = model.tracks
        if let download = tracks.downloads.first(where: { $0.id == recording.id }) {
            LabeledContent("Downloaded", value: Self.size(download.bytes))
                .ink()
            Button("Remove Download", systemImage: "trash", role: .destructive) { tracks.remove(download) }
                .accessibilityIdentifier("remove-download")
        } else if let share = tracks.progress[recording.id] {
            ProgressView(value: share) { Text("Downloading") }
            Button("Cancel Download", systemImage: "xmark.circle") { tracks.cancelDownload(recording.id) }
        } else {
            Button("Download", systemImage: "arrow.down.circle") {
                if let client = model.client { tracks.download(recording, title: title, client: client) }
            }
            .accessibilityIdentifier("download")
            if let failure = tracks.failures[recording.id] {
                Label(failure, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(Palette.textPrimary)
            }
        }
    }

    static func size(_ bytes: Int64) -> String {
        bytes.formatted(.byteCount(style: .file))
    }
}
