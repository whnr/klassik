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

    var body: some View {
        if let album = work.albumKey.flatMap({ model.library.index.album($0) }) {
            NavigationLink(value: Page.album(album.id)) {
                VStack(alignment: .leading) {
                    HStack {
                        Text(album.title)
                            .ink()
                        OfflineHint(isOffline: model.tracks.isOffline(album.recording))
                    }
                    Text(WorkIndex.Recording.count(album.tracks.count, "track"))
                        .typeStyle(.subheadline)
                        .foregroundStyle(Palette.textSecondary)
                }
            }
            .itemActions(album.item, downloads: true)
            .accessibilityIdentifier("album")
        } else {
            NavigationLink(value: Page.work(work.id)) {
                VStack(alignment: .leading) {
                    HStack {
                        Text(work.title)
                            .ink()
                        OfflineHint(isOffline: work.recordings.contains { model.tracks.isOffline($0) })
                    }
                    if !work.context.isEmpty {
                        Text(work.context)
                            .typeStyle(.subheadline)
                            .foregroundStyle(Palette.textSecondary)
                    }
                    Text(WorkIndex.Recording.count(work.recordings.count, "recording"))
                        .typeStyle(.subheadline)
                        .foregroundStyle(Palette.textSecondary)
                }
            }
            .itemActions(work.defaultRecording.map { QueueItem(work: work, recording: $0) })
            .accessibilityIdentifier("work")
        }
    }
}

/// A work's recordings, oldest first, with the performers up front.
struct WorkView: View {
    @Environment(AppModel.self) private var model
    let work: WorkIndex.Work

    var body: some View {
        PageList {
            Section {
                NavigationLink(value: Page.composer(work.composer)) {
                    LabeledContent("Composer", value: work.composer)
                        .ink()
                }
                .accessibilityIdentifier("work-composer")
                if !work.context.isEmpty {
                    Text(work.context)
                        .foregroundStyle(Palette.textSecondary)
                }
                if work.isTagged {
                    ComposedRow(work: work)
                }
                if let recording = work.defaultRecording {
                    Button(recording.isReference ? "Play Reference Recording" : "Play", systemImage: "play.fill") {
                        model.playback.play(QueueItem(work: work, recording: recording))
                    }
                    .accessibilityIdentifier("play-work")
                }
            }

            Section {
                ForEach(work.recordings) { recording in
                    let isPlaying = plays(recording)
                    NavigationLink(value: Page.recording(work: work.id, recording: recording.id)) {
                        RecordingRow(
                            recording: recording, isOffline: model.tracks.isOffline(recording),
                            isReference: recording.isReference, isPlaying: isPlaying)
                    }
                    // The row of what plays is tinted, so the listener sees it while browsing (ADR 0015).
                    .listRowBackground(isPlaying ? Palette.tint.color.opacity(0.12) : Palette.backgroundRow.color)
                    .itemActions(QueueItem(work: work, recording: recording), downloads: true, reference: true)
                    .accessibilityIdentifier("recording")
                }
            } header: {
                SectionHeading("Recordings")
            }
        }
        .pageTitle(work.title)
    }

    private func plays(_ recording: WorkIndex.Recording) -> Bool {
        guard let item = model.playback.item else { return false }
        return item.work.id == work.id && item.recording.id == recording.id
    }
}

/// A recording on the work page: its own cover, the principal performers, every other name, and the facts in prose.
private struct RecordingRow: View {
    let recording: WorkIndex.Recording
    let isOffline: Bool
    let isReference: Bool
    let isPlaying: Bool
    @Environment(AppModel.self) private var model
    @ScaledMetric(relativeTo: .body) private var cover: CGFloat = 56
    @ScaledMetric(space: .inGroup) private var gap: CGFloat

