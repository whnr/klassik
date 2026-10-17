import SwiftUI

/// Finds an album on the server for the gapless comparison.
struct GaplessTestView: View {
    @Environment(AppModel.self) private var model
    @State private var query = ""
    @State private var albums: [Album] = []
    @State private var error: String?

    var body: some View {
        List {
            Section {
                ForEach(albums) { album in
                    NavigationLink {
                        GaplessAlbumView(album: album)
                    } label: {
                        VStack(alignment: .leading) {
                            Text(album.name)
                            if let artist = album.artist {
                                Text(artist)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .accessibilityIdentifier("gapless-album")
                }
            } footer: {
                Text(error ?? "Search for a work whose movements run into each other, then listen at each change of track.")
            }
        }
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Album")
        .onSubmit(of: .search) {
            Task { await search() }
        }
        .navigationTitle("Gapless Test")
    }

    private func search() async {
        guard let client = model.client else { return }
        do {
            albums = try await client.searchAlbums(query)
            error = albums.isEmpty ? "No album found." : nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct GaplessAlbumView: View {
    @Environment(AppModel.self) private var model
    let album: Album
    @State private var songs: [Song] = []
    @State private var player = GaplessTestPlayer()
    @State private var kind = GaplessTestPlayer.Kind.audioEngine
    @State private var startNearEnd = true

    var body: some View {
        Form {
            Section {
                Picker("Player", selection: $kind) {
                    ForEach(GaplessTestPlayer.Kind.allCases) { Text($0.rawValue).tag($0) }
                }
                Toggle("Start 10 s Before the End", isOn: $startNearEnd)
            } footer: {
                Text("AVQueuePlayer streams each track. AVAudioEngine downloads each track and cuts encoder delay and padding as the MP3 header specifies.")
            }

            Section("Tap a Track to Play from There") {
                ForEach(Array(songs.enumerated()), id: \.element.id) { index, song in
                    Button {
                        guard let client = model.client else { return }
                        player.play(songs, from: index, with: kind, client: client, lastSeconds: startNearEnd ? 10 : nil)
                    } label: {
                        VStack(alignment: .leading) {
                            Text(song.title)
                                .foregroundStyle(.primary)
                            if let analysis = player.analysis[song.id] {
                                Text(analysis.summary)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .accessibilityIdentifier("gapless-track")
                }
            }

            Section {
                LabeledContent("Status", value: player.status)
                Button("Stop") { player.stop() }
            }
        }
        .navigationTitle(album.name)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard let client = model.client, songs.isEmpty else { return }
            songs = (try? await client.album(id: album.id).songs) ?? []
        }
        .onDisappear { player.stop() }
    }
}
