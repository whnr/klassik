import Testing

@testable import Klassik

struct AudioTimelineTests {
    @Test func starvationDoesNotMoveTheAudioCursorOrLength() {
        var timeline = AudioTimeline()
        timeline.declare(0, frames: 100)
        #expect(timeline.append(0, audio: 0..<50, rendered: 0) == 0..<50)
        #expect(timeline.position(at: 75, from: 0)?.frame == 50)
        #expect(timeline.append(0, audio: 50..<100, rendered: 75) == 75..<125)
        #expect(timeline.position(at: 75, from: 0)?.frame == 50)
        #expect(timeline.position(at: 100, from: 0)?.frame == 75)
        #expect(timeline.length(0) == 100)
    }

    @Test func aSeekAndARecordingBoundaryKeepExactFrameCoordinates() {
        var timeline = AudioTimeline()
        timeline.declare(0, frames: 100)
        #expect(timeline.append(0, audio: 75..<100, rendered: 0) == 0..<25)
        #expect(timeline.append(1, audio: 0..<100, rendered: 10) == 25..<125)
        #expect(timeline.position(at: 24, from: 0)?.frame == 99)
        #expect(timeline.position(at: 25, from: 0)?.movement == 1)
        #expect(timeline.position(at: 25, from: 0)?.frame == 0)
        #expect(timeline.position(at: 20, from: 1) == nil)
        timeline.prune(before: 100)
        #expect(timeline.position(at: 100, from: 1)?.frame == 75)
    }
}
