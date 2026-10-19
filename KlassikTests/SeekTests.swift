import Testing

@testable import Klassik

struct SeekTests {
    /// The playable range of an MP3 starts after the encoder delay; a seek counts from there.
    @Test func seekCountsFromTheStartOfThePlayableRange() {
        #expect(Player.seekRange(1105..<45_205, to: 0.5, sampleRate: 44_100) == 23_155..<45_205)
    }

    @Test func seekBeforeTheStartPlaysTheWholeMovement() {
        #expect(Player.seekRange(0..<44_100, to: -3, sampleRate: 44_100) == 0..<44_100)
    }

    /// A seek past the end keeps one frame, so the movement ends and the next one follows.
    @Test func seekPastTheEndKeepsTheLastFrame() {
        #expect(Player.seekRange(0..<44_100, to: 10, sampleRate: 44_100) == 44_099..<44_100)
    }

    @Test func seekToAnInvalidTimeStartsAtTheBeginning() {
        #expect(Player.seekRange(0..<44_100, to: .nan, sampleRate: 44_100) == 0..<44_100)
    }

    @Test func seekUsesTheFileSampleRate() {
        #expect(Player.seekRange(0..<960_000, to: 2, sampleRate: 96_000) == 192_000..<960_000)
    }
}
