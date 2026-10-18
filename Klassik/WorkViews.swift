import SwiftUI

/// A composer's works. Albums without work tags come last, each as one work.
struct ComposerView: View {
    let composer: WorkIndex.Composer

    var body: some View {
        let tagged = composer.works.filter(\.isTagged)
        let untagged = composer.works.filter { !$0.isTagged }
        List {
            if !tagged.isEmpty {
                Section("Works") {
                    ForEach(tagged) { WorkRow(work: $0) }
                }
            }
            if !untagged.isEmpty {
                Section {
                    ForEach(untagged) { WorkRow(work: $0) }
                } header: {
                    Text("Albums Without Work Tags")
                } footer: {
                    Text("These tracks have no WORK tag, so Klassik shows each album as one work.")
                }
            }
        }
        .navigationTitle(composer.name)
        .miniPlayerInset()
        .toolbar { ShuffleButton(works: composer.works) }
    }
}

/// Plays works in random order. The movements of each work stay in order.
struct ShuffleButton: View {
    @Environment(AppModel.self) private var model
    let works: [WorkIndex.Work]

    var body: some View {
        Button("Shuffle Works", systemImage: "shuffle") {
            guard let client = model.client else { return }
            let items = works.shuffled().compactMap { work in
                work.defaultRecording.map { Player.Item(work: work, recording: $0) }
            }
            model.player.play(items, client: client)
        }
        .disabled(works.isEmpty)
        .accessibilityIdentifier("shuffle")
    }
}

/// The actions of a row that stands for one recording or one album. Trailing swipe: the queue. Leading swipe:
/// download and reference recording. The context menu holds all of them, as in Apple Music.
private struct ItemActions: ViewModifier {
    @Environment(AppModel.self) private var model
    let item: Player.Item
    /// Only recordings and albums download, never a whole work.
    let downloads: Bool
    let reference: Bool

    func body(content: Content) -> some View {
        content
            .swipeActions(edge: .trailing) {
                Button("Add to Queue", systemImage: "text.line.last.and.arrowtriangle.forward") { addToQueue() }
                    .tint(.orange)
                Button("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward") { playNext() }
                    .tint(.indigo)
            }
            .swipeActions(edge: .leading) {
                if downloads { downloadButton.tint(.blue) }
                if reference { referenceButton.tint(.yellow) }
            }
            .contextMenu {
                Button("Play", systemImage: "play") {
                    if let client = model.client { model.player.play([item], client: client) }
                }
                Button("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward") { playNext() }
                Button("Add to Queue", systemImage: "text.line.last.and.arrowtriangle.forward") { addToQueue() }
                if downloads { downloadButton }
                if reference { referenceButton }
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
        if let client = model.client { model.player.playNext(item, client: client) }
    }

    private func addToQueue() {
        if let client = model.client { model.player.addToQueue(item, client: client) }
    }
}

extension View {
    @ViewBuilder func itemActions(_ item: Player.Item?, downloads: Bool = false, reference: Bool = false) -> some View {
        if let item { modifier(ItemActions(item: item, downloads: downloads, reference: reference)) } else { self }
    }
}

/// A small mark on rows that play without the server.
struct OfflineHint: View {
    let isOffline: Bool

    var body: some View {
        if isOffline {
            Image(systemName: "arrow.down.circle.fill")
                .font(.caption)
                .foregroundStyle(Color.secondary)
                .accessibilityLabel("Available offline")
        }
    }
}

private struct WorkRow: View {
    @Environment(AppModel.self) private var model
    let work: WorkIndex.Work

