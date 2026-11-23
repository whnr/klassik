import Observation
import SwiftUI
import UIKit

/// UIKit owns the system chrome; the overlay keeps its content clear without joining a navigation container.
@MainActor @Observable
final class PlayerOverlayLayout {
    var top: CGFloat = 0
    var bottom: CGFloat = 0
}

/// The drag that closes the player. The handle and the heading of the player (cover and title) take it, so the player
/// follows the finger and shows the page below, as the works sheet of Chronology does. Rows below the heading scroll.
@MainActor struct PlayerCloseDrag {
    /// How far the finger has pulled the player down. It returns to zero when the finger lifts.
    let pulled: GestureState<CGFloat>
    /// Where the player stays when a drag closes it, so it leaves from there and does not jump back.
    let leave: (CGFloat) -> Void
    let close: () -> Void
    /// The pull of a drag that started on the hero, which UIKit tracks and SwiftUI cannot reset by itself.
    let heroPull: Binding<CGFloat>

    /// A pull this far closes the player on release.
    private static let closingPull: CGFloat = 120
    /// A fling that would carry the player this far closes it.
    private static let closingFling: CGFloat = 240

    var gesture: some Gesture {
        DragGesture()
            .updating(pulled) { value, state, _ in state = max(0, value.translation.height) }
            .onEnded { value in
                release(pull: value.translation.height, predicted: value.predictedEndTranslation.height)
            }
    }

    /// The drag from the hero. It begins only for a downward move, so an upward drag reaches the page scroll.
    var heroGesture: some UIGestureRecognizerRepresentable { HeroDrag(drag: self) }

    fileprivate func release(pull: CGFloat, predicted: CGFloat) {
        guard pull > Self.closingPull || predicted > Self.closingFling, pull > 0 else { return }
        leave(pull)
        close()
    }

    /// DragGesture cannot refuse a drag once it has started, and a high-priority one then takes the page scroll.
    private struct HeroDrag: UIGestureRecognizerRepresentable {
        let drag: PlayerCloseDrag

        /// The distance a fling carries the player, as the seconds of travel that SwiftUI predicts for its drag.
        private static let flingSeconds: CGFloat = 0.25

        final class Coordinator: NSObject, UIGestureRecognizerDelegate {
            func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
                guard let pan = recognizer as? UIPanGestureRecognizer else { return false }
                // Velocity is an estimate that can be zero or jitter at the first callback, and a refusal
                // fails the recognizer for the whole touch. Translation is the settled distance; velocity
                // only decides while the translation is still zero. The page scroll pan is not made
                // simultaneous: UIKit lets this pan win by failing the scroll only when it begins first.
                let move = pan.translation(in: pan.view)
                if move != .zero { return move.y > 0 && abs(move.y) > abs(move.x) }
                let velocity = pan.velocity(in: pan.view)
                return velocity.y > 0 && abs(velocity.y) > abs(velocity.x)
            }
        }

        func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator { Coordinator() }

        func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
            let pan = UIPanGestureRecognizer()
            pan.delegate = context.coordinator
            return pan
        }

        func handleUIGestureRecognizerAction(_ pan: UIPanGestureRecognizer, context: Context) {
            let pull = pan.translation(in: pan.view).y
            switch pan.state {
            case .changed:
                drag.heroPull.wrappedValue = max(0, pull)
            case .ended:
                let predicted = pull + pan.velocity(in: pan.view).y * Self.flingSeconds
                drag.heroPull.wrappedValue = 0
                drag.release(pull: pull, predicted: predicted)
            case .cancelled, .failed:
                drag.heroPull.wrappedValue = 0
            default:
                break
            }
        }
    }
}

/// One player above the places and below the native tab bar.
struct PlayerOverlayLayer: View {
    @Environment(AppModel.self) private var model
    @Environment(AppNavigator.self) private var navigator
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var lastItem: QueueItem?

    var body: some View {
        ZStack {
            if navigator.isPlayerOpen, let item = model.playback.item ?? lastItem {
                PlayerOverlay(item: item)
                    .transition(reduceMotion ? .opacity : .move(edge: .bottom))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea(.container)
        .animation(Motion.rise.animation(reduceMotion: reduceMotion), value: navigator.isPlayerOpen)
        .onChange(of: model.playback.item?.id, initial: true) { _, _ in
            // The last item stays in the overlay while it slides away.
            if let item = model.playback.item { lastItem = item }
            navigator.playbackChanged(hasItem: model.playback.item != nil)
        }
    }
}

private struct PlayerOverlay: View {
    @Environment(AppModel.self) private var model
    @Environment(AppNavigator.self) private var navigator
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(PlayerOverlayLayout.self) private var layout
    let item: QueueItem
    @GestureState private var dragged: CGFloat = 0
    @State private var heroPulled: CGFloat = 0
    /// The pull that closed the player. The slide out starts from it.
    @State private var leaving: CGFloat = 0

    /// The specimen's rise: the old content leaves upwards, the next one comes from below.
    private static let rise = AnyTransition.asymmetric(
        insertion: .offset(y: Layout.riseIn).combined(with: .opacity),
        removal: .offset(y: -Layout.riseOut).combined(with: .opacity))

    private var pulled: CGFloat { dragged + heroPulled }

    private var closeDrag: PlayerCloseDrag {
        PlayerCloseDrag(
            pulled: $dragged, leave: { leaving = $0 }, close: { navigator.closePlayer() }, heroPull: $heroPulled)
    }

    var body: some View {
        VStack(spacing: 0) {
            Button {
                navigator.closePlayer()
            } label: {
                Capsule()
                    .fill(Palette.textTertiary)
                    .frame(width: Layout.grabberWidth, height: Layout.grabberHeight)
                    .frame(maxWidth: .infinity)
                    .frame(height: Measure.hitTarget)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close the player")
            .accessibilityIdentifier("player-handle")
            .gesture(closeDrag.gesture)
            .overlay(alignment: .trailing) {
                // specimen menu.html, Player: the menu of what plays has the download and the tags, no queue items.
                PageMenuButton(
                    target: PageMenuTarget(
                        kind: .player, item: item, album: item.recording.albumKey.flatMap { model.library.album($0) })
                )
                .labelStyle(.iconOnly)
                .frame(width: Measure.hitTarget, height: Measure.hitTarget)
                .padding(.trailing, Layout.edge - Space.s.points)
            }
            ZStack {
                // When an item ends, its content leaves upwards and the next item rises in its place.
                RecordingView(
                    work: item.work, recording: item.recording,
                    album: item.recording.albumKey.flatMap { model.library.album($0) }, isOverlay: true,
                    closeDrag: closeDrag
                )
                .environment(\.washOwner, item.id)
                .id(item.id)
                .transition(reduceMotion ? .opacity : Self.rise)
            }
            .animation(Motion.rise.animation(reduceMotion: reduceMotion), value: item.id)
        }
        .padding(.top, layout.top)
        .padding(.bottom, layout.bottom)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background { PlayerGround() }
        .coverWash(
            item: item.id,
            song: model.playback.item?.id == item.id ? model.playback.coverSong : item.recording.songs.first,
            isPlaying: model.playback.item?.id == item.id
        )
        .offset(y: pulled + leaving)
        // The spring runs only when the finger lifts, so the player follows the finger without lag.
        .animation(pulled == 0 ? Motion.rise.animation(reduceMotion: reduceMotion) : nil, value: pulled)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("player-overlay")
    }
}
