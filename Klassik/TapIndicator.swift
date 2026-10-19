import UIKit

/// Draws a circle at each touch, so that a screen recording shows where the user taps.
/// iOS screen recordings show no touches, and iOS has no setting that shows them.
@MainActor
final class TapIndicator {
    static let shared = TapIndicator()
    static let storageKey = "showTaps"

    private var overlay: UIWindow?
    private var observer: NSObjectProtocol?
    private var markers: [ObjectIdentifier: UIView] = [:]

    func setEnabled(_ enabled: Bool) {
        if enabled { start() } else { stop() }
    }

    private func start() {
        guard overlay == nil,
            let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first
        else { return }
        // A window without user interaction lets every touch through to the windows below it.
        let window = UIWindow(windowScene: scene)
        window.windowLevel = .alert + 1
        window.isUserInteractionEnabled = false
        window.backgroundColor = .clear
        window.isHidden = false
        overlay = window
        scene.windows.forEach(watch)
        // Menus and sheets can open their own windows.
        observer = NotificationCenter.default.addObserver(
            forName: UIWindow.didBecomeVisibleNotification, object: nil, queue: .main
        ) { note in
            MainActor.assumeIsolated {
                if let window = note.object as? UIWindow { TapIndicator.shared.watch(window) }
            }
        }
    }

    private func stop() {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        for window in overlay?.windowScene?.windows ?? [] {
            window.gestureRecognizers?.filter { $0 is TouchObserver }.forEach(window.removeGestureRecognizer)
        }
        markers.values.forEach { $0.removeFromSuperview() }
        markers = [:]
        overlay?.isHidden = true
        overlay = nil
    }

    private func watch(_ window: UIWindow) {
        let watched = (window.gestureRecognizers ?? []).contains { $0 is TouchObserver }
        guard window !== overlay, !watched else { return }
        window.addGestureRecognizer(TouchObserver(indicator: self))
    }

    fileprivate func show(_ touches: Set<UITouch>) {
        guard let overlay else { return }
        for touch in touches {
            let key = ObjectIdentifier(touch)
            let marker = markers[key] ?? makeMarker(in: overlay)
            markers[key] = marker
            marker.center = touch.location(in: overlay)
        }
    }

    fileprivate func hide(_ touches: Set<UITouch>) {
        for touch in touches {
            guard let marker = markers.removeValue(forKey: ObjectIdentifier(touch)) else { continue }
            UIView.animate(withDuration: 0.4, animations: { marker.alpha = 0 }) { _ in marker.removeFromSuperview() }
        }
    }

    private func makeMarker(in overlay: UIWindow) -> UIView {
        let size = 44.0
        let marker = UIView(frame: CGRect(x: 0, y: 0, width: size, height: size))
        marker.layer.cornerRadius = size / 2
        marker.backgroundColor = UIColor.systemGray.withAlphaComponent(0.5)
        marker.layer.borderColor = UIColor.white.withAlphaComponent(0.8).cgColor
        marker.layer.borderWidth = 2
        overlay.addSubview(marker)
        return marker
    }
}

/// Sees every touch in its window and never takes one away from the views below.
private final class TouchObserver: UIGestureRecognizer, UIGestureRecognizerDelegate {
    private unowned let indicator: TapIndicator

    init(indicator: TapIndicator) {
        self.indicator = indicator
        super.init(target: nil, action: nil)
        cancelsTouchesInView = false
        delaysTouchesBegan = false
        delaysTouchesEnded = false
        delegate = self
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) { indicator.show(touches) }
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) { indicator.show(touches) }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) { finish(touches, event) }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) { finish(touches, event) }

    private func finish(_ touches: Set<UITouch>, _ event: UIEvent) {
        indicator.hide(touches)
        let remaining = event.allTouches?.filter { $0.phase != .ended && $0.phase != .cancelled } ?? []
        if remaining.isEmpty { state = .failed }
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
    ) -> Bool {
        true
    }
}
