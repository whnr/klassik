import SwiftUI

/// The bar at the bottom of every screen while a recording plays, as in Apple Music. Tapping it opens the recording.
struct MiniPlayer: View {
    @Environment(AppModel.self) private var model
    @State private var showsRecording = false
    @ScaledMetric(space: .xxs) private var lineGap: CGFloat
    @ScaledMetric(space: .m) private var inset: CGFloat
    @ScaledMetric(space: .l) private var gap: CGFloat
    @ScaledMetric(space: .xl) private var edge: CGFloat

    var body: some View {
        let player = model.playback
        if let work = player.work, let recording = player.recording {
            HStack(spacing: gap) {
                VStack(alignment: .leading, spacing: lineGap) {
                    Text(work.title)
                        .ink()
                        .lineLimit(1)
                    if !work.composer.isEmpty {
                        Text(work.composer)
                            .typeStyle(.subheadline)
                            .foregroundStyle(Palette.textSecondary)
                            .lineLimit(1)
                    }
                    Text(player.movement.map { recording.title(of: recording.songs[$0]) } ?? recording.performers)
                        .typeStyle(.subheadline)
                        .foregroundStyle(Palette.textSecondary)
                        .lineLimit(1)
                }
                Spacer()
                Button(player.isPaused ? "Resume" : "Pause", systemImage: player.isPaused ? "play.fill" : "pause.fill")
                {
                    player.togglePause()
                }
                .labelStyle(.iconOnly)
                .typeStyle(.title3)
                .buttonStyle(.borderless)
                .accessibilityIdentifier("mini-player-pause")
            }
            .padding(.horizontal, edge)
            .padding(.vertical, inset)
            .contentShape(.rect)
            .onTapGesture { showsRecording = true }
            .glassEffect(in: .capsule)
            .padding(.horizontal)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("mini-player")
            .sheet(isPresented: $showsRecording) {
                NavigationStack {
                    NowPlayingView()
                        .toolbar {
                            Button("Done", systemImage: "chevron.down") { showsRecording = false }
                        }
                }
            }
        }
    }
}

extension View {
    /// Shows the mini player below the screen's content. Each screen needs its own inset:
    /// an inset on the NavigationStack does not move the last rows of a pushed List above the mini player.
    func miniPlayerInset() -> some View {
        safeAreaInset(edge: .bottom) { MiniPlayer() }
    }
}

/// The recording that plays now. It follows the player when the queue moves on.
private struct NowPlayingView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let work = model.playback.work, let recording = model.playback.recording {
            RecordingView(work: work, recording: recording)
                .id(recording.id)
        } else {
            ContentUnavailableView("Nothing Playing", systemImage: "music.note")
        }
    }
}
