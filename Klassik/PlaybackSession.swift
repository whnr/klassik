import AVFoundation
import MediaPlayer
import Observation

/// One thing in the queue: a recording of a work, or a whole album.
struct QueueItem: Identifiable, Sendable {
    let id = UUID()
    var work: WorkIndex.Work
    var recording: WorkIndex.Recording
}

/// Owns the server and the queue. A view says what to play and reads the state; it never passes a client
/// and never asks an engine for progress.
@MainActor @Observable
final class PlaybackSession {
    /// How far the current movement and the whole item have played.
    struct Progress {
        var movement: Int
        var elapsed: Double
        var duration: Double
        var workElapsed: Double
        var workDuration: Double
        /// The length of each track, for the gaps in the whole-work bar.
        var durations: [Double]
    }

    /// Everything a view can show, at one moment.
    struct State {
        var item: QueueItem?
        /// The queue items that play after `item`, in order.
        var upNext: [QueueItem]
        /// The movement that is audible now, as an index into the songs of `item`.
        var movement: Int?
        /// Seconds into `movement`.
        var position: Double
        /// The length of each movement, in seconds.
        var segments: [Double]
        var isPaused: Bool
        var isLoading: Bool
        /// True after the last item played to its end.
        var queueEnded: Bool
        var error: String?
    }

    /// What the lock screen and Control Center ask for.
    enum RemoteCommand: Sendable {
        case play
        case pause
        case toggle
        case next
        case previous
        case seek(Double)
    }

    // Views read these one by one, so that the ticking position does not redraw a view that ignores it.
    private(set) var item: QueueItem?
    private(set) var upNext: [QueueItem] = []
    private(set) var movement: Int? {
        didSet {
            applyGain()
            updateNowPlaying()
        }
    }
    private(set) var position = 0.0
    private(set) var segments: [Double] = []
    var isPaused: Bool { !playback.shouldPlay }
    private(set) var isLoading = false
    private(set) var queueEnded = false
    private(set) var error: String?
    var leveling: VolumeLeveling {
        didSet {
            defaults.set(leveling.rawValue, forKey: Self.levelingKey)
            applyGain()
        }
    }

    /// Nil until the listener connects. Nothing plays without it.
    @ObservationIgnored var server: (any ServerPort)?

    var work: WorkIndex.Work? { item?.work }
    var recording: WorkIndex.Recording? { item?.recording }

    var state: State {
        State(
            item: item, upNext: upNext, movement: movement, position: position, segments: segments,
            isPaused: isPaused, isLoading: isLoading, queueEnded: queueEnded, error: error)
    }

    var progress: Progress? {
        guard recording != nil, let movement, segments.indices.contains(movement) else { return nil }
        return Progress(
            movement: movement, elapsed: position, duration: segments[movement],
            workElapsed: segments[..<movement].reduce(0, +) + position, workDuration: segments.reduce(0, +),
            durations: segments)
    }

    private var playback = PlaybackState()
    private let notifications = PlaybackNotifications()
    private let remoteTargets = RemoteCommandTargets()
    private var positionTask: Task<Void, Never>?
    /// Engine reconfiguration can erase its timeline before the notification reaches the main actor.
    private var checkpoint: (movement: Int, elapsed: Double)?
    /// Pause can reach the main actor before the final completion does.
    private var recordingCompleted = false
    private let engine: any PlaybackEngine
    private let store: TrackStore
    private let defaults: UserDefaults
    private static let levelingKey = "player.volumeLeveling"

    init(engine: any PlaybackEngine, store: TrackStore, defaults: UserDefaults = .standard) {
        self.engine = engine
        self.store = store
        self.defaults = defaults
        leveling = defaults.string(forKey: Self.levelingKey).flatMap(VolumeLeveling.init) ?? .album
        engine.onEvent = { [weak self] event in self?.engineEvent(event) }
        observeAudioSession()
        registerRemoteCommands()
    }

    // MARK: Queue

    /// Plays one item and keeps the queue when that item already plays: a movement of the playing item only
    /// moves the position. Any other item replaces the queue (ADR 0006, 0015).
    func play(_ item: QueueItem, from movement: Int = 0, at position: Double = 0) {
        if let playing = self.item, playing.recording.id == item.recording.id {
            start(playing, from: movement, offset: position)
        } else {
            play(queue: [item], from: movement, at: position)
        }
    }

    /// Replaces the queue. The first item plays, the others wait.
    func play(queue items: [QueueItem], from movement: Int = 0, at position: Double = 0) {
        guard let first = items.first, server != nil else { return }
        upNext = Array(items.dropFirst())
        start(first, from: movement, offset: position)
    }

    /// Puts an item at the top of the queue. With nothing playing, it plays at once.
    func playNext(_ item: QueueItem) {
        guard self.item != nil else { return play(queue: [item]) }
        upNext.insert(item, at: 0)
    }

    /// Puts an item at the end of the queue. With nothing playing, it plays at once.
    func addToQueue(_ item: QueueItem) {
        guard self.item != nil else { return play(queue: [item]) }
        upNext.append(item)
    }

