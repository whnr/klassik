import SwiftUI
import UIKit

/// The mini player: a pill at the end of the timeline, in the tab row, flush with the screen edge (ADR 0028). It
/// holds a round play/pause button and the square cover, and no text. The cover opens the page of what plays.
struct MiniPlayer: View {
    @Environment(AppModel.self) private var model
    @Environment(AppNavigator.self) private var navigator
    let side: TimelineSide

    /// The size of the button and the cover, as of the tab items beside them.
    static let item: CGFloat = 48
    /// The corner toward the round screen corner.
    private static let edgeCorner: CGFloat = 12

    var body: some View {
        let player = model.playback
        if let item = player.item {
            let page = Page.recording(work: item.work.id, recording: item.recording.id)
            // On the player page the pill holds only play/pause (ADR 0028).
            let onPlayer = navigator.pages(in: navigator.selection).last == page
            let shape = shape
            HStack(spacing: Space.xs.points) {
                if side == .left, !onPlayer { cover(of: item, page: page) }
                Button(player.isPaused ? "Resume" : "Pause", systemImage: player.isPaused ? "play.fill" : "pause.fill")
                {
                    player.togglePause()
                }
                .labelStyle(.iconOnly)
                .typeStyle(.title3)
                .foregroundStyle(Palette.textPrimary)
                .frame(width: Self.item, height: Self.item)
                .contentShape(.circle)
                .buttonStyle(.borderless)
                .accessibilityIdentifier("mini-player-pause")
                if side == .right, !onPlayer { cover(of: item, page: page) }
            }
            .padding(Space.xs.points)
            // The timeline runs on down the flat face, so the pill reads as its end.
            .padding(side == .right ? .trailing : .leading, Measure.timeline)
            .background {
                Rectangle()
                    .fill(Palette.timelineUnplayed)
                    .frame(width: Measure.timeline)
                    .frame(maxWidth: .infinity, alignment: side == .right ? .trailing : .leading)
                    .clipShape(shape)
            }
            .glassEffect(.regular.interactive(), in: shape)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Mini player")
            .accessibilityIdentifier("mini-player")
        }
    }

    /// Round on the content side, flat on the screen edge.
    private var shape: UnevenRoundedRectangle {
        let round = Self.item / 2 + Space.xs.points
        return side == .right
            ? UnevenRoundedRectangle(
                topLeadingRadius: round, bottomLeadingRadius: round, bottomTrailingRadius: Self.edgeCorner,
                topTrailingRadius: 0)
            : UnevenRoundedRectangle(
                topLeadingRadius: 0, bottomLeadingRadius: Self.edgeCorner, bottomTrailingRadius: round,
                topTrailingRadius: round)
    }

    /// Album art is square, so the cover is square; only play/pause is round.
    private func cover(of item: QueueItem, page: Page) -> some View {
        Button {
            navigator.open(page, in: navigator.selection)
        } label: {
            CoverImage(id: item.recording.songs.first?.coverArt, points: Self.item)
                .frame(width: Self.item, height: Self.item)
                .clipShape(.rect(cornerRadius: Radius.s))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.work.title)
        .accessibilityHint("Opens the page of what plays.")
        .accessibilityIdentifier("mini-player-cover")
    }
}

/// The cover of a song. It loads once for each cover ID; without one, a note stands in.
struct CoverImage: View {
    @Environment(AppModel.self) private var model
    @Environment(\.displayScale) private var scale
    let id: String?
    let points: CGFloat
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Rectangle().fill(Palette.fillQuiet)
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "music.note")
                    .foregroundStyle(Palette.textSecondary)
            }
        }
        .accessibilityHidden(true)
        .task(id: id) {
            image = nil
            guard let id, let client = model.client else { return }
            let url = client.coverArtURL(id: id, size: Int((points * scale).rounded(.up)))
            guard let response = try? await URLSession.shared.data(from: url) else { return }
            image = UIImage(data: response.0)
        }
    }
}