    var body: some View {
        NavigationLink {
            WorkView(work: work)
        } label: {
            VStack(alignment: .leading) {
                HStack {
                    Text(work.title)
                    OfflineHint(isOffline: work.recordings.contains { model.tracks.isOffline($0) })
                }
                Text(
                    [work.context, work.recordings.count == 1 ? "1 recording" : "\(work.recordings.count) recordings"]
                        .filter { !$0.isEmpty }.joined(separator: " · ")
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
        }
        .itemActions(work.defaultRecording.map { Player.Item(work: work, recording: $0) })
        .accessibilityIdentifier("work")
    }
}

/// A work's recordings, oldest first, with the performers up front.
struct WorkView: View {
    @Environment(AppModel.self) private var model
    let work: WorkIndex.Work

    var body: some View {
        List {
            Section {
                LabeledContent("Composer", value: work.composer)
                if !work.context.isEmpty {
                    Text(work.context)
                        .foregroundStyle(.secondary)
                }
                if let recording = work.defaultRecording {
                    Button(recording.isReference ? "Play Reference Recording" : "Play", systemImage: "play.fill") {
                        if let client = model.client { model.player.play(recording, of: work, client: client) }
                    }
                    .accessibilityIdentifier("play-work")
                }
            }

            Section {
                ForEach(work.recordings) { recording in
                    NavigationLink {
                        // Here and not in RecordingView, because the now-playing sheet also shows RecordingView.
                        RecordingView(work: work, recording: recording)
                            .miniPlayerInset()
                    } label: {
                        VStack(alignment: .leading) {
                            HStack {
                                Text(recording.performers.isEmpty ? recording.album : recording.performers)
                                if recording.isReference {
                                    Image(systemName: "star.fill")
                                        .font(.caption)
                                        .foregroundStyle(.yellow)
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
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        }
                    }
                    .itemActions(Player.Item(work: work, recording: recording), downloads: true, reference: true)
                    .accessibilityIdentifier("recording")
                }
            } header: {
                Text("Recordings")
            }
        }
        .navigationTitle(work.title)
        .miniPlayerInset()
    }
}

/// One recording: play it from the start or from any movement.
struct RecordingView: View {
    @Environment(AppModel.self) private var model
    let work: WorkIndex.Work
    let recording: WorkIndex.Recording

    private var isPlayingThis: Bool { model.player.recording?.id == recording.id }

    /// The whole album, if it holds more than this recording.
    private var album: Player.Item? {
        guard !recording.isAlbum, let key = recording.songs.first?.albumKey,
            let album = WorkIndex.album(model.library.songs.filter { $0.albumKey == key }),
            album.recording.songs.count > recording.songs.count
        else { return nil }
        return Player.Item(work: album.work, recording: album.recording)
    }

    var body: some View {
        let player = model.player
        List {
            Section {
                LabeledContent("Composer", value: work.composer)
                if !recording.performers.isEmpty {
                    LabeledContent("Performers", value: recording.performers)
                }
                LabeledContent("Album", value: recording.album)
                if let year = recording.year {
                    LabeledContent("Year", value: String(year))
                }
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
                        Spacer()
                        Button("Next Work", systemImage: "forward.end.fill") { player.nextWork() }
                            .disabled(player.upNext.isEmpty)
                        Spacer()
                        Button("Stop", systemImage: "stop.fill") { player.stop() }
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .font(.title2)
                    .padding(.horizontal)
                } else {
                    Button("Play", systemImage: "play.fill") { play(from: 0) }
                        .accessibilityIdentifier("play-recording")
                    if let album {
                        Button("Play Whole Album", systemImage: "square.stack") {
                            if let client = model.client { player.play([album], client: client) }
                        }
                    }
                }
                if isPlayingThis, let error = player.error {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                }
            }

            Section("Offline") {
                OfflineControls(recording: recording, title: work.title)
            }

            Section("Movements") {
                ForEach(Array(recording.songs.enumerated()), id: \.element.id) { index, song in
                    Button {
                        play(from: index)
                    } label: {
                        HStack {
                            Text(recording.title(of: song))
                                .foregroundStyle(Color.primary)
                            Spacer()
                            if isPlayingThis, player.current == index {
                                if player.isLoading {
                                    ProgressView()
                                } else {
                                    Image(systemName: "speaker.wave.2.fill")
                                        .foregroundStyle(.tint)
                                        .accessibilityLabel("Now playing")
                                }
                            } else {
                                OfflineHint(isOffline: model.tracks.isOffline(song))
                                if let duration = song.duration {
                                    Text(Duration.seconds(duration).formatted(.time(pattern: .minuteSecond)))
                                        .foregroundStyle(Color.secondary)
                                        .monospacedDigit()
                                }
                            }
                        }
                    }
                    .accessibilityIdentifier("movement")
                }
            }

            if isPlayingThis, !player.upNext.isEmpty {
                Section("Up Next") {
                    ForEach(player.upNext) { item in
                        Button {
                            player.playQueued(item.id)
                        } label: {
                            VStack(alignment: .leading) {
                                Text(item.work.title)
                                    .foregroundStyle(Color.primary)
                                Text(
                                    [item.work.composer, item.recording.performers]
                                        .filter { !$0.isEmpty }.joined(separator: " · ")
                                )
                                .font(.subheadline)
                                .foregroundStyle(Color.secondary)
                            }
                        }
                        .accessibilityIdentifier("up-next")
                    }
                    .onDelete { player.removeFromQueue(at: $0) }
                    .onMove { player.moveInQueue(from: $0, to: $1) }
                }
            }
        }
        .navigationTitle(work.title)
        .navigationBarTitleDisplayMode(.inline)
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
        guard let client = model.client else { return }
        model.player.play(recording, of: work, from: index, client: client)
    }
}

/// How far the current movement and the whole work have played.
struct PlaybackProgress: View {
    let player: Player

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { _ in
            if let progress = player.progress(), let recording = player.recording {
                VStack(alignment: .leading, spacing: 12) {
                    bar(
                        recording.title(of: recording.songs[progress.movement]), progress.elapsed, of: progress.duration
                    )
                    bar(
                        recording.isAlbum ? "Whole Album" : "Whole Work", progress.workElapsed,
                        of: progress.workDuration, gaps: progress.durations)
                }
                .padding(.vertical, 4)
            }
        }
        .accessibilityIdentifier("playback-progress")
    }

    private func bar(
        _ title: String, _ elapsed: Double, of duration: Double, gaps durations: [Double] = []
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.subheadline)
            if durations.count > 1 {
                SegmentedBar(elapsed: elapsed, durations: durations)
            } else {
                ProgressView(value: min(elapsed, duration), total: max(duration, 1))
            }
            HStack {
                Text(Self.time(elapsed))
                Spacer()
                Text("−" + Self.time(max(duration - elapsed, 0)))
            }
            .font(.caption)
            .monospacedDigit()
            .foregroundStyle(.secondary)
        }
    }

    static func time(_ seconds: Double) -> String {
        Duration.seconds(seconds.rounded()).formatted(
            .time(pattern: seconds >= 3600 ? .hourMinuteSecond : .minuteSecond))
    }
}

/// A progress bar with a gap at each track boundary, so the bar shows how many tracks there are.
private struct SegmentedBar: View {
    let elapsed: Double
    let durations: [Double]
    private let gap: CGFloat = 2

    var body: some View {
        GeometryReader { proxy in
            let total = max(durations.reduce(0, +), 1)
            let usable = max(proxy.size.width - gap * CGFloat(durations.count - 1), 0)
            HStack(spacing: gap) {
                ForEach(durations.indices, id: \.self) { index in
                    let start = durations[..<index].reduce(0, +)
                    let share = min(max((elapsed - start) / max(durations[index], 0.001), 0), 1)
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.secondary.opacity(0.25))
                        Capsule().fill(Color.accentColor)
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
                    .foregroundStyle(.red)
            }
        }
    }

    static func size(_ bytes: Int64) -> String {
        bytes.formatted(.byteCount(style: .file))
    }
}