    /// Skips to the next item in the queue.
    func nextItem() {
        guard !upNext.isEmpty, server != nil else { return }
        start(upNext.removeFirst(), from: 0)
    }

    /// Plays a queued item and drops the items before it.
    func playQueued(_ id: QueueItem.ID) {
        guard server != nil, let index = upNext.firstIndex(where: { $0.id == id }) else { return }
        let item = upNext[index]
        upNext.removeFirst(index + 1)
        start(item, from: 0)
    }

    func removeFromQueue(at offsets: IndexSet) {
        upNext.remove(atOffsets: offsets)
    }

    func moveInQueue(from source: IndexSet, to destination: Int) {
        upNext.move(fromOffsets: source, toOffset: destination)
    }

    // MARK: Transport

    /// Goes to the next movement, or to the next item after the last movement.
    func next() {
        guard let item, let movement else { return }
        if movement + 1 < item.recording.songs.count {
            start(item, from: movement + 1)
        } else {
            nextItem()
        }
    }

    /// Goes back to the start of the movement, or to the movement before if it has only just begun.
    func previous() {
        guard let item, let movement else { return }
        let restart = (located()?.elapsed ?? position) > 3 || movement == 0
        start(item, from: restart ? movement : movement - 1)
    }

    /// Moves to a position in the current movement. The movements after it schedule again, as after a skip,
    /// so they still join without a gap. A paused player stays paused.
    func seek(to seconds: Double) {
        guard let item, let movement else { return }
        start(item, from: movement, offset: seconds, paused: !playback.wantsPlayback)
    }

    func togglePause() {
        if isPaused { resume() } else { pause() }
    }

    func pause() {
        handle(.pause)
    }

    func resume() {
        guard item != nil else { return }
        handle(.resume)
    }

