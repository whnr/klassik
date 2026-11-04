/// Keeps listener intent separate from temporary loss of the audio session or engine.
struct PlaybackState: Sendable {
    enum Event: Sendable {
        case play
        case resume
        case pause
        case stop
        case interruptionBegan
        case interruptionEnded(shouldResume: Bool)
        case routeChanged(oldDeviceUnavailable: Bool, headphonesRemoved: Bool)
        case configurationChanged
        case mediaServicesLost
        case mediaServicesReset
    }

    enum Action: Equatable {
        case none
        case pause
        case suspend
        case resume
        case rebuild
    }

    private(set) var wantsPlayback = false
    private(set) var isInterrupted = false
    private(set) var mediaServicesAvailable = true

    var shouldPlay: Bool { wantsPlayback && !isInterrupted && mediaServicesAvailable }

    mutating func handle(_ event: Event) -> Action {
        switch event {
        case .play:
            wantsPlayback = true
            return shouldPlay ? .resume : .none
        case .resume:
            // An interruption can have no end notification. Explicit Play must still try session activation.
            isInterrupted = false
            wantsPlayback = true
            return shouldPlay ? .resume : .none
        case .pause:
            wantsPlayback = false
            return .pause
        case .stop:
            wantsPlayback = false
            return .suspend
        case .interruptionBegan:
            isInterrupted = true
            return .suspend
        case .interruptionEnded(let shouldResume):
            guard isInterrupted else { return .none }
            isInterrupted = false
            if !shouldResume { wantsPlayback = false }
            return shouldPlay ? .rebuild : .none
        case .routeChanged(let oldDeviceUnavailable, let headphonesRemoved):
            guard oldDeviceUnavailable && headphonesRemoved else { return .none }
            wantsPlayback = false
            return .pause
        case .configurationChanged:
            return shouldPlay ? .rebuild : .suspend
        case .mediaServicesLost:
            mediaServicesAvailable = false
            return .suspend
        case .mediaServicesReset:
            mediaServicesAvailable = true
            return shouldPlay ? .rebuild : .suspend
        }
    }
}
