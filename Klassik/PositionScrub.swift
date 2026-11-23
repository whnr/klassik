import Foundation

/// What the position bar of the playing movement shows. While a finger drags, the bar follows the finger. After
/// the finger lifts, the bar holds the new place until the player reports it, so the bar does not jump back to
/// the old place while the movement starts again.
struct PositionScrub {
    /// A reported position this close to the new place counts as arrived, in seconds.
    static let arrival = 1.0
    /// The longest hold after a lift. A player that cannot reach the place must not freeze the bar.
    static let longestHold = Duration.seconds(3)

    private(set) var dragged: Double?
    private var released: (seconds: Double, at: ContinuousClock.Instant)?

    mutating func drag(to seconds: Double) {
        dragged = seconds
        released = nil
    }

    /// Ends the drag. Returns the place to seek to, or nil when no drag ran.
    mutating func release(at now: ContinuousClock.Instant = .now) -> Double? {
        guard let dragged else { return nil }
        self.dragged = nil
        released = (dragged, now)
        return dragged
    }

    /// Drops a drag that did not end with a lift. A hold after a lift stays.
    mutating func cancel() { dragged = nil }

    /// The player reported a position. The hold ends when it arrived at the new place.
    mutating func observe(elapsed: Double) {
        if let released, abs(elapsed - released.seconds) <= Self.arrival { self.released = nil }
    }

    func shown(elapsed: Double, at now: ContinuousClock.Instant = .now) -> Double {
        if let dragged { return dragged }
        if let released, now - released.at < Self.longestHold { return released.seconds }
        return elapsed
    }

    /// The place under a finger at `x` on a bar of `width` points, inside the movement.
    static func seconds(at x: Double, width: Double, duration: Double) -> Double {
        guard width > 0, duration > 0 else { return 0 }
        return min(max(x / width, 0), 1) * duration
    }

    /// The played share of the bar, from 0 to 1.
    static func share(_ seconds: Double, of duration: Double) -> Double {
        guard duration > 0 else { return 0 }
        return min(max(seconds / duration, 0), 1)
    }
}