    /// Stops playback and empties the queue.
    func stop() {
        reset()
        upNext = []
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    /// The system may call from any thread. The command moves to the main actor, where the state lives.
    nonisolated func receive(_ command: RemoteCommand) {
        Task { @MainActor in self.perform(command) }
    }

    // MARK: Events

    /// Applies what the audio session reported. Tests call it with the events that the notifications map to.
    func handle(_ event: PlaybackState.Event) {
        let action = playback.handle(event)
        guard item != nil else { return }
        if recordingCompleted && playback.shouldPlay {
            completeRecording()
            return
        }
        switch action {
        case .none: break
        case .pause:
            savePosition()
            engine.pause()
        case .suspend:
            savePosition()
            discardEngine()
        case .rebuild:
            savePosition()
            rebuild()
        case .resume:
            if engine.isRunning {
                do { try engine.resume() } catch { playbackFailed(error.localizedDescription) }
            } else {
                rebuild()
            }
        }
        updateNowPlaying()
    }

    private func perform(_ command: RemoteCommand) {
        switch command {
        case .play: resume()
        case .pause: pause()
        case .toggle: togglePause()
        case .next: next()
        case .previous: previous()
        case .seek(let seconds): seek(to: seconds)
        }
    }

    private func engineEvent(_ event: PlaybackEngineEvent) {
        switch event {
        case .movementEnded(let ended): finished(ended)
        case .loading(let loading): isLoading = loading
        case .scheduled(let scheduled):
            refreshSegments()
            if scheduled == movement { updateNowPlaying() }
        case .configurationChanged: handle(.configurationChanged)
        case .problem(let text): error = text
        case .failed(let text): playbackFailed(text)
        }
    }

    private func finished(_ ended: Int) {
        guard let item, let movement, ended >= movement else { return }
        if ended + 1 < item.recording.songs.count {
            checkpoint = (ended + 1, 0)
            position = 0
            self.movement = ended + 1
        } else {
            recordingCompleted = true
            if playback.shouldPlay { completeRecording() }
        }
    }

    private func completeRecording() {
        if upNext.isEmpty {
            stop()
            queueEnded = true
        } else {
            nextItem()
        }
    }

    // MARK: Engine

    private func start(_ item: QueueItem, from index: Int, offset: Double = 0, paused: Bool = false) {
        guard server != nil else { return }
        reset()
        _ = playback.handle(paused ? .pause : .play)
        self.item = item
        checkpoint = (index, offset)
        position = offset
        refreshSegments()
        movement = index
        if playback.shouldPlay { rebuild() }
        updateNowPlaying()
    }

    private func rebuild() {
        guard playback.shouldPlay, let item, let server, let checkpoint else { return }
        discardEngine()
        position = checkpoint.elapsed
        movement = checkpoint.movement
        error = nil
        let store = store
        engine.load(item.recording.songs, from: checkpoint.movement, offset: checkpoint.elapsed) { song in
            try await store.file(for: song, client: server)
        }
        positionTask = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
                guard let self else { return }
                self.savePosition()
            }
        }
    }

    private func playbackFailed(_ text: String) {
        savePosition()
        _ = playback.handle(.pause)
        discardEngine()
        error = text
        updateNowPlaying()
    }

    private func reset() {
        _ = playback.handle(.stop)
        discardEngine()
        item = nil
        movement = nil
        checkpoint = nil
        recordingCompleted = false
        error = nil
        queueEnded = false
        position = 0
        segments = []
    }

    private func discardEngine() {
        positionTask?.cancel()
        positionTask = nil
        engine.discard()
        isLoading = false
    }

    /// Where playback is: the engine's answer, else the last saved place.
    private func located() -> (movement: Int, elapsed: Double)? {
        guard let movement, let checkpoint else { return nil }
        return engine.position(from: movement) ?? checkpoint
    }

    private func savePosition() {
        guard let found = located(), let movement, found.movement >= movement else { return }
        checkpoint = (found.movement, found.elapsed)
        if position != found.elapsed { position = found.elapsed }
        refreshSegments()
        if movement != found.movement { self.movement = found.movement }
    }

    private func refreshSegments() {
        guard let songs = item?.recording.songs else { return }
        let lengths = songs.indices.map { engine.duration(of: $0) ?? Double(songs[$0].duration ?? 0) }
        if lengths != segments { segments = lengths }
    }

    /// Album gains are the same for each movement, so a change at the movement boundary is not audible.
    private func applyGain() {
        guard let recording, let movement, recording.songs.indices.contains(movement) else { return engine.setGain(0) }
        engine.setGain(leveling.gain(for: recording.songs[movement]))
    }

    // MARK: System

    /// Fills the lock screen and Control Center.
    private func updateNowPlaying() {
        guard let work, let recording, let movement, segments.indices.contains(movement) else { return }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: recording.title(of: recording.songs[movement]),
            MPMediaItemPropertyArtist: recording.performers,
            MPMediaItemPropertyAlbumTitle: work.title,
            MPMediaItemPropertyPlaybackDuration: segments[movement],
            MPNowPlayingInfoPropertyElapsedPlaybackTime: position,
            MPNowPlayingInfoPropertyPlaybackRate: isPaused ? 0.0 : 1.0,
        ]
    }

    /// One handler for each remote command, ready for `addTarget`.
    struct RemoteHandlers: Sendable {
        typealias Handler = @Sendable (MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus
        let play: Handler
        let pause: Handler
        let toggle: Handler
        let next: Handler
        let previous: Handler
        let seek: Handler
    }

    /// The system calls these from a thread of its own. A closure that a main-actor method writes would be
    /// main-actor too, and it would trap at entry on that thread. Here the closures have no actor.
    nonisolated static func remoteHandlers(for session: PlaybackSession) -> RemoteHandlers {
        func forward(_ command: RemoteCommand) -> RemoteHandlers.Handler {
            { @Sendable [weak session] _ in
                session?.receive(command)
                return .success
            }
        }
        return RemoteHandlers(
            play: forward(.play), pause: forward(.pause), toggle: forward(.toggle), next: forward(.next),
            previous: forward(.previous),
            seek: { @Sendable [weak session] event in
                guard let time = (event as? MPChangePlaybackPositionCommandEvent)?.positionTime else {
                    return .commandFailed
                }
                session?.receive(.seek(time))
                return .success
            })
    }

    private func registerRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        let handlers = Self.remoteHandlers(for: self)
        remoteTargets.add(center.playCommand, handlers.play)
        remoteTargets.add(center.pauseCommand, handlers.pause)
        remoteTargets.add(center.togglePlayPauseCommand, handlers.toggle)
        remoteTargets.add(center.nextTrackCommand, handlers.next)
        remoteTargets.add(center.previousTrackCommand, handlers.previous)
        remoteTargets.add(center.changePlaybackPositionCommand, handlers.seek)
    }

    private func observeAudioSession() {
        notifications.observe(AVAudioSession.interruptionNotification) { [weak self] notification in
            guard let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                let type = AVAudioSession.InterruptionType(rawValue: raw)
            else { return }
            let event: PlaybackState.Event
            switch type {
            case .began: event = .interruptionBegan
            case .ended:
                let rawOptions = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
                event = .interruptionEnded(
                    shouldResume: AVAudioSession.InterruptionOptions(rawValue: rawOptions).contains(.shouldResume))
            @unknown default: return
            }
            Task { @MainActor in self?.handle(event) }
        }
        notifications.observe(AVAudioSession.routeChangeNotification) { [weak self] notification in
            let reason = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
            let previous =
                notification.userInfo?[AVAudioSessionRouteChangePreviousRouteKey] as? AVAudioSessionRouteDescription
            let headphonesRemoved =
                previous?.outputs.contains {
                    [.headphones, .bluetoothA2DP, .bluetoothLE, .bluetoothHFP].contains($0.portType)
                } ?? false
            let event = PlaybackState.Event.routeChanged(
                oldDeviceUnavailable: reason == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue,
                headphonesRemoved: headphonesRemoved)
            Task { @MainActor in self?.handle(event) }
        }
        notifications.observe(AVAudioSession.mediaServicesWereLostNotification) { [weak self] _ in
            Task { @MainActor in self?.handle(.mediaServicesLost) }
        }
        notifications.observe(AVAudioSession.mediaServicesWereResetNotification) { [weak self] _ in
            Task { @MainActor in self?.handle(.mediaServicesReset) }
        }
        // Secondary-audio hints concern soundtracks, not this app's primary music.
    }
}
