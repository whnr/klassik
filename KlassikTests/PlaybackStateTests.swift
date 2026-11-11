import Testing

@testable import Klassik

struct PlaybackStateTests {
    private func playing() -> PlaybackState {
        var state = PlaybackState()
        #expect(state.handle(.play) == .resume)
        #expect(state.shouldPlay)
        return state
    }

    @Test func interruptionResumesWithPermission() {
        var state = playing()
        #expect(state.handle(.interruptionBegan) == .suspend)
        #expect(!state.shouldPlay)
        #expect(state.wantsPlayback)
        #expect(state.handle(.interruptionEnded(shouldResume: true)) == .rebuild)
        #expect(state.shouldPlay)
    }

    @Test func interruptionWithoutPermissionNeedsExplicitPlay() {
        var state = playing()
        _ = state.handle(.interruptionBegan)
        #expect(state.handle(.interruptionEnded(shouldResume: false)) == .none)
        #expect(!state.shouldPlay)
        #expect(state.handle(.configurationChanged) == .suspend)
        #expect(state.handle(.mediaServicesReset) == .suspend)
        #expect(state.handle(.play) == .resume)
        #expect(state.shouldPlay)
    }

    @Test func pausedMusicDoesNotResumeAfterInterruption() {
        var state = playing()
        #expect(state.handle(.pause) == .pause)
        _ = state.handle(.interruptionBegan)
        #expect(state.handle(.interruptionEnded(shouldResume: true)) == .none)
        #expect(!state.shouldPlay)
    }

    @Test func pauseDuringInterruptionCancelsResume() {
        var state = playing()
        _ = state.handle(.interruptionBegan)
        _ = state.handle(.pause)
        #expect(state.handle(.interruptionEnded(shouldResume: true)) == .none)
        #expect(!state.shouldPlay)
    }

    @Test func duplicateInterruptionNotificationsDoNotRestartPlayback() {
        var state = playing()
        _ = state.handle(.interruptionBegan)
        _ = state.handle(.interruptionBegan)
        #expect(state.handle(.interruptionEnded(shouldResume: true)) == .rebuild)
        #expect(state.handle(.interruptionEnded(shouldResume: true)) == .none)
        #expect(state.shouldPlay)
    }

    @Test func playDuringInterruptionWaitsForPermission() {
        var state = PlaybackState()
        _ = state.handle(.interruptionBegan)
        #expect(state.handle(.play) == .none)
        #expect(!state.shouldPlay)
        #expect(state.handle(.configurationChanged) == .suspend)
        #expect(state.handle(.interruptionEnded(shouldResume: true)) == .rebuild)
    }

    @Test func explicitResumeWorksWithoutAnInterruptionEndNotification() {
        var state = playing()
        _ = state.handle(.interruptionBegan)
        #expect(state.handle(.resume) == .resume)
        #expect(state.shouldPlay)
        #expect(state.handle(.interruptionEnded(shouldResume: false)) == .none)
        #expect(state.shouldPlay)
    }

    @Test func explicitResumeWaitsForMediaServices() {
        var state = playing()
        _ = state.handle(.mediaServicesLost)
        #expect(state.handle(.resume) == .none)
        #expect(!state.shouldPlay)
        #expect(state.handle(.mediaServicesReset) == .rebuild)
    }

    @Test func replacingPlaybackDuringInterruptionKeepsTheSessionBlocked() {
        var state = playing()
        _ = state.handle(.interruptionBegan)
        _ = state.handle(.stop)
        #expect(state.handle(.play) == .none)
        #expect(!state.shouldPlay)
        #expect(state.handle(.interruptionEnded(shouldResume: true)) == .rebuild)
    }

    @Test func headphoneRemovalPausesUntilExplicitPlay() {
        var state = playing()
        #expect(state.handle(.routeChanged(oldDeviceUnavailable: true, headphonesRemoved: true)) == .suspend)
        #expect(!state.shouldPlay)
        #expect(state.handle(.configurationChanged) == .suspend)
        #expect(state.handle(.routeChanged(oldDeviceUnavailable: false, headphonesRemoved: false)) == .none)
        #expect(!state.shouldPlay)
        #expect(state.handle(.play) == .resume)
        #expect(state.shouldPlay)
    }

    @Test func headphoneRemovalDuringInterruptionCancelsResume() {
        var state = playing()
        _ = state.handle(.interruptionBegan)
        _ = state.handle(.routeChanged(oldDeviceUnavailable: true, headphonesRemoved: true))
        #expect(state.handle(.interruptionEnded(shouldResume: true)) == .none)
        #expect(!state.shouldPlay)
    }

    @Test(arguments: [false, true])
    func otherRouteChangesKeepPlaying(headphonesInPreviousRoute: Bool) {
        var state = playing()
        #expect(
            state.handle(.routeChanged(oldDeviceUnavailable: false, headphonesRemoved: headphonesInPreviousRoute))
                == .none)
        #expect(state.shouldPlay)
    }

    @Test func losingCarPlayOrSpeakerDoesNotPause() {
        var state = playing()
        #expect(state.handle(.routeChanged(oldDeviceUnavailable: true, headphonesRemoved: false)) == .none)
        #expect(state.shouldPlay)
        #expect(state.handle(.configurationChanged) == .rebuild)
    }

    @Test func configurationChangesWaitUntilInterruptionEnds() {
        var state = playing()
        _ = state.handle(.interruptionBegan)
        #expect(state.handle(.configurationChanged) == .suspend)
        #expect(!state.shouldPlay)
        #expect(state.handle(.interruptionEnded(shouldResume: true)) == .rebuild)
    }

    @Test func mediaServicesResetRestoresOnlyPlayingMusic() {
        var state = playing()
        #expect(state.handle(.mediaServicesLost) == .suspend)
        #expect(!state.shouldPlay)
        #expect(state.handle(.configurationChanged) == .suspend)
        #expect(state.handle(.mediaServicesReset) == .rebuild)
        #expect(state.shouldPlay)
        _ = state.handle(.pause)
        #expect(state.handle(.mediaServicesReset) == .suspend)
        #expect(!state.shouldPlay)
    }

    @Test(arguments: [false, true])
    func overlappingResetAndInterruptionResumeOnlyWhenBothEnd(resetFirst: Bool) {
        var state = playing()
        _ = state.handle(.interruptionBegan)
        _ = state.handle(.mediaServicesLost)
        if resetFirst {
            #expect(state.handle(.mediaServicesReset) == .suspend)
            #expect(!state.shouldPlay)
            #expect(state.handle(.interruptionEnded(shouldResume: true)) == .rebuild)
        } else {
            #expect(state.handle(.interruptionEnded(shouldResume: true)) == .none)
            #expect(!state.shouldPlay)
            #expect(state.handle(.mediaServicesReset) == .rebuild)
        }
        #expect(state.shouldPlay)
    }

    @Test func pauseDuringMediaServicesLossCancelsResume() {
        var state = playing()
        _ = state.handle(.mediaServicesLost)
        _ = state.handle(.pause)
        #expect(state.handle(.mediaServicesReset) == .suspend)
        #expect(!state.shouldPlay)
    }

    @Test func stoppedMusicCannotResumeFromLateSystemEvents() {
        var state = playing()
        _ = state.handle(.interruptionBegan)
        #expect(state.handle(.stop) == .suspend)
        #expect(state.handle(.interruptionEnded(shouldResume: true)) == .none)
        #expect(state.handle(.mediaServicesReset) == .suspend)
        #expect(state.handle(.configurationChanged) == .suspend)
        #expect(!state.shouldPlay)
    }
}