    var body: some View {
        let principal = recording.principalNames
        let others = recording.otherNames
        HStack(alignment: .top, spacing: Space.m.points) {
            CoverImage(id: recording.songs.first?.coverArt, points: cover)
                .frame(width: cover, height: cover)
                .clipShape(.rect(cornerRadius: Radius.s))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: gap) {
                HStack(alignment: .firstTextBaseline) {
                    if principal.isEmpty && others.isEmpty {
                        Text(recording.album)
                            .ink()
                    } else {
                        RoleLines(lines: principal)
                            .ink()
                    }
                    if isReference {
                        Image(systemName: "star.fill")
                            .typeStyle(.caption1)
                            .foregroundStyle(Palette.favourite)
                            .accessibilityLabel("Reference recording")
                    }
                    OfflineHint(isOffline: isOffline)
                }
                // The facts hold the year, so they come before the other names (spec: performers and year first).
                Text(recording.facts())
                    .typeStyle(.subheadline)
                    .foregroundStyle(Palette.textSecondary)
                RoleLines(lines: others)
                    .ink()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if isPlaying { slot }
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

/// When the work was composed. It opens the sources, and asks the listener to confirm an unclear match.
private struct ComposedRow: View {
    @Environment(AppModel.self) private var model
    let work: WorkIndex.Work

    var body: some View {
        let enrichment = model.enrichment
        NavigationLink(value: Page.sources(work: work.id)) {
            if case .candidates = enrichment.link(of: work) {
                InkLabel("Confirm the MusicBrainz Work", systemImage: "questionmark.circle")
            } else {
                LabeledContent("Composed") {
                    if let composed = enrichment.composed(work) {
                        Text(composed.span.text)
                    } else {
                        Text(enrichment.isRunning ? "Looking up…" : "Unknown")
                    }
                }
                .ink()
            }
        }
        .accessibilityIdentifier("composed")
    }
}

/// The page of a recording or album. While it plays, it is the player (ADR 0015): the header holds what every track
/// shares, a row holds what differs, and only the playing movement has a playback bar (ADR 0027).
struct RecordingView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let work: WorkIndex.Work
    let recording: WorkIndex.Recording
    /// Set on the album page, which lists the tracks of the album.
    var album: WorkIndex.Album?
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
                                player.play(wholeAlbum)
                            }
                        }
                    }
                }

                if let album, album.showsWorkHeadings {
                    ForEach(album.blocks) { block in
                        Section {
                            ForEach(Array(block.tracks.enumerated()), id: \.element.id) { offset, song in
                                movementRow(
                                    song, at: block.start + offset, page: page,
                                    title: album.title(of: song, in: block))
                            }
                        } header: {
                            heading(of: block)
                        }
                    }
                } else {
                    Section {
                        ForEach(Array(recording.songs.enumerated()), id: \.element.id) { index, song in
                            movementRow(song, at: index, page: page, title: recording.title(of: song))
                        }
                    } header: {
                        SectionHeading(recording.isAlbum ? "Tracks" : "Movements")
                    }
                }

                Section {
                    NavigationLink(value: Page.rawTags(work: work.id, recording: recording.id)) {
                        Text("Tags and Grouping")
                            .ink()
                    }
                    .accessibilityIdentifier("raw-tags")
                }

                Section {
                    OfflineControls(recording: recording, title: work.title)
                } header: {
                    SectionHeading("Offline")
                }

                if isPlayingThis, !player.upNext.isEmpty {
                    Section {
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
                    } header: {
                        SectionHeading("Up next")
                    }
                }
            }
            // A finger on the page, or a scroll that it started, holds the rows. The spell begins when the page is still.
            // A scroll by the app itself is not a touch.
            .onScrollPhaseChange { _, phase in
                spell.touching(phase == .tracking || phase == .interacting || phase == .decelerating)
            }
            .simultaneousGesture(TapGesture().onEnded { spell.touch() })
            .onChange(of: model.isScrubbingTimeline) { _, scrubbing in spell.hold(scrubbing) }
            .task(id: isPlayingThis ? player.movement : nil) {
                guard isPlayingThis, let movement = player.movement, recording.songs.indices.contains(movement)
                else { return }
                while let rest = spell.wait() {
                    try? await Task.sleep(for: rest)
                    if Task.isCancelled { return }
                }
                withAnimation(Motion.glide.animation(reduceMotion: reduceMotion)) {
                    proxy.scrollTo(recording.songs[movement].id, anchor: UnitPoint(x: 0.5, y: 0.2))
                }
            }
        }
        .pageTitle(work.title)
        .toolbar {
            if !recording.isAlbum {
                // The page can show a queue copy. The state and the change come from the library.
                let live = model.library.current(work: work, recording: recording)
                Button(
                    live.recording.isReference ? "Remove Reference" : "Reference",
                    systemImage: live.recording.isReference ? "star.fill" : "star"
                ) {
                    Task {
                        _ = await model.setReference(live.recording, of: live.work, to: !live.recording.isReference)
                    }
                }
                .accessibilityIdentifier("reference")
            }
        }
    }

    /// What every track shares, in centred lines.
    private func header(_ page: PlayerPage) -> some View {
        VStack(spacing: Space.xs.points) {
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

    /// The work of a block opens its recording page, so the listener reaches the work from the disc.
    @ViewBuilder private func heading(of block: WorkIndex.Album.Block) -> some View {
        if let part = block.part {
            NavigationLink(value: Page.recording(work: part.workID, recording: part.recordingID)) {
                HStack {
                    SectionHeading(part.title)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundStyle(Palette.textSecondary)
                }
            }
            .accessibilityIdentifier("album-work")
        }
    }

    private func movementRow(_ song: Song, at index: Int, page: PlayerPage, title: String) -> some View {
        MovementRow(
            song: song, title: title, names: page.differing.indices.contains(index) ? page.differing[index] : [],
            isPlaying: isPlayingThis && model.playback.movement == index,
            isOpen: opened.contains(index),
            toggle: {
                if opened.contains(index) { opened.remove(index) } else { opened.insert(index) }
            },
            play: { play(from: index) }
        )
        .id(song.id)
    }

    private func play(from index: Int) {
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
                .frame(width: Measure.hitTarget * 0.7, height: Measure.hitTarget * 0.7)
                .background(Palette.fillQuiet, in: .circle)
                .frame(width: Measure.hitTarget, height: Measure.hitTarget)
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
