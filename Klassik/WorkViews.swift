import SwiftUI

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
    /// "Composed 1844, 1 recording" (person.html workRow). The track titles stay on the work page: in a list they
    /// repeat the title or name one movement.
    nonisolated static func detail(of work: WorkIndex.Work, composed: String?) -> String {
        let recordings = WorkIndex.Recording.count(work.recordings.count, "recording")
        guard let composed else { return recordings }
        return "Composed\u{00A0}\(composed), \(recordings)"
    }
}

/// The work cover and composer lead the playback capsules and recording list, as work.html draws them.
struct WorkView: View {
    @Environment(AppModel.self) private var model
    let work: WorkIndex.Work

    private var recordings: [RecordingOrder.Row] { model.recordingOrder.rows(of: work) }

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
            if let recording = model.recordingOrder.reference(of: work) {
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

            Section {
                CountedHeading("Recordings", count: work.recordings.count)
                ForEach(recordings) { row in
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
                    .moveDisabled(!row.isFavourite)
                    .itemSeparator(first: row.id == recordings.first?.id, last: row.id == recordings.last?.id)
                }
                .onMove { model.recordingOrder.moveFavourites(of: work, from: $0, to: $1) }
                Text("Favourite recordings come first, in your order. Then the newest.")
                    .typeStyle(Layout.footnote)
                    .foregroundStyle(Palette.textSecondary)
                    .listRowSeparator(.hidden)
                    .pageEdges(top: Layout.workFootTop + Layout.footTop)
            }
        }
        .navigationTitle(work.title)
        .navigationBarTitleDisplayMode(.inline)
        .environment(\.pageHeading, "")
        .toolbar { if recordings.filter(\.isFavourite).count > 1 { EditButton() } }
        .onAppear { model.sweep.prefer(performers: recordings.flatMap(\.recording.performerNames)) }
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
    /// The note that the listener writes in the playing row. It stays while the listener scrubs (ADR 0027).
    @State private var draft: NoteDraft?
    /// Where the notes of each row live, by track position.
    @State private var places: [NotePlace?] = []

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
                    // The page and the player share one hero: the cover, then the title (specimen player.html hero).
                    VStack(spacing: Layout.bigCoverBottom) {
                        CoverImage(
                            song: isPlayingThis ? player.coverSong : recording.songs.first,
                            points: Layout.bigCover, playback: isPlayingThis
                        )
                        .frame(width: Layout.bigCover, height: Layout.bigCover)
                        .clipShape(.rect(cornerRadius: Layout.bigCoverCorner))
                        .accessibilityElement()
                        .accessibilityLabel("Cover")
                        .accessibilityIdentifier("hero-cover")
                        heroTitle
                            .accessibilityAddTraits(.isHeader)
                    }
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    header(page)
                        .listRowSeparator(.hidden)
                    if isPlayingThis, let error = player.error {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(Palette.textPrimary)
                            .listRowSeparator(.hidden)
                    }
                    if !isPlayingThis {
                        // Play is the accent capsule; Play Album is muted beside it (sz-3hcq.2).
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
                                let verb = playsAlbum ? (player.isPaused ? "Resume" : "Pause") : "Play"
                                Button {
                                    spell.touch()
                                    player.play(wholeAlbum)
                                } label: {
                                    CapsuleLabel(
                                        title: "\(verb) Album",
                                        systemImage: playsAlbum && !player.isPaused ? "pause.fill" : "play.fill",
                                        filled: false)
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("play-album")
                            }
                        }
                        .padding(.top, Layout.buttonRowTop)
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
                    Section {
                        SectionHeading(recording.isAlbum ? "Tracks" : "Movements")
                        ForEach(Array(recording.songs.enumerated()), id: \.element.id) { index, song in
                            movementRow(song, at: index, page: page, title: recording.title(of: song))
                                .itemSeparator(first: index == 0, last: index == recording.songs.count - 1)
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
                    .listRowSeparator(.hidden)
                }

                Section {
                    SectionHeading("Offline")
                    OfflineControls(recording: recording, title: work.title)
                        .listRowSeparator(.hidden)
                }

                if isOverlay { tail }
            }
            // A finger on the page, or a scroll that it started, holds the rows. The spell begins when the page is still.
            // A scroll by the app itself is not a touch. The list has no tap gesture of its own, so row controls keep their
            // taps. Each control touches the spell itself.
            .onScrollPhaseChange { _, phase in
                spell.touching(phase == .tracking || phase == .interacting || phase == .decelerating)
            }
            .onChange(of: model.isScrubbing) { _, scrubbing in spell.hold(scrubbing) }
            .onChange(of: draft != nil) { _, writing in spell.writing(writing) }
            // specimen player.html: each second, after a quiet spell, the player brings the playing row back.
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
        // The hero draws the title, so the list draws no heading. The bar keeps the name for Back and VoiceOver.
        .environment(\.pageHeading, "")
        .navigationTitle(isOverlay ? "" : work.title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { model.sweep.prefer(performers: recording.performerNames) }
        .task(id: placesKey) { places = NotePlace.places(in: recording, index: model.library.index) }
    }

