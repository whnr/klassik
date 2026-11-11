import Foundation

/// The screen edge that the timeline runs on. The listener picks it (ADR 0014).
enum TimelineSide: String, CaseIterable, Identifiable, Sendable {
    case right
    case left

    static let standard = TimelineSide.right
    static let storageKey = "timeline.side"

    var id: Self { self }

    var title: String {
        switch self {
        case .right: "Right"
        case .left: "Left"
        }
    }
}

/// Where each movement sits on the timeline, and the place in the music under a point (ADR 0014, 0035).
/// Points count down from the top of the bar. Times are in seconds.
struct TimelineBar: Sendable {
    struct Segment: Equatable, Sendable {
        var top: Double
        var height: Double
        var bottom: Double { top + height }
    }

    /// A movement and the seconds into it.
    struct Place: Equatable, Sendable {
        var movement: Int
        var seconds: Double
    }

    let durations: [Double]
    let segments: [Segment]

    /// One segment for each movement, as long as its share of the whole, with `gap` between two segments.
    init(durations: [Double], height: Double, gap: Double) {
        self.durations = durations
        let lengths = durations.map { max($0, 0) }
        let total = lengths.reduce(0, +)
        // Without lengths, each movement gets the same share, so the bar still shows how many there are.
        let shares = lengths.map { total > 0 ? $0 / total : 1 / Double(lengths.count) }
        let usable = max(height - gap * Double(max(lengths.count - 1, 0)), 0)
        var top = 0.0
        segments = shares.map { share in
            defer { top += share * usable + gap }
            return Segment(top: top, height: share * usable)
        }
    }

    /// How much of each movement has played, from 0 to 1.
    func played(movement: Int, position: Double) -> [Double] {
        durations.indices.map { index in
            if index < movement { return 1 }
            if index > movement || durations[index] <= 0 { return 0 }
            return min(max(position / durations[index], 0), 1)
        }
    }

    /// The place under a point. A point in a gap is the start of the movement below it. Above the bar is the
    /// start of the first movement, below it the end of the last one.
    func place(at y: Double) -> Place? {
        guard !segments.isEmpty else { return nil }
        let movement = segments.firstIndex { y < $0.bottom } ?? segments.count - 1
        let segment = segments[movement]
        let share = segment.height > 0 ? min(max((y - segment.top) / segment.height, 0), 1) : 0
        return Place(movement: movement, seconds: share * max(durations[movement], 0))
    }

    /// The centre of the scrub label: level with the finger, but whole on screen between `top` and `floor`.
    static func labelCentre(finger: Double, labelHeight: Double, top: Double, floor: Double) -> Double {
        let half = labelHeight / 2
        return max(min(finger, floor - half), top + half)
    }
}

/// What a touch on the timeline is, decided by how the finger moves. A vertical move scrubs; a tap plays the
/// movement under the finger; a sideways swipe changes nothing in the music (ADR 0014).
enum TimelineTouch: Equatable, Sendable {
    case undecided
    case scrub
    case sideways

    /// How far a finger moves before the touch is no longer a tap, in points.
    static let slop = 8.0
    /// The length of a swipe that goes back, in points. The edge swipe of ADR 0038 uses the same.
    static let backSwipe = 60.0

    /// What the timeline does when the finger lifts.
    enum Action: Equatable, Sendable {
        case nothing
        case play(movement: Int)
        case seek(TimelineBar.Place)
        /// The timeline on the left edge covers the start of the system back swipe, so it goes back itself.
        case back
    }

    /// The touch after the finger moved by `dx` and `dy` from where it went down. Once decided, it stays.
    func moved(dx: Double, dy: Double) -> TimelineTouch {
        guard self == .undecided else { return self }
        if abs(dy) > Self.slop, abs(dy) > abs(dx) { return .scrub }
        if abs(dx) > Self.slop { return .sideways }
        return .undecided
    }

    func end(dx: Double, side: TimelineSide, at place: TimelineBar.Place?) -> Action {
        switch self {
        case .undecided: place.map { .play(movement: $0.movement) } ?? .nothing
        case .scrub: place.map { .seek($0) } ?? .nothing
        case .sideways: side == .left && dx > Self.backSwipe ? .back : .nothing
        }
    }
}
