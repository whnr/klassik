import SwiftUI
import UIKit

/// The mini player: a pill at the end of the timeline, in the tab row, flush with the screen edge (ADR 0028). It
/// holds a round play/pause button and the square cover, and no text. The cover opens the player overlay.
struct MiniPlayer: View {
    @Environment(AppModel.self) private var model
    @Environment(AppNavigator.self) private var navigator
    let side: TimelineSide
    let height: CGFloat
    let edgeInset: CGFloat

    /// The size of the button and the cover, as of the tab items beside them.
    nonisolated static let item: CGFloat = 48
    private var itemSize: CGFloat { Self.itemSize(height: height) }

    var body: some View {
        let player = model.playback
        if let item = player.item {
            let edge: Edge.Set = side == .right ? .trailing : .leading
            let content: Edge.Set = side == .right ? .leading : .trailing
            HStack(spacing: Space.xs.points) {
                if side == .left { cover(of: item, edge: edge) }
                Button {
                    player.togglePause()
                } label: {
                    Image(systemName: player.isPaused ? "play.fill" : "pause.fill")
                        .typeStyle(.title3)
                        .foregroundStyle(Palette.textPrimary)
                        .frame(width: itemSize, height: itemSize)
                        .padding(.vertical, max(0, (height - itemSize) / 2))
                        .padding(content, Space.xs.points)
                        .contentShape(.rect)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(player.isPaused ? "Resume" : "Pause")
                .accessibilityIdentifier("mini-player-pause")
                if side == .right { cover(of: item, edge: edge) }
            }
            .glassEffect(.regular.interactive(), in: shape)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Mini player")
            .accessibilityIdentifier("mini-player")
        }
    }

    nonisolated static func width(height: CGFloat, edgeInset: CGFloat) -> CGFloat {
        2 * itemSize(height: height) + 2 * Space.xs.points + edgeInset
    }

    nonisolated private static func itemSize(height: CGFloat) -> CGFloat {
        min(item, max(Measure.hitTarget, height - 2 * Space.xs.points))
    }

    /// The square cover clears the display bend with the same gap as the straight edge.
    nonisolated static func coverInset(radius: CGFloat, bottom: CGFloat) -> CGFloat {
        let below = max(0, radius - bottom - Space.xs.points)
        let bend = radius - sqrt(max(0, radius * radius - below * below))
        return Measure.timeline + Space.xs.points + bend
    }

    private var shape: ConcentricRectangle {
        let round = height / 2
        return side == .right
            ? ConcentricRectangle(
                topLeadingCorner: .fixed(round), topTrailingCorner: .fixed(0),
                bottomLeadingCorner: .fixed(round), bottomTrailingCorner: .concentric)
            : ConcentricRectangle(
                topLeadingCorner: .fixed(0), topTrailingCorner: .fixed(round),
                bottomLeadingCorner: .concentric, bottomTrailingCorner: .fixed(round))
    }

    /// Album art is square, so the cover is square; only play/pause is round.
    private func cover(of item: QueueItem, edge: Edge.Set) -> some View {
        Button {
            navigator.openPlayer()
        } label: {
            CoverImage(id: item.recording.songs.first?.coverArt, points: itemSize)
                .frame(width: itemSize, height: itemSize)
                .clipShape(.rect(cornerRadius: Radius.s))
                .padding(.vertical, max(0, (height - itemSize) / 2))
                .padding(edge, edgeInset)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.work.title)
        .accessibilityHint("Opens the player overlay.")
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
        .task(id: id) {
            image = nil
            guard let id, let client = model.client else { return }
            let url = client.coverArtURL(id: id, size: Int((points * scale).rounded(.up)))
            guard let response = try? await URLSession.shared.data(from: url) else { return }
            image = UIImage(data: response.0)
        }
    }
}

/// The bump follows the display corner. Two system-resolved contours keep the strip eight points wide.
private struct DisplayCornerStrip: Shape {
    let outer: Path
    let inner: Path

    func path(in rect: CGRect) -> Path {
        var path = outer
        path.addPath(inner)
        return path
    }
}

struct MiniPlayerCorner: View {
    let side: TimelineSide
    let top: CGFloat

    var body: some View {
        GeometryReader { geometry in
            let bounds = CGRect(origin: .zero, size: geometry.size)
            let inset = bounds.insetBy(dx: Measure.timeline, dy: Measure.timeline)
            if let outer = geometry.concentricCornerRadii,
                let inner = geometry.concentricCornerRadii(in: inset)
            {
                let radius = side == .right ? outer.bottomTrailing : outer.bottomLeading
                DisplayCornerStrip(
                    outer: Path(roundedRect: bounds, cornerRadii: outer, style: .continuous),
                    inner: Path(roundedRect: inset, cornerRadii: inner, style: .continuous)
                )
                .fill(Palette.timelineUnplayed, style: FillStyle(eoFill: true))
                .mask(alignment: side == .right ? .bottomTrailing : .bottomLeading) {
                    Rectangle().frame(width: max(radius, Measure.timeline), height: max(0, bounds.height - top))
                }
            }
        }
        .accessibilityHidden(true)
    }
}
