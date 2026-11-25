import Testing

@testable import KlassikLab

struct LabPlayerTests {
    @Test func switchWhilePlayingRestartsTheEngine() {
        #expect(LabPlayer.switchAction(isPlaying: true, hasEngine: true) == .restart)
    }

    @Test func switchWhilePausedDiscardsTheEngine() {
        #expect(LabPlayer.switchAction(isPlaying: false, hasEngine: true) == .discard)
    }

    @Test func switchWithoutEngineDoesNothing() {
        #expect(LabPlayer.switchAction(isPlaying: false, hasEngine: false) == .none)
        #expect(LabPlayer.switchAction(isPlaying: true, hasEngine: false) == .none)
    }
}
