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
            CoverImage(song: item.recording.songs.first, points: itemSize)
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

/// Local audio supplies embedded artwork before the server. Without artwork, a note stands in.
struct CoverImage: View {
    @Environment(AppModel.self) private var model
    @Environment(\.displayScale) private var scale
    let song: Song?
    let points: CGFloat
    @State private var image: UIImage?

    private struct Source: Equatable {
        var files: [URL]
        var remote: URL?
    }

    private var source: Source {
        guard let song else { return Source(files: [], remote: nil) }
        // Another downloaded movement can hold the album art when the first movement is not on the device.
        let related = model.library.songs.filter {
            $0.id != song.id && ($0.albumKey == song.albumKey || (song.coverArt != nil && $0.coverArt == song.coverArt))
        }
        let files = ([song] + related).filter { model.tracks.isOffline($0) }.compactMap {
            model.tracks.localFile(for: $0)
        }
        let remote = song.coverArt.flatMap {
            model.client?.coverArtURL(id: $0, size: Int((points * scale).rounded(.up)))
        }
        return Source(files: files, remote: remote)
    }

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
        .task(id: source) {
            let source = source
            image = nil
            let loaded = await CoverArt.load(files: source.files, remote: source.remote)
            guard !Task.isCancelled else { return }
            image = loaded
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
