import Foundation

/// Maps node frames to valid audio frames. Silence during a network wait has no place in a movement (ADR 0060).
struct AudioTimeline {
    struct Span {
        var movement: Int
        var node: Range<Int64>
        var audio: Range<Int64>
    }

    private(set) var spans: [Span] = []
    private(set) var end: Int64 = 0
    private var lengths: [Int: Int64] = [:]

    mutating func declare(_ movement: Int, frames: Int64) {
        lengths[movement] = frames
    }

    func length(_ movement: Int) -> Int64? { lengths[movement] }

    /// Returns the exact node range assigned to these frames. A dry node can have advanced past its last buffer.
    mutating func append(_ movement: Int, audio: Range<Int64>, rendered: Int64) -> Range<Int64> {
        let start = max(end, rendered)
        let range = start..<(start + Int64(audio.count))
        spans.append(Span(movement: movement, node: range, audio: audio))
        end = range.upperBound
        return range
    }

    func position(at sample: Int64, from movement: Int) -> (movement: Int, frame: Int64)? {
        guard let span = spans.last(where: { $0.movement >= movement && $0.node.lowerBound <= sample }) else {
            return nil
        }
        return (
            span.movement, span.audio.lowerBound + min(max(sample - span.node.lowerBound, 0), Int64(span.audio.count))
        )
    }

    /// Finished spans no longer need per-buffer records. Retain the last span for progress while bytes arrive.
    mutating func prune(before sample: Int64) {
        guard let last = spans.lastIndex(where: { $0.node.upperBound <= sample }), last > 0 else { return }
        spans.removeFirst(last)
    }
}
