import Foundation
import Testing

@testable import Klassik

/// The read-ahead set follows the queue and the data mode of ADR 0060.
struct ReadAheadTests {
    func item(_ id: String, movements: Int) -> QueueItem {
        let songs = (0..<movements).map { Song(id: "\(id)-\($0)", title: "Movement \($0 + 1)", suffix: "flac") }
        let recording = WorkIndex.Recording(id: id, album: id, songs: songs)
        let work = WorkIndex.Work(id: id, title: id, composer: "Fixture", isTagged: false, recordings: [recording])
        return QueueItem(work: work, recording: recording)
    }

    func plan(_ movement: Int, _ mode: DataMode, queued: Bool = true) -> [String] {
        let upNext = queued ? [item("b", movements: 2), item("c", movements: 2)] : []
        return ReadAhead.plan(item("a", movements: 4), movement: movement, upNext: upNext, mode: mode).map(\.id)
    }

    /// Wi-Fi prepares the rest of the work and all of the next queue item, never the item after it.
    @Test func normalModePreparesTheWholeWorkAndTheWholeNextItem() {
        #expect(plan(0, .normal) == ["a-1", "a-2", "a-3", "b-0", "b-1"])
        #expect(plan(2, .normal) == ["a-3", "b-0", "b-1"])
    }

    /// A next item that repeats tracks of the current work prepares each track once.
    @Test func aRepeatedItemPreparesItsTracksOnce() {
        let current = item("a", movements: 3)
        let planned = ReadAhead.plan(current, movement: 1, upNext: [current], mode: .normal).map(\.id)
        #expect(planned == ["a-2"])
    }

    @Test func constrainedModePreparesOneTrack() {
        #expect(plan(0, .constrained) == ["a-1"])
        #expect(plan(2, .constrained) == ["a-3"])
    }

    /// At a work boundary, Wi-Fi prepares the whole next work and cellular its first track.
    @Test func theLastMovementPreparesTheNextWork() {
        #expect(plan(3, .normal) == ["b-0", "b-1"])
        #expect(plan(3, .constrained) == ["b-0"])
    }

    @Test func theEndOfTheQueuePreparesNothingMore() {
        #expect(plan(3, .normal, queued: false).isEmpty)
        #expect(plan(1, .normal, queued: false) == ["a-2", "a-3"])
    }

    @Test func offlinePreparesNothing() {
        #expect(plan(0, .offline).isEmpty)
        #expect(plan(3, .offline).isEmpty)
    }

    /// Cellular, Low Data Mode and Low Power Mode each prepare one track; only Wi-Fi prepares whole works.
    @Test func cellularLowDataModeAndLowPowerModeConstrain() {
        #expect(DataMode.of(satisfied: true, constrained: false, cellular: false, lowPower: false) == .normal)
        #expect(DataMode.of(satisfied: true, constrained: false, cellular: true, lowPower: false) == .constrained)
        #expect(DataMode.of(satisfied: true, constrained: true, cellular: false, lowPower: false) == .constrained)
        #expect(DataMode.of(satisfied: true, constrained: false, cellular: false, lowPower: true) == .constrained)
        #expect(DataMode.of(satisfied: false, constrained: false, cellular: true, lowPower: false) == .offline)
    }
}

/// The slow-connection line shows after one second without sound, only on a slow connection (ADR 0060).
struct SlowConnectionLineTests {
    let start = ContinuousClock.now

    @Test func theLineWaitsOneSecond() {
        var line = SlowConnectionLine()
        line.update(PlaybackWait(kind: .start, slow: true), at: start)
        #expect(line.text(at: start + .milliseconds(999)) == nil)
        #expect(line.text(at: start + .seconds(1)) == SlowConnectionLine.startText)
        #expect(line.due == start + .seconds(1))
    }

    @Test func aFastConnectionShowsNoLine() {
        var line = SlowConnectionLine()
        line.update(PlaybackWait(kind: .start, slow: false), at: start)
        #expect(line.text(at: start + .seconds(5)) == nil)
        // The connection turns slow later; the second without sound already passed.
        line.update(PlaybackWait(kind: .start, slow: true), at: start + .seconds(5))
        #expect(line.text(at: start + .seconds(5)) == SlowConnectionLine.startText)
    }

    @Test func soundRemovesTheLine() {
        var line = SlowConnectionLine()
        line.update(PlaybackWait(kind: .start, slow: true), at: start)
        line.update(nil, at: start + .seconds(2))
        #expect(line.text(at: start + .seconds(3)) == nil)
        #expect(line.due == nil)
    }

    /// A later starvation shows the recovery text after its own second.
    @Test func aLaterWaitShowsTheRecoveryLine() {
        var line = SlowConnectionLine()
        line.update(PlaybackWait(kind: .start, slow: true), at: start)
        line.update(nil, at: start + .seconds(2))
        line.update(PlaybackWait(kind: .resume, slow: true), at: start + .seconds(60))
        #expect(line.text(at: start + .milliseconds(60_500)) == nil)
        #expect(line.text(at: start + .seconds(61)) == SlowConnectionLine.resumeText)
    }

    @Test func clearRemovesTheLine() {
        var line = SlowConnectionLine()
        line.update(PlaybackWait(kind: .resume, slow: true), at: start)
        line.clear()
        #expect(line.text(at: start + .seconds(2)) == nil)
    }

    @Test func theTextsAreTheChosenOnes() {
        #expect(SlowConnectionLine.startText == "Slow connection. Playback will start shortly.")
        #expect(SlowConnectionLine.resumeText == "Slow connection. Playback will continue shortly.")
    }
}
