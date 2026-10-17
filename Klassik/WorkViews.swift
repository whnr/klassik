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
            LabeledContent(work.title, value: work.recordings.count == 1 ? "1 recording" : "\(work.recordings.count) recordings")
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
                    Button(player.isPaused ? "Resume" : "Pause", systemImage: player.isPaused ? "play.fill" : "pause.fill") {
                        player.togglePause()
                    }
                    Button("Stop", systemImage: "stop.fill") { player.stop() }
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
