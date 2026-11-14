import SwiftUI
import UIKit

/// The mini player: a pill at the end of the timeline, in the tab row, flush with the screen edge (ADR 0028). It
/// holds a round play/pause button and the square cover, and no text. The cover opens the page of what plays.
struct MiniPlayer: View {
    @Environment(AppModel.self) private var model
    @Environment(AppNavigator.self) private var navigator
    let side: TimelineSide
    let bottom: CGFloat

    /// The size of the button and the cover, as of the tab items beside them.
    nonisolated static let item: CGFloat = 48

    var body: some View {
        let player = model.playback
        if let item = player.item {
            let page = Page.recording(work: item.work.id, recording: item.recording.id)
            // On the player page the pill holds only play/pause (ADR 0028).
            let onPlayer = navigator.pages(in: navigator.selection).last == page
            let edge: Edge.Set = side == .right ? .trailing : .leading
            let content: Edge.Set = side == .right ? .leading : .trailing
            HStack(spacing: Space.xs.points) {
                if side == .left, !onPlayer { cover(of: item, page: page, edge: edge) }
                Button {
                    player.togglePause()
                } label: {
                    Image(systemName: player.isPaused ? "play.fill" : "pause.fill")
                        .typeStyle(.title3)
                        .foregroundStyle(Palette.textPrimary)
                        .frame(width: Self.item, height: Self.item)
                        .padding(.vertical, Space.xs.points)
                        .padding(content, Space.xs.points)
                        .padding(edge, onPlayer ? Self.edgeInset : 0)
                        .contentShape(.rect)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(player.isPaused ? "Resume" : "Pause")
                .accessibilityIdentifier("mini-player-pause")
                if side == .right, !onPlayer { cover(of: item, page: page, edge: edge) }
            }
            .background(alignment: .top) {
                Color.clear
                    .frame(height: TabRow.height + bottom)
                    .glassEffect(.regular.interactive(), in: shape(onPlayer: onPlayer))
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Mini player")
            .accessibilityIdentifier("mini-player")
        }
    }

    nonisolated static func width(onPlayer: Bool) -> CGFloat {
        onPlayer ? item + Space.xs.points + edgeInset : 2 * item + 2 * Space.xs.points + edgeInset
    }

    /// The padding on the screen edge: the timeline strip and a gap. The button at the edge takes it into its
    /// own frame, so a tap at the screen edge still hits it.
    nonisolated private static let edgeInset = Space.xs.points + Measure.timeline

    /// Round on the content side, flat on the screen edge.
    private func shape(onPlayer: Bool) -> ConcentricRectangle {
        let round = Self.item / 2 + Space.xs.points
        return side == .right
            ? ConcentricRectangle(
                topLeadingCorner: .fixed(round), topTrailingCorner: .fixed(0),
                bottomLeadingCorner: .fixed(onPlayer ? 0 : round), bottomTrailingCorner: .concentric)
            : ConcentricRectangle(
                topLeadingCorner: .fixed(0), topTrailingCorner: .fixed(round),
                bottomLeadingCorner: .concentric, bottomTrailingCorner: .fixed(onPlayer ? 0 : round))
    }

    /// Album art is square, so the cover is square; only play/pause is round.
    private func cover(of item: QueueItem, page: Page, edge: Edge.Set) -> some View {
        Button {
            navigator.open(page, in: navigator.selection)
        } label: {
            CoverImage(id: item.recording.songs.first?.coverArt, points: Self.item)
                .frame(width: Self.item, height: Self.item)
                .clipShape(.rect(cornerRadius: Radius.s))
                .padding(.vertical, Space.xs.points)
                .padding(edge, Self.edgeInset)
                .contentShape(.rect)
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
