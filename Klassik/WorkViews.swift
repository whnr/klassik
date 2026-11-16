import SwiftUI

/// Plays works in random order. The movements of each work stay in order.
struct ShuffleButton: View {
    @Environment(AppModel.self) private var model
    let works: [WorkIndex.Work]

    var body: some View {
        Button("Shuffle Works", systemImage: "shuffle") {
            let items = works.shuffled().compactMap { work in
                work.defaultRecording.map { QueueItem(work: work, recording: $0) }
            }
            model.playback.play(queue: items)
        }
        .disabled(works.isEmpty)
        .accessibilityIdentifier("shuffle")
    }
}

/// The actions of a row that stands for one recording or one album. Trailing swipe: the queue. Leading swipe:
/// download and reference recording. The context menu holds all of them, as in Apple Music.
private struct ItemActions: ViewModifier {
    @Environment(AppModel.self) private var model
    let item: QueueItem
    /// Only recordings and albums download, never a whole work.
    let downloads: Bool
    let reference: Bool

    func body(content: Content) -> some View {
        content
            .swipeActions(edge: .trailing) {
                ForEach(SwipeSettings.actions(model.swipes.trailing)) { button(for: $0) }
            }
            .swipeActions(edge: .leading) {
                ForEach(SwipeSettings.actions(model.swipes.leading)) { button(for: $0) }
            }
            .contextMenu {
                Button("Play", systemImage: "play") { model.playback.play(item) }
                Button("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward") { playNext() }
                Button("Add to Queue", systemImage: "text.line.last.and.arrowtriangle.forward") { addToQueue() }
                if downloads { downloadButton }
                if reference { referenceButton }
            }
    }

    /// A row that cannot do an action leaves it out: works never download, albums have no reference.
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
        case .reference:
            if reference { referenceButton.tint(Palette.swipeFavourite.color) }
        }
    }

    @ViewBuilder private var downloadButton: some View {
        let tracks = model.tracks
        if let download = tracks.downloads.first(where: { $0.id == item.recording.id }) {
            Button("Remove Download", systemImage: "trash") { tracks.remove(download) }
        } else if tracks.progress[item.recording.id] != nil {
            Button("Cancel Download", systemImage: "xmark.circle") { tracks.cancelDownload(item.recording.id) }
        } else {
            Button("Download", systemImage: "arrow.down.circle") {
                if let client = model.client {
                    tracks.download(item.recording, title: item.work.title, client: client)
                }
            }
        }
    }

    private var referenceButton: some View {
        let isReference = item.recording.isReference
        return Button(
            isReference ? "Remove Reference" : "Reference", systemImage: isReference ? "star.slash" : "star"
        ) {
            Task { _ = await model.setReference(item.recording, of: item.work, to: !isReference) }
        }
    }

    private func playNext() {
        model.playback.playNext(item)
    }

    private func addToQueue() {
        model.playback.addToQueue(item)
    }
}

extension View {
    @ViewBuilder func itemActions(_ item: QueueItem?, downloads: Bool = false, reference: Bool = false) -> some View {
        if let item { modifier(ItemActions(item: item, downloads: downloads, reference: reference)) } else { self }
    }
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
            .itemActions(album.item, downloads: true)
            .accessibilityIdentifier("album")
        } else {
            NavigationLink(value: Page.work(work.id)) {
                VStack(alignment: .leading, spacing: gap) {
                    HStack {
                        Text(work.title)
                            .ink()
                        OfflineHint(isOffline: work.recordings.contains { model.tracks.isOffline($0) })
                    }
                    if !work.context.isEmpty {
                        Text(work.context)
                            .typeStyle(.footnote)
                            .foregroundStyle(Palette.textSecondary)
                    }
                    Text(facts)
                        .typeStyle(.footnote)
                        .foregroundStyle(Palette.textSecondary)
                }
            }
            .itemActions(work.defaultRecording.map { QueueItem(work: work, recording: $0) })
            .accessibilityIdentifier("work")
        }
    }

    /// When the work was composed, then the recordings: "Composed 1844, 1 recording".
    private var facts: String {
        let recordings = WorkIndex.Recording.count(work.recordings.count, "recording")
        guard let composed = model.enrichment.composed(work) else { return recordings }
        return "Composed\u{00A0}\(composed.span.text), \(recordings)"
    }
}

/// A work's page as work.html draws it: composer under the title, a Play pill, then the recordings on plain rows.
struct WorkView: View {
    @Environment(AppModel.self) private var model
    let work: WorkIndex.Work

    /// Favourite recordings come first. The rest keep the order of the index.
    private var recordings: [WorkIndex.Recording] {
        work.recordings.filter(\.isReference) + work.recordings.filter { !$0.isReference }
    }