    /// Changes when a sync or a new classical filter can move a track to another recording.
    private var placesKey: String {
        "\(recording.id)|\(model.library.classical.count)|\(model.library.syncedAt?.timeIntervalSince1970 ?? 0)"
    }

    /// The favourite of the page: the album on an album page, else the recording (ADR 0013, 0017).
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

    /// The end of the player: the next queue item, or where the queue ends (ADR 0014, specimen player.html).
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
            notes: place.map { model.notes.notes(at: $0) } ?? [],
            place: place,
            isPlaying: isPlayingThis && model.playback.movement == index,
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
        .id(song.id)
    }

    private func play(from index: Int) {
        spell.touch()
        opened.removeAll()
        model.playback.play(QueueItem(work: work, recording: recording), from: index)
    }

    /// A tap on a note moves to its time; a tap on its time also plays (ADR 0014). A note of a page that does not
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
/// row stays open, holds the only playback bar and takes a new note (ADR 0027).
private struct MovementRow: View {
    @Environment(AppModel.self) private var model
    let song: Song
    /// The position of the row on its page.
    let row: Int
    let title: String
    /// The names that differ from the header.
    let names: [Roles.Line]
    let notes: [ListeningNote]
    /// Where a new note of this row goes. A row without a place takes no note.
    let place: NotePlace?
    let isPlaying: Bool
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
                        RoleLines(lines: names, style: .subheadline)
                            .ink()
                    }
                    NoteList(notes: notes, jump: jump)
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
                .accessibilityHint(hint)
        } else {
            label
        }
    }

    private var hint: String {
        let what = hasNames ? (notes.isEmpty ? "the names" : "the names and notes") : "the notes"
        return (isOpen ? "Hides " : "Shows ") + what
    }

    private var label: some View {
        HStack {
            MovementTitle(title: title, style: .body)
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

    /// The playing row: its title, the names that differ, the playback bar with the note marks, the controls, the
    /// notes and the note that the listener writes (specimen player.html `openBody`).
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
            PlaybackProgress(player: player, notes: notes, jump: { jump($0, false) })
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
            NoteList(notes: notes, jump: jump)
            if let place {
                NoteEditor(
                    draft: $draft, row: row, place: place, elapsed: { player.progress?.elapsed ?? player.position })
            }
        }
        .accessibilityIdentifier("movement")
    }
}

/// The notes of a movement, earliest first. The time is a prefix in the tint (specimen player.html `.note`). A tap
/// on the text moves to the note; a tap on its time moves there and plays (ADR 0014).
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

/// "Add a note here", then the note in the row: never a modal (ADR 0027). The note stays open until Save or Return,
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

    /// Dots for moments and lines for spans above the bar. Notes that overlap stack in lanes (ADR 0014).
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

/// The row of the next queue item at the end of the player (ADR 0014). It shows the cover, title and album.
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

/// A capsule button face (specimen.css .capsule): filled in the accent, or muted on the quiet fill.
struct CapsuleLabel: View {
    let title: String
    let systemImage: String
    let filled: Bool

    var body: some View {
        HStack(spacing: Layout.capsuleGap) {
            Image(systemName: systemImage)
                .accessibilityHidden(true)
            Text(title)
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
