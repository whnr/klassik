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

    @Test func theFadeSliderRunsFromZeroTo300AndStartsAt100() {
        #expect(LabPlayer.fadeRange == 0...300)
        #expect(LabPlayer.defaultFade == 100)
        #expect(LabPlayer.fadeSeconds(milliseconds: 100) == 0.1)
        #expect(LabPlayer.fadeSeconds(milliseconds: 0) == 0)
        #expect(LabPlayer.fadeSeconds(milliseconds: 300) == 0.3)
        #expect(LabPlayer.fadeSeconds(milliseconds: 900) == 0.3)
    }
}
