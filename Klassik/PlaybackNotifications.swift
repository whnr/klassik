import Foundation

/// Removes block observers when their player or engine goes away.
final class PlaybackNotifications {
    private var tokens: [NSObjectProtocol] = []

    func observe(
        _ name: Notification.Name, object: AnyObject? = nil,
        using handler: @escaping @Sendable (Notification) -> Void
    ) {
        tokens.append(NotificationCenter.default.addObserver(forName: name, object: object, queue: nil, using: handler))
    }

    deinit {
        for token in tokens { NotificationCenter.default.removeObserver(token) }
    }
}
