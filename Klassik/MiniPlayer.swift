import SwiftUI
import UIKit

/// The mini player: a pill at the end of the timeline, in the tab row, flush with the screen edge. It
/// holds a round play/pause button and the square cover, and no text. The cover opens the player overlay.
struct MiniPlayer: View {
    @Environment(AppModel.self) private var model
    @Environment(AppNavigator.self) private var navigator
    let side: TimelineSide
    let height: CGFloat
    let edgeInset: CGFloat

    /// The size of the button and the cover, as of the tab items beside them.
    nonisolated static let item = Layout.pillItem
    private var itemSize: CGFloat { Self.itemSize(height: height) }

    var body: some View {
        let player = model.playback
        if let item = player.item {
            let edge: Edge.Set = side == .right ? .trailing : .leading
            let content: Edge.Set = side == .right ? .leading : .trailing
            HStack(spacing: Layout.pillGap) {
                if side == .left { cover(of: item, edge: edge) }
                Button {
                    player.togglePause()
                } label: {
                    Image(systemName: player.isPaused ? "play.fill" : "pause.fill")
                        .typeStyle(.title3)
                        .foregroundStyle(Palette.textPrimary)
                        .frame(width: itemSize, height: itemSize)
                        .padding(.vertical, max(0, (height - itemSize) / 2))
                        .padding(content, Layout.pillPadding)
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
    nonisolated static func coverInset(in geometry: GeometryProxy, side: TimelineSide, bottom: CGFloat, height: CGFloat)
        -> CGFloat
    {
        let gap = Measure.timeline + Space.xs.points
        let bounds = CGRect(origin: .zero, size: geometry.size).insetBy(dx: gap, dy: gap)
        guard let corners = geometry.concentricCornerRadii(in: bounds) else { return gap }
        let contour = Path(roundedRect: bounds, cornerRadii: corners, style: .continuous)
        let padding = max(0, (height - itemSize(height: height)) / 2)
        let y = geometry.size.height - bottom - padding
        // An empty contour row has no edge to find; it must not consume the tab bar's width.
        guard contour.contains(CGPoint(x: geometry.size.width / 2, y: y)) else { return gap }
        var low = gap
        var high = geometry.size.width / 2
        for _ in 0..<16 {
            let inset = (low + high) / 2
            let point = CGPoint(x: side == .right ? geometry.size.width - inset : inset, y: y)
            if contour.contains(point) { high = inset } else { low = inset }
        }
        return high.rounded(.up)
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
            CoverImage(song: model.playback.coverSong, points: itemSize, playback: true)
                .frame(width: itemSize, height: itemSize)
                .clipShape(.rect(cornerRadius: Layout.pillCoverCorner))
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

/// A cover slot of a fixed size. It shows the kept file at once, else a fixed placeholder, and asks for a missing
/// cover. A cover that arrives replaces the placeholder or the older cover in place, so the layout never moves
/// (ADR 0059).
struct CoverImage: View {
    @Environment(AppModel.self) private var model
    @Environment(\.displayScale) private var scale
    let song: Song?
    let points: CGFloat
    /// The cover of what plays loads in Low Data Mode too.
    var playback = false
    @State private var shown: Shown?

    private struct Shown {
        var slot: String
        var image: UIImage
    }

    private struct Load: Equatable {
        var slot: String
        var candidates: [String]
        var arrival: Int
        var pixels: Int
    }

    var body: some View {
        let pixels = Int((points * scale).rounded(.up))
        let covers = model.albumCovers
        let load = song.map {
            Load(
                slot: $0.id, candidates: covers.candidates(for: $0), arrival: covers.arrival(for: $0), pixels: pixels)
        }
        let cached = load?.candidates.first.flatMap { model.covers.image(hash: $0, pixels: pixels) }
        let visible = cached ?? ((playback || shown?.slot == song?.id) ? shown?.image : nil)
        // The slot is square wherever the cover shows. The image sits in an overlay, so it never sizes the slot.
        Rectangle()
            .fill(Palette.fillQuiet)
            .overlay {
                if let visible {
                    Image(uiImage: visible)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: "music.note")
                        .foregroundStyle(Palette.textSecondary)
                }
            }
            .aspectRatio(1, contentMode: .fit)
            .clipped()
            .task(id: load) { await show(load) }
    }

    /// The best kept file shows. Without one, the cover goes to the front of the queue, and its arrival starts
    /// this task again.
    private func show(_ load: Load?) async {
        guard let load, let song else { return }
        for hash in load.candidates {
            if let image = model.covers.image(hash: hash, pixels: load.pixels) {
                shown = Shown(slot: load.slot, image: image)
                return
            }
            if let data = await model.albumArt.data(named: hash),
                let image = await CoverArt.square(data, to: load.pixels)
            {
                guard !Task.isCancelled else { return }
                model.covers.store(image, hash: hash, pixels: load.pixels)
                shown = Shown(slot: load.slot, image: image)
                return
            }
            guard !Task.isCancelled else { return }
        }
        model.albumCovers.request(song, playback: playback)
    }
}
