import SwiftUI

/// A composer's works. Albums without work tags come last, each as one work.
struct ComposerView: View {
    @Environment(AppModel.self) private var model
    let composer: WorkIndex.Composer

    var body: some View {
        let sets = composer.sets
        let loose = composer.looseWorks
        let untagged = composer.works.filter { !$0.isTagged }
        PageList {
            if let facts = model.enrichment.composer(named: composer.name), facts.born != nil || facts.died != nil {
                Section {
                    LabeledContent(
                        "Lived", value: "\(facts.born.map(String.init) ?? "?")–\(facts.died.map(String.init) ?? "")"
                    )
                    .ink()
                    if let period = Timeline.Period.of(born: facts.born, died: facts.died) {
                        LabeledContent("Period", value: period.title)
                            .ink()
                    }
                }
                .accessibilityIdentifier("composer-dates")
            }
            if !sets.isEmpty {
                Section {
                    ForEach(sets) { set in
                        DisclosureGroup {
                            ForEach(set.works) { WorkRow(work: $0) }
                        } label: {
                            LabeledContent(set.name, value: "\(set.works.count)")
                                .ink()
                        }
                        .accessibilityIdentifier("set")
                    }
                } header: {
                    SectionHeading("Sets")
                }
            }
            if !loose.isEmpty {
                Section {
                    ForEach(loose) { WorkRow(work: $0) }
                } header: {
                    SectionHeading("Works")
                }
            }
            if !untagged.isEmpty {
                Section {
                    ForEach(untagged) { WorkRow(work: $0) }
                } header: {
                    SectionHeading("Albums without work tags")
                } footer: {
                    Text("These tracks have no WORK tag, so Klassik shows each album as one work.")
                }
            }
        }
        .navigationTitle(composer.name)
        .toolbar { ShuffleButton(works: composer.works) }
    }
}

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

private struct WorkRow: View {
    @Environment(AppModel.self) private var model
    let work: WorkIndex.Work

    var body: some View {
        NavigationLink(value: Page.work(work.id)) {
            VStack(alignment: .leading) {
                HStack {
                    Text(work.title)
                        .ink()
                    OfflineHint(isOffline: work.recordings.contains { model.tracks.isOffline($0) })
                }
                Text(
                    [work.context, work.recordings.count == 1 ? "1 recording" : "\(work.recordings.count) recordings"]
                        .filter { !$0.isEmpty }.joined(separator: " · ")
                )
                .typeStyle(.subheadline)
                .foregroundStyle(Palette.textSecondary)
            }
        }
        .itemActions(work.defaultRecording.map { QueueItem(work: work, recording: $0) })
        .accessibilityIdentifier("work")
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
                    NavigationLink(value: Page.recording(work: work.id, recording: recording.id)) {
                        VStack(alignment: .leading) {
                            HStack {
                                Text(recording.performers.isEmpty ? recording.album : recording.performers)
                                    .ink()
                                if recording.isReference {
                                    Image(systemName: "star.fill")
                                        .typeStyle(.caption1)
                                        .foregroundStyle(Palette.favourite)
                                        .accessibilityLabel("Reference recording")
                                }
                                OfflineHint(isOffline: model.tracks.isOffline(recording))
                            }
                            Text(
                                [
                                    recording.year.map(String.init), recording.album,
                                    recording.completeness ?? "\(recording.songs.count) tracks",
                                ]
                                .compactMap(\.self).joined(separator: " · ")
                            )
                            .typeStyle(.subheadline)
                            .foregroundStyle(Palette.textSecondary)
                        }
                    }
                    .itemActions(QueueItem(work: work, recording: recording), downloads: true, reference: true)
                    .accessibilityIdentifier("recording")
                }
            } header: {
                SectionHeading("Recordings")
            }
        }
        .navigationTitle(work.title)
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

/// One recording: play it from the start or from any movement.
struct RecordingView: View {
    @Environment(AppModel.self) private var model
    let work: WorkIndex.Work
    let recording: WorkIndex.Recording

    private var isPlayingThis: Bool { model.playback.recording?.id == recording.id }

    /// The whole album, if it holds more than this recording.
    private var album: QueueItem? {
        guard !recording.isAlbum, let key = recording.songs.first?.albumKey,
            let album = WorkIndex.album(model.library.songs.filter { $0.albumKey == key }),
            album.recording.songs.count > recording.songs.count
        else { return nil }
        return QueueItem(work: album.work, recording: album.recording)
    }

