import SwiftUI

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
    let item: QueueItem
    @GestureState private var dragged: CGFloat = 0

    var body: some View {
        NavigationStack(
            path: Binding<[Page]>(
                get: { [] },
                set: { pages in
                    guard let page = pages.first else { return }
                    navigator.open(page, in: navigator.selection)
                    navigator.closePlayer()
                })
        ) {
            VStack(spacing: 0) {
                Button {
                    navigator.closePlayer()
                } label: {
                    Capsule()
                        .fill(Palette.textTertiary)
                        .frame(width: 36, height: 5)
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
                if model.playback.item == nil {
                    Text(model.playback.queueEnded ? "The queue has ended" : "Playback stopped")
                        .foregroundStyle(Palette.textSecondary)
                        .accessibilityIdentifier("player-ended")
                }
                RecordingView(
                    work: item.work, recording: item.recording,
                    album: item.recording.albumKey.flatMap { model.library.album($0) }, isOverlay: true
                )
                .id(item.id)
            }
            .background(Palette.backgroundGrouped)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Page.self) { _ in Color.clear }
        }
        .background(Palette.backgroundGrouped.color.ignoresSafeArea())
        .offset(y: dragged)
        .animation(Motion.rise.animation(reduceMotion: reduceMotion), value: dragged == 0)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("player-overlay")
    }
}
