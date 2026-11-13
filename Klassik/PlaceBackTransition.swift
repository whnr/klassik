import SwiftUI
import UIKit

/// A tab switch has no system pop transition. The outgoing page slides away while each tab keeps its stack.
@MainActor
final class PlaceBackTransition {
    weak var surface: UIView?
    private var isRunning = false

    func perform(reduceMotion: Bool, bottom: CGFloat, action: () -> Void) {
        guard !isRunning else { return }
        guard let window = surface?.window else {
            action()
            return
        }
        var rect = window.bounds.inset(by: window.safeAreaInsets).insetBy(dx: Measure.timeline, dy: 0)
        rect.size.height = max(0, rect.height - bottom)
        guard let snapshot = window.resizableSnapshotView(from: rect, afterScreenUpdates: false, withCapInsets: .zero)
        else {
            action()
            return
        }
        let overlay = UIView(frame: rect)
        overlay.clipsToBounds = true
        overlay.accessibilityElementsHidden = true
        snapshot.frame = overlay.bounds
        overlay.addSubview(snapshot)
        window.addSubview(overlay)
        let width = rect.width
        isRunning = true
        action()
        UIView.animate(
            withDuration: reduceMotion ? 0.15 : 0.25, delay: 0, options: .curveEaseInOut,
            animations: {
                if reduceMotion {
                    snapshot.alpha = 0
                } else {
                    snapshot.transform = CGAffineTransform(translationX: width, y: 0)
                }
            },
            completion: { _ in
                overlay.removeFromSuperview()
                self.isRunning = false
            })
    }
}

/// The window supplies the rendered page, including the scroll position, without rebuilding its SwiftUI stack.
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