    var body: some View {
        let player = model.playback
        PageList {
            Section {
                LabeledContent("Composer", value: work.composer)
                    .ink()
                if !recording.performers.isEmpty {
                    LabeledContent("Performers", value: recording.performers)
                        .ink()
                }
                LabeledContent("Album", value: recording.album)
                    .ink()
                if let year = recording.year {
                    LabeledContent("Year", value: String(year))
                        .ink()
                }
                NavigationLink(value: Page.rawTags(work: work.id, recording: recording.id)) {
                    Text("Tags and Grouping")
                        .ink()
                }
                .accessibilityIdentifier("raw-tags")
            }

            Section {
                if isPlayingThis {
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
                } else {
                    Button("Play", systemImage: "play.fill") { play(from: 0) }
                        .accessibilityIdentifier("play-recording")
                    if let album {
                        Button("Play Whole Album", systemImage: "square.stack") {
                            player.play(album)
                        }
                    }
                }
                if isPlayingThis, let error = player.error {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(Palette.textPrimary)
                }
            }

            Section {
                OfflineControls(recording: recording, title: work.title)
            } header: {
                SectionHeading("Offline")
            }

            Section {
                ForEach(Array(recording.songs.enumerated()), id: \.element.id) { index, song in
                    Button {
                        play(from: index)
                    } label: {
                        HStack {
                            Text(recording.title(of: song))
                                .ink()
                            Spacer()
                            if isPlayingThis, player.movement == index {
                                if player.isLoading {
                                    ProgressView()
                                } else {
                                    Image(systemName: "speaker.wave.2.fill")
                                        .foregroundStyle(Palette.tint)
                                        .accessibilityLabel("Now playing")
                                }
                            } else {
                                OfflineHint(isOffline: model.tracks.isOffline(song))
                                if let duration = song.duration {
                                    Text(Duration.seconds(duration).formatted(.time(pattern: .minuteSecond)))
                                        .foregroundStyle(Palette.textSecondary)
                                }
                            }
                        }
                    }
                    .accessibilityIdentifier("movement")
                }
            } header: {
                SectionHeading("Movements")
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
                                Text(
                                    [item.work.composer, item.recording.performers]
                                        .filter { !$0.isEmpty }.joined(separator: " · ")
                                )
                                .typeStyle(.subheadline)
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
        .navigationTitle(work.title)
        .toolbar {
            if !recording.isAlbum {
                Button(
                    recording.isReference ? "Remove Reference" : "Reference",
                    systemImage: recording.isReference ? "star.fill" : "star"
                ) {
                    Task { _ = await model.setReference(recording, of: work, to: !recording.isReference) }
                }
                .accessibilityIdentifier("reference")
            }
        }
    }

    private func play(from index: Int) {
        model.playback.play(QueueItem(work: work, recording: recording), from: index)
    }
}

/// How far the current movement and the whole work have played.
struct PlaybackProgress: View {
    let player: PlaybackSession
    @ScaledMetric(space: .m) private var gap: CGFloat
    @ScaledMetric(space: .xs) private var lineGap: CGFloat

    var body: some View {
        Group {
            if let progress = player.progress, let recording = player.recording {
                VStack(alignment: .leading, spacing: gap) {
                    PositionSlider(
                        player: player, title: recording.title(of: recording.songs[progress.movement]),
                        elapsed: progress.elapsed, duration: progress.duration
                    )
                    .id(progress.movement)
                    bar(
                        recording.isAlbum ? "Whole Album" : "Whole Work", progress.workElapsed,
                        of: progress.workDuration, gaps: progress.durations)
                }
                .padding(.vertical, lineGap)
            }
        }
        // A container keeps the identifiers of its children, such as the position slider.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("playback-progress")
    }

    private func bar(
        _ title: String, _ elapsed: Double, of duration: Double, gaps durations: [Double] = []
    ) -> some View {
        VStack(alignment: .leading, spacing: lineGap) {
            Text(title)
                .typeStyle(.subheadline)
            if durations.count > 1 {
                SegmentedBar(elapsed: elapsed, durations: durations)
            } else {
                ProgressView(value: min(elapsed, duration), total: max(duration, 1))
            }
            Self.times(elapsed, of: duration)
        }
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
    let title: String
    let elapsed: Double
    let duration: Double
    @State private var dragged: Double?
    @State private var isDragging = false
    @ScaledMetric(space: .xs) private var lineGap: CGFloat

    var body: some View {
        let shown = dragged ?? min(elapsed, duration)
        VStack(alignment: .leading, spacing: lineGap) {
            Text(title)
                .typeStyle(.subheadline)
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

/// A progress bar with a gap at each track boundary, so the bar shows how many tracks there are.
private struct SegmentedBar: View {
    let elapsed: Double
    let durations: [Double]
    private let gap = Space.xxs.points

    var body: some View {
        GeometryReader { proxy in
            let total = max(durations.reduce(0, +), 1)
            let usable = max(proxy.size.width - gap * CGFloat(durations.count - 1), 0)
            HStack(spacing: gap) {
                ForEach(durations.indices, id: \.self) { index in
                    let start = durations[..<index].reduce(0, +)
                    let share = min(max((elapsed - start) / max(durations[index], 0.001), 0), 1)
                    ZStack(alignment: .leading) {
                        Capsule().fill(Palette.timelineUnplayed)
                        Capsule().fill(Palette.timelinePlayed)
                            .frame(width: usable * durations[index] / total * share)
                    }
                    .frame(width: usable * durations[index] / total)
                }
            }
        }
        .frame(height: 4)
        .accessibilityElement()
        .accessibilityLabel("Progress")
        .accessibilityValue(
            Text(elapsed / max(durations.reduce(0, +), 1), format: .percent.precision(.fractionLength(0))))
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
