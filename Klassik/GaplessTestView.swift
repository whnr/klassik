import SwiftUI

/// Finds an album on the server for the gapless comparison.
struct GaplessTestView: View {
    @Environment(AppModel.self) private var model
    @State private var query = ""
    @State private var albums: [Album] = []
    @State private var error: String?

    var body: some View {
        PageList {
            Section {
                ForEach(albums) { album in
                    NavigationLink(value: Page.gaplessAlbum(album.id)) {
                        VStack(alignment: .leading) {
                            Text(album.name)
                                .ink()
                            if let artist = album.artist {
                                Text(artist)
                                    .typeStyle(.subheadline)
                                    .foregroundStyle(Palette.textSecondary)
                            }
                        }
                    }
                    .accessibilityIdentifier("gapless-album")
                }
            } footer: {
                Text(
                    error
                        ?? "Search for a work whose movements run into each other, then listen at each change of track."
                )
            }
        }
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Album")
        .onSubmit(of: .search) {
            Task { await search() }
        }
        .navigationTitle("Gapless Test")
        .miniPlayerInset()
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
    let albumID: String
    @State private var name: String?
    @State private var songs: [Song] = []
    @State private var player = GaplessTestPlayer()
    @State private var kind = GaplessTestPlayer.Kind.audioEngine
    @State private var startNearEnd = true

    var body: some View {
        PageForm {
            Section {
                Picker("Player", selection: $kind) {
                    ForEach(GaplessTestPlayer.Kind.allCases) { Text($0.rawValue).tag($0) }
                }
                Toggle("Start 10 s Before the End", isOn: $startNearEnd)
            } footer: {
                Text(
                    "AVQueuePlayer streams each track. AVAudioEngine downloads each track and cuts encoder delay and padding as the MP3 header specifies."
                )
            }

            Section("Tap a Track to Play from There") {
                ForEach(Array(songs.enumerated()), id: \.element.id) { index, song in
                    Button {
                        guard let client = model.client else { return }
                        player.play(
                            songs, from: index, with: kind, client: client, lastSeconds: startNearEnd ? 10 : nil)
                    } label: {
                        VStack(alignment: .leading) {
                            Text(song.title)
                                .ink()
                            if let analysis = player.analysis[song.id] {
                                Text(analysis.summary)
                                    .typeStyle(.caption1)
                                    .foregroundStyle(Palette.textSecondary)
                            }
                        }
                    }
                    .accessibilityIdentifier("gapless-track")
                }
            }

            Section {
                LabeledContent("Status", value: player.status)
                    .ink()
                Button("Stop") { player.stop() }
            }
        }
        .navigationTitle(name ?? "Album")
        .miniPlayerInset()
        .task {
            guard let client = model.client, songs.isEmpty else { return }
            guard let album = try? await client.album(id: albumID) else { return }
            name = album.name
            songs = album.songs
        }
        .onDisappear { player.stop() }
    }
}
