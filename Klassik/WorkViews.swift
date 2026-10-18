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
    }
}

private struct WorkRow: View {
    let work: WorkIndex.Work

    var body: some View {
        NavigationLink {
            WorkView(work: work)
        } label: {
            VStack(alignment: .leading) {
                Text(work.title)
                Text([work.context, work.recordings.count == 1 ? "1 recording" : "\(work.recordings.count) recordings"]
                    .filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityIdentifier("work")
    }
}

/// A work's recordings, oldest first, with the performers up front.
struct WorkView: View {
    let work: WorkIndex.Work

    var body: some View {
        List {
            Section {
                LabeledContent("Composer", value: work.composer)
                if !work.context.isEmpty {
                    Text(work.context)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                ForEach(work.recordings) { recording in
                    NavigationLink {
                        RecordingView(work: work, recording: recording)
                    } label: {
                        VStack(alignment: .leading) {
                            Text(recording.performers.isEmpty ? recording.album : recording.performers)
                            Text([recording.year.map(String.init), recording.album, "\(recording.songs.count) tracks"]
                                .compactMap(\.self).joined(separator: " · "))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityIdentifier("recording")
                }
            } header: {
                Text("Recordings")
            }
        }
        .navigationTitle(work.title)
    }
}

/// One recording: play it from the start or from any movement.
struct RecordingView: View {
    @Environment(AppModel.self) private var model
    let work: WorkIndex.Work
    let recording: WorkIndex.Recording

    private var isPlayingThis: Bool { model.player.recording?.id == recording.id }

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
                        Button(player.isPaused ? "Resume" : "Pause", systemImage: player.isPaused ? "play.fill" : "pause.fill") {
                            player.togglePause()
                        }
                        Spacer()
                        Button("Next", systemImage: "forward.fill") { player.next() }
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
                }
                if isPlayingThis, let error = player.error {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                }
            }

            Section("Movements") {
                ForEach(Array(recording.songs.enumerated()), id: \.element.id) { index, song in
                    Button {
                        play(from: index)
                    } label: {
                        HStack {
                            Text(song.movementTitle)
                                .foregroundStyle(.primary)
                            Spacer()
                            if isPlayingThis, player.current == index {
                                if player.isLoading {
                                    ProgressView()
                                } else {
                                    Image(systemName: "speaker.wave.2.fill")
                                        .foregroundStyle(.tint)
                                        .accessibilityLabel("Now playing")
                                }
                            } else if let duration = song.duration {
                                Text(Duration.seconds(duration).formatted(.time(pattern: .minuteSecond)))
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                        }
                    }
                    .accessibilityIdentifier("movement")
                }
            }
        }
        .navigationTitle(work.title)
        .navigationBarTitleDisplayMode(.inline)
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
                    bar(recording.songs[progress.movement].movementTitle, progress.elapsed, of: progress.duration)
                    bar("Whole Work", progress.workElapsed, of: progress.workDuration)
                }
                .padding(.vertical, 4)
            }
        }
        .accessibilityIdentifier("playback-progress")
    }

    private func bar(_ title: String, _ elapsed: Double, of duration: Double) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.subheadline)
            ProgressView(value: min(elapsed, duration), total: max(duration, 1))
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
        Duration.seconds(seconds.rounded()).formatted(.time(pattern: seconds >= 3600 ? .hourMinuteSecond : .minuteSecond))
    }
}
