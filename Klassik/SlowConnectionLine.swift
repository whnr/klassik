import Foundation
import KlassikEngine

/// The one line under the playback bar while a slow connection keeps the player silent (ADR 0060).
/// It shows after one second without sound, and only when the throughput is below the needed bitrate.
struct SlowConnectionLine: Equatable {
    static let delay = Duration.seconds(1)
    static var startText: String { L("Slow connection. Playback will start shortly.") }
    static var resumeText: String { L("Slow connection. Playback will continue shortly.") }

    private var wait: PlaybackWait?
    private var since: ContinuousClock.Instant?

    /// The engine reports a wait, a change of its throughput, or nil for sound.
    mutating func update(_ wait: PlaybackWait?, at now: ContinuousClock.Instant) {
        if wait?.kind != self.wait?.kind { since = wait == nil ? nil : now }
        self.wait = wait
    }

    /// Pause, Stop and a new selection remove the line.
    mutating func clear() {
        wait = nil
        since = nil
    }

    /// When a waiting line can next appear, for the timer that asks again.
    var due: ContinuousClock.Instant? { since.map { $0 + Self.delay } }

    func text(at now: ContinuousClock.Instant) -> String? {
        guard let wait, wait.slow, let since, since.duration(to: now) >= Self.delay else { return nil }
        return wait.kind == .start ? Self.startText : Self.resumeText
    }
}
