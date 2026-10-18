import SwiftUI

/// The bar at the bottom of every screen while a recording plays, as in Apple Music. Tapping it opens the recording.
struct MiniPlayer: View {
    @Environment(AppModel.self) private var model
    @State private var showsRecording = false

    var body: some View {
        let player = model.player
        if let work = player.work, let recording = player.recording {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(work.title)
                        .lineLimit(1)
                    Text(player.current.map { recording.songs[$0].movementTitle } ?? recording.performers)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Button(player.isPaused ? "Resume" : "Pause", systemImage: player.isPaused ? "play.fill" : "pause.fill") {
                    player.togglePause()
                }
                .labelStyle(.iconOnly)
                .font(.title3)
                .buttonStyle(.borderless)
                .accessibilityIdentifier("mini-player-pause")
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .contentShape(.rect)
            .onTapGesture { showsRecording = true }
            .glassEffect(in: .capsule)
            .padding(.horizontal)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("mini-player")
            .sheet(isPresented: $showsRecording) {
                NavigationStack {
                    RecordingView(work: work, recording: recording)
                        .toolbar {
                            Button("Done", systemImage: "chevron.down") { showsRecording = false }
                        }
                }
            }
        }
    }
}
