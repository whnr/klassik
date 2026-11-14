import SwiftUI

/// The timeline on the screen edge while something plays (ADR 0014, 0035), and its scrub label. `TimelineBar` holds
/// the geometry and `TimelineTouch` decides what a touch does; this view draws and forwards.
struct TimelineBarView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppNavigator.self) private var navigator
    let side: TimelineSide
    @State private var touch = TimelineTouch.undecided
    /// The start of the touch that `touch` belongs to. The system can cancel a drag without `onEnded`, so a new
    /// start point begins a new touch.
    @State private var touchStart: CGPoint?
    /// True while a finger is down. It turns false on a cancel too, which takes the scrub label away.
    @GestureState private var isTouching = false
    /// The place under the finger while it scrubs. The bar draws it, and the music moves there when the finger
    /// lifts, so the movement does not restart for every step of the drag.
    @State private var scrubbed: TimelineBar.Place?
    @State private var finger = 0.0
    @State private var labelHeight = 0.0

    /// The width that takes a touch. It stays clear of the toolbar buttons and the row content, which start
    /// `Space.l` from the edge.
    static let touchWidth = Measure.timeline + Space.m.points

    var body: some View {
        let player = model.playback
        GeometryReader { proxy in
            let bar = TimelineBar(durations: player.segments, height: proxy.size.height, gap: Space.xxs.points)
            let shown = scrubbed ?? player.movement.map { TimelineBar.Place(movement: $0, seconds: player.position) }
            let played = shown.map { bar.played(movement: $0.movement, position: $0.seconds) } ?? []
            ZStack(alignment: side == .right ? .topTrailing : .topLeading) {
                if let scrubbed {
                    label(scrubbed)
                        .frame(maxWidth: proxy.size.width * 0.7, alignment: side == .right ? .trailing : .leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .onGeometryChange(for: Double.self) {
                            Double($0.size.height)
                        } action: {
                            labelHeight = $0
                        }
                        .offset(
                            y: TimelineBar.labelCentre(
                                finger: finger, labelHeight: labelHeight, top: 0,
                                floor: proxy.size.height - Space.s.points) - labelHeight / 2
                        )
                        .padding(side == .right ? .trailing : .leading, Measure.hitTarget + Space.xs.points)
                        .allowsHitTesting(false)
                }
                segments(of: bar, played: played)
                    .frame(width: Self.touchWidth, height: proxy.size.height, alignment: alignment)
                    .contentShape(.rect)
                    .gesture(drag(on: bar))
                    .onChange(of: isTouching) { _, touching in
                        if !touching { scrubbed = nil }
                    }
                    .onChange(of: scrubbed != nil) { _, scrubbing in
                        model.isScrubbingTimeline = scrubbing
                    }
                    .accessibilityElement()
                    .accessibilityLabel("Timeline")
                    .accessibilityValue(accessibilityValue)
                    .accessibilityHint("Swipe up or down to play the next or the previous movement.")
                    .accessibilityAdjustableAction(adjust)
                    .accessibilityIdentifier("timeline")
            }
            .coordinateSpace(name: "timeline")
            .frame(
                width: proxy.size.width, height: proxy.size.height,
                alignment: side == .right ? .topTrailing : .topLeading)
        }
    }

    private var alignment: Alignment { side == .right ? .trailing : .leading }

    private func segments(of bar: TimelineBar, played: [Double]) -> some View {
        ZStack(alignment: .top) {
            ForEach(bar.segments.indices, id: \.self) { index in
                let segment = bar.segments[index]
                let shape = shape(first: index == 0)
                shape.fill(Palette.timelineUnplayed)
                    .overlay(alignment: .top) {
                        Rectangle()
                            .fill(Palette.timelinePlayed)
                            .frame(height: segment.height * (played.indices.contains(index) ? played[index] : 0))
                    }
                    .clipShape(shape)
                    .frame(height: segment.height)
                    .offset(y: segment.top)
            }
        }
        .frame(width: Measure.timeline)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    /// Flush with the screen edge, round on the content side. The first segment grows out of the edge (ADR 0035).
    private func shape(first: Bool) -> UnevenRoundedRectangle {
        let top = first ? Measure.timelineCap : Radius.xs
        return side == .right
            ? UnevenRoundedRectangle(
                topLeadingRadius: top, bottomLeadingRadius: Radius.xs, bottomTrailingRadius: 0, topTrailingRadius: 0)
            : UnevenRoundedRectangle(
                topLeadingRadius: 0, bottomLeadingRadius: 0, bottomTrailingRadius: Radius.xs, topTrailingRadius: top)
    }

    /// Two lines: the movement, then the time. No separator (ADR 0031).
    private func label(_ place: TimelineBar.Place) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title(of: place.movement))
                .foregroundStyle(Palette.textPrimary)
            Text(PlaybackProgress.time(place.seconds))
                .foregroundStyle(Palette.textSecondary)
        }
        .typeStyle(.footnote)
        .padding(.vertical, Space.xs.points)
        .padding(.horizontal, Space.s.points)
        .background(Palette.backgroundElevated, in: .rect(cornerRadius: Radius.s))
        .shadow(radius: 5, y: 2)
        .accessibilityHidden(true)
    }

    private func drag(on bar: TimelineBar) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named("timeline"))
            .updating($isTouching) { _, state, _ in state = true }
            .onChanged { value in
                if value.startLocation != touchStart {
                    touchStart = value.startLocation
                    touch = .undecided
                    scrubbed = nil
                }
                touch = touch.moved(dx: value.translation.width, dy: value.translation.height)
                if touch == .scrub {
                    finger = value.location.y
                    scrubbed = bar.place(at: value.location.y)
                }
            }
            .onEnded { value in
                let action = touch.moved(dx: value.translation.width, dy: value.translation.height)
                    .end(dx: value.translation.width, side: side, at: bar.place(at: value.location.y))
                touch = .undecided
                touchStart = nil
                perform(action)
                scrubbed = nil
            }
    }

    private func perform(_ action: TimelineTouch.Action) {
        let player = model.playback
        switch action {
        case .nothing: break
        case .play(let movement): play(movement)
        case .seek(let place): player.seek(movement: place.movement, to: place.seconds)
        case .back: navigator.back()
        }
    }

    private func play(_ movement: Int) {
        let player = model.playback
        guard let item = player.item, item.recording.songs.indices.contains(movement) else { return }
        player.play(item, from: movement)
    }

    /// VoiceOver moves by whole movements, as a tap does.
    private func adjust(_ direction: AccessibilityAdjustmentDirection) {
        guard let movement = model.playback.movement else { return }
        switch direction {
        case .increment: play(movement + 1)
        case .decrement: play(movement - 1)
        @unknown default: break
        }
    }

    private func title(of movement: Int) -> String {
        guard let recording = model.playback.recording, recording.songs.indices.contains(movement) else { return "" }
        return recording.title(of: recording.songs[movement])
    }

    private var accessibilityValue: String {
        let player = model.playback
        guard let movement = player.movement, let recording = player.recording else { return "" }
        return "Movement \(movement + 1) of \(recording.songs.count), \(title(of: movement)), "
            + PlaybackProgress.time(player.position)
    }
}
