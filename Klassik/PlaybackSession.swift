import AVFoundation
import MediaPlayer
import Observation

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
    private(set) var item: QueueItem? {
        didSet { updateNextCommand() }
    }
    private(set) var upNext: [QueueItem] = [] {
        didSet { updateNextCommand() }
    }
    private(set) var movement: Int? {
        didSet {
            applyGain()
            updateNowPlaying()
            updateNextCommand()
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

    var scrobblesEnabled: Bool {
        willSet { savePosition() }
        didSet { defaults.set(scrobblesEnabled, forKey: Self.scrobblesKey) }
    }
    private(set) var listeningError: String?

    /// A different login must never receive the queue of this login.
    @ObservationIgnored var server: (any ServerPort)? {
        didSet {
            savePosition()
            if item != nil { persistQueue() }
            reset()
            upNext = []
            canSaveQueue = false
            queueRevision += 1
            restored = false
            history = server.map { PlaybackHistory(server: $0, defaults: defaults) }
            listeningError = nil
            let currentHistory = history
            history?.onError = { [weak self, weak currentHistory] message in
                guard let self, self.history === currentHistory else { return }
                self.listeningError = message
            }
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        }
    }

    /// False on the last movement of the last item, where Next has nowhere to go.
    var hasNext: Bool {
        guard let item, let movement else { return false }
        return movement + 1 < item.recording.songs.count || !upNext.isEmpty
    }

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

    private var history: PlaybackHistory?
    private var queueRevision = 0
    private var restored = false
    private var canSaveQueue = false
    private var lastQueueSave = ContinuousClock.now
    private static let scrobblesKey = "player.scrobbles"
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
        scrobblesEnabled = defaults.object(forKey: Self.scrobblesKey) as? Bool ?? true
        leveling = defaults.string(forKey: Self.levelingKey).flatMap(VolumeLeveling.init) ?? .album
        engine.onEvent = { [weak self] event in self?.engineEvent(event) }
        observeAudioSession()
        registerRemoteCommands()
        updateNextCommand()
    }

    // MARK: Server history

    /// A slow launch response must not replace a queue that the listener has already started.
    func restoreQueue() async {
        guard !restored, item == nil, let history else { return }
        let revision = queueRevision
        do {
            let saved = try await history.restore()
            guard self.history === history, queueRevision == revision, item == nil else { return }
            restored = true
            listeningError = nil
            guard let saved, let first = saved.items.first else { return }
            upNext = Array(saved.items.dropFirst())
            start(first, from: saved.movement, offset: saved.position, paused: true, save: false)
        } catch {
            if self.history === history, queueRevision == revision {
                listeningError = "Could not restore the queue from the server."
            }
        }
    }

    /// Saves before the app enters the background, where iOS can suspend a paused session.
    func saveQueue() async {
        savePosition()
        persistQueue()
        await history?.flush()
    }

    private func persistQueue() {
        guard canSaveQueue, let history else { return }
        history.save(items: item.map { [$0] + upNext } ?? [], movement: movement ?? 0, position: position)
        lastQueueSave = .now
    }

    private func hear(through found: (movement: Int, elapsed: Double)) {
        guard let item, let movement, found.movement >= movement else { return }
        for index in movement...found.movement where segments.indices.contains(index) {
            history?.hear(
                item: item, movement: index, position: index == found.movement ? found.elapsed : segments[index],
                duration: segments[index], enabled: scrobblesEnabled)
        }
    }

    // MARK: Queue

    /// Plays one item. On the item that already plays, it pauses or resumes, as a tap on its tinted row does
    /// (ADR 0039). Any other item replaces the queue (ADR 0006).
    func play(_ item: QueueItem) {
        if let playing = self.item, playing.recording.id == item.recording.id {
            togglePause()
        } else {
            play(queue: [item])
        }
    }

    /// Plays one item from a movement. A movement of the playing item only moves the position and keeps the
    /// queue (ADR 0014). Any other item replaces the queue (ADR 0006).
    func play(_ item: QueueItem, from movement: Int, at position: Double = 0) {
        if let playing = self.item, playing.recording.id == item.recording.id {
            start(playing, from: movement, offset: position, preserveListen: true)
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
        persistQueue()
    }

    /// Puts an item at the end of the queue. With nothing playing, it plays at once.
    func addToQueue(_ item: QueueItem) {
        guard self.item != nil else { return play(queue: [item]) }
        upNext.append(item)
        persistQueue()
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
        persistQueue()
    }

    func moveInQueue(from source: IndexSet, to destination: Int) {
        upNext.move(fromOffsets: source, toOffset: destination)
        persistQueue()
    }

    // MARK: Transport

    /// Goes to the next movement, or to the next item after the last movement. On the last movement of the last
    /// item it does nothing.
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
        guard let movement else { return }
        seek(movement: movement, to: seconds)
    }

    /// Moves to a position in any movement of the item that plays, as a scrub on the timeline does. A paused
    /// player stays paused.
    func seek(movement index: Int, to seconds: Double) {
        guard let item, item.recording.songs.indices.contains(index) else { return }
        start(item, from: index, offset: seconds, paused: !playback.wantsPlayback, preserveListen: true)
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
        canSaveQueue = true
        savePosition()
        history?.endListening()
        queueRevision += 1
        reset()
        upNext = []
        persistQueue()
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    /// The system may call from any thread. The command moves to the main actor, where the state lives.
    nonisolated func receive(_ command: RemoteCommand) {
        Task { @MainActor in self.perform(command) }
    }

    // MARK: Events

    /// Applies what the audio session reported. Tests call it with the events that the notifications map to.
    func handle(_ event: PlaybackState.Event) {
        savePosition()
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
        persistQueue()
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
        guard let item, let movement, ended >= movement, segments.indices.contains(ended) else { return }
        hear(through: (ended, segments[ended]))
        if ended + 1 < item.recording.songs.count {
            checkpoint = (ended + 1, 0)
            position = 0
            self.movement = ended + 1
            history?.begin(item: item, movement: ended + 1, position: 0)
            persistQueue()
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

    private func start(
        _ item: QueueItem, from index: Int, offset: Double = 0, paused: Bool = false, save: Bool = true,
        preserveListen: Bool = false
    ) {
        guard server != nil, item.recording.songs.indices.contains(index) else { return }
        savePosition()
        canSaveQueue = true
        queueRevision += 1
        reset()
        _ = playback.handle(paused ? .pause : .play)
        self.item = item
        checkpoint = (index, offset)
        position = offset
        refreshSegments()
        movement = index
        if !preserveListen { history?.endListening() }
        history?.begin(item: item, movement: index, position: offset)
        if playback.shouldPlay { rebuild() }
        updateNowPlaying()
        if save { persistQueue() }
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
                if self.playback.shouldPlay, self.lastQueueSave.duration(to: .now) >= .seconds(5) {
                    self.persistQueue()
                }
            }
        }
    }

    private func playbackFailed(_ text: String) {
        savePosition()
        _ = playback.handle(.pause)
        discardEngine()
        error = text
        updateNowPlaying()
        persistQueue()
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
        refreshSegments()
        if playback.shouldPlay { hear(through: found) }
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

    /// The lock screen shows Next as unavailable where the app has none.
    private func updateNextCommand() {
        MPRemoteCommandCenter.shared().nextTrackCommand.isEnabled = hasNext
    }

    /// Fills the lock screen and Control Center.
    private func updateNowPlaying() {
        guard let work, let recording, let movement, segments.indices.contains(movement) else { return }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: recording.title(of: recording.songs[movement]),
            MPMediaItemPropertyArtist: recording.summary,
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
