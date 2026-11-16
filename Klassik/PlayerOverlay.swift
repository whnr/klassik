import Observation
import SwiftUI

/// UIKit owns the system chrome; the overlay keeps its content clear without joining a navigation container.
@MainActor @Observable
final class PlayerOverlayLayout {
    var top: CGFloat = 0
    var bottom: CGFloat = 0
}

/// One player above the places and below the native tab bar (ADR 0014).
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
            if let item = model.playback.item { lastItem = item }
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
            .gesture(
                DragGesture()
                    .updating($dragged) { value, state, _ in state = max(0, value.translation.height) }
                    .onEnded { value in
                        if value.translation.height > 120 || value.predictedEndTranslation.height > 240 {
                            navigator.closePlayer()
                        }
                    })
            RecordingView(
                work: item.work, recording: item.recording,
                album: item.recording.albumKey.flatMap { model.library.album($0) }, isOverlay: true
            )
            .id(item.id)
        }
        .padding(.top, layout.top)
        .padding(.bottom, layout.bottom)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.backgroundGrouped.color.ignoresSafeArea())
        .offset(y: dragged)
        .animation(Motion.rise.animation(reduceMotion: reduceMotion), value: dragged == 0)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("player-overlay")
    }
}