    var body: some View {
        PageList {
            WorkHeader(work: work)
                .listRowSeparator(.hidden)
                .pageEdges(bottom: Layout.headBottom)
            if let recording = work.defaultRecording {
                Button {
                    model.playback.play(QueueItem(work: work, recording: recording))
                } label: {
                    Label(
                        recording.isReference ? "Play Reference Recording" : "Play", systemImage: "play.fill"
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
                ForEach(recordings) { recording in
                    let isPlaying = plays(recording)
                    NavigationLink(value: Page.recording(work: work.id, recording: recording.id)) {
                        RecordingRow(
                            recording: recording, isOffline: model.tracks.isOffline(recording),
                            playsFirst: recording.id == work.defaultRecording?.id, isPlaying: isPlaying)
                    }
                    // The whole row of what plays is tinted, edge to edge, so the listener sees it while browsing.
                    .listRowBackground(isPlaying ? Palette.tint.color.opacity(0.12) : Color.clear)
                    .itemActions(QueueItem(work: work, recording: recording), downloads: true, reference: true)
                    .accessibilityIdentifier("recording")
                }
                Text("Favourite recordings come first. Then the oldest.")
                    .typeStyle(Layout.footnote)
                    .foregroundStyle(Palette.textSecondary)
                    .listRowSeparator(.hidden)
                    .pageEdges(top: Layout.workFootTop + Layout.footTop)
            }
        }
        .pageTitle(work.title)
        .environment(\.pageHeadingBottom, Layout.metaTop)
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
                if playsFirst {
                    Text("Plays first")
                        .typeStyle(.footnote)
                        .foregroundStyle(Palette.tint)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // Every row keeps the room of the slot, so the playing row tints in place and its text does not rewrap.
            slot
                .opacity(isPlaying ? 1 : 0)
                .disabled(!isPlaying)
                .accessibilityHidden(!isPlaying)
        }
    }

    private var title: some View {
        HStack(alignment: .firstTextBaseline, spacing: fermataGap) {
            Text(lead.isEmpty ? recording.album : Roles.Line.list(lead))
                .ink()
                .fixedSize(horizontal: false, vertical: true)
            if recording.isReference {
                FermataMark(isSet: true)
            }
            OfflineHint(isOffline: isOffline)
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
    @State private var followsMovement = false

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
                            HStack(alignment: .firstTextBaseline) {
                                Text(work.title)
                                    .accessibilityIdentifier("player-title")
                                    .typeStyle(Layout.pageTitle)
                                    .ink()
                                if !recording.isAlbum { referenceButton }
                            }
                            .buttonStyle(.borderless)
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
                            Button("Play Whole Album", systemImage: "square.stack") {
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
            }
            // A finger on the page, or a scroll that it started, holds the rows. The spell begins when the page is still.
            // A scroll by the app itself is not a touch. The list has no tap gesture of its own, so row controls keep their
            // taps. Each control touches the spell itself.
            .onScrollPhaseChange { _, phase in
                spell.touching(phase == .tracking || phase == .interacting || phase == .decelerating)
            }
            .onChange(of: model.isScrubbingTimeline) { _, scrubbing in spell.hold(scrubbing) }
            .task(id: isOverlay && isPlayingThis ? player.movement : nil) {
                guard isOverlay, isPlayingThis, let movement = player.movement,
                    recording.songs.indices.contains(movement)
                else { return }
                // Opening the player shows its header. Only a later movement change follows the rows.
                guard followsMovement else {
                    followsMovement = true
                    return
                }
                while let rest = spell.wait() {
                    try? await Task.sleep(for: rest)
                    if Task.isCancelled { return }
                }
                withAnimation(Motion.glide.animation(reduceMotion: reduceMotion)) {
                    proxy.scrollTo(recording.songs[movement].id, anchor: UnitPoint(x: 0.5, y: 0.2))
                }
            }
        }
        .pageTitle(isOverlay ? "" : work.title)
        .toolbar {
            if !isOverlay, !recording.isAlbum { referenceButton }
        }
    }

    private var referenceButton: some View {
        // The page can show a queue copy. The library supplies current Reference state.
        let live = model.library.current(work: work, recording: recording)
        return Button(
            live.recording.isReference ? "Remove Reference" : "Reference",
            systemImage: live.recording.isReference ? "star.fill" : "star"
        ) {
            Task {
                _ = await model.setReference(live.recording, of: live.work, to: !live.recording.isReference)
            }
        }
        .labelStyle(.iconOnly)
        .accessibilityIdentifier("reference")
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
                .buttonStyle(.borderless)
                .accessibilityHint(isOpen ? "Hides the names" : "Shows the names")
        } else {
            label
        }
    }

    private var label: some View {
        HStack {
            Text(title)
                .ink()
            Spacer()
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
                Text(title)
                    .typeStyle(.headline)
                    .ink()
                Spacer()
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

/// How far the playing movement has played.
struct PlaybackProgress: View {
    let player: PlaybackSession
    @ScaledMetric(space: .xs) private var lineGap: CGFloat

    var body: some View {
        Group {
            if let progress = player.progress {
                PositionSlider(player: player, elapsed: progress.elapsed, duration: progress.duration)
                    .id(progress.movement)
                    .padding(.vertical, lineGap)
            }
        }
        // A container keeps the identifiers of its children, such as the position slider.
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

/// The position in the current movement. A drag moves playback when the finger lifts, so the movement does not
/// restart for every step of the drag.
private struct PositionSlider: View {
    let player: PlaybackSession
    let elapsed: Double
    let duration: Double
    @State private var dragged: Double?
    @State private var isDragging = false
    @ScaledMetric(space: .xs) private var lineGap: CGFloat

    var body: some View {
        let shown = dragged ?? min(elapsed, duration)
        VStack(alignment: .leading, spacing: lineGap) {
            Slider(
                value: Binding(
                    get: { shown },
                    set: { value in
                        dragged = value
                        // VoiceOver adjusts the value without a drag.
                        if !isDragging { seek() }
                    }),
                in: 0...max(duration, 1)
            ) { editing in
                isDragging = editing
                if !editing { seek() }
            }
            .accessibilityLabel("Position")
            .accessibilityValue(PlaybackProgress.time(shown))
            .accessibilityIdentifier("position")
            PlaybackProgress.times(shown, of: duration)
        }
    }

    private func seek() {
        guard let dragged else { return }
        player.seek(to: dragged)
        // The player reports the new position at once, so the slider does not jump back.
        self.dragged = nil
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
