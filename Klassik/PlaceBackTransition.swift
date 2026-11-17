import SwiftUI
import UIKit

/// Tabs keep their stacks, so cancelling a cross-tab drag must restore the origin as well as the selection.
@MainActor
final class PlaceBackTransition {
    weak var surface: UIView?
    private(set) var isRunning = false
    private var overlay: UIView?
    private var snapshot: UIView?
    private var undo: (() -> Void)?
    private var distance: CGFloat = 0
    private var width: CGFloat = 0
    var onCompletion: (() -> Void)?

    func begin(bottom: CGFloat, action: () -> (() -> Void)) -> Bool {
        guard !isRunning, let window = surface?.window else { return false }
        var rect = window.bounds.inset(by: window.safeAreaInsets).insetBy(dx: Measure.timeline, dy: 0)
        rect.size.height = max(0, window.bounds.maxY - bottom - rect.minY)
        guard let snapshot = window.resizableSnapshotView(from: rect, afterScreenUpdates: false, withCapInsets: .zero)
        else { return false }
        let overlay = UIView(frame: rect)
        overlay.clipsToBounds = true
        overlay.accessibilityElementsHidden = true
        snapshot.frame = overlay.bounds
        overlay.addSubview(snapshot)
        window.addSubview(overlay)
        self.overlay = overlay
        self.snapshot = snapshot
        width = rect.width
        distance = 0
        isRunning = true
        withoutAnimation { undo = action() }
        return true
    }

    func update(distance: CGFloat) {
        guard isRunning else { return }
        self.distance = min(width, max(0, distance))
        snapshot?.transform = CGAffineTransform(translationX: self.distance, y: 0)
    }

    func finish(velocity: CGFloat, cancelled: Bool, reduceMotion: Bool) {
        guard isRunning else { return }
        let completes = !cancelled && distance + velocity * 0.2 > width / 2
        UIView.animate(
            withDuration: reduceMotion ? 0.15 : 0.25, delay: 0, options: [.curveEaseOut, .beginFromCurrentState],
            animations: {
                if reduceMotion && completes {
                    self.snapshot?.alpha = 0
                } else {
                    self.snapshot?.transform = CGAffineTransform(translationX: completes ? self.width : 0, y: 0)
                }
            },
            completion: { _ in
                if !completes { self.withoutAnimation { self.undo?() } }
                // SwiftUI must restore the selected tab before the snapshot leaves the window.
                DispatchQueue.main.async {
                    self.overlay?.removeFromSuperview()
                    self.overlay = nil
                    self.snapshot = nil
                    self.undo = nil
                    self.isRunning = false
                    self.onCompletion?()
                }
            })
    }

    func perform(reduceMotion: Bool, bottom: CGFloat, action: () -> Void) {
        if begin(
            bottom: bottom,
            action: {
                action()
                return {}
            })
        {
            update(distance: width)
            snapshot?.transform = .identity
            finish(velocity: 0, cancelled: false, reduceMotion: reduceMotion)
        } else if !isRunning {
            action()
        }
    }

    private func withoutAnimation(_ action: () -> Void) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction, action)
    }
}

/// The window supplies the rendered page, including its scroll position, without rebuilding its SwiftUI stack.
struct PlaceBackSurface: UIViewRepresentable {
    let transition: PlaceBackTransition

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isUserInteractionEnabled = false
        transition.surface = view
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {}
}
