import AVFoundation
import KlassikEngine
import MediaPlayer
import Observation
import UIKit

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
        /// The slow-connection line under the playback bar, or nil (ADR 0060).
        var slowLine: String?
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

    /// Both playing cover slots follow the audible movement, including a start within a recording.
    var coverSong: Song? {
        guard let songs = item?.recording.songs else { return nil }
        guard let movement, songs.indices.contains(movement) else { return songs.first }
        return songs[movement]
    }
    private(set) var position = 0.0
    private(set) var segments: [Double] = []
    var isPaused: Bool { !playback.shouldPlay }
    private(set) var isLoading = false
    /// The line that replaces the times under the playback bar while a slow connection keeps the player silent.
    private(set) var slowLine: String?
    /// What the app may prepare without a request. AppModel follows the network path and Low Power Mode.
    var dataMode = DataMode.normal {
        didSet {
            store.networkAllowed = dataMode != .offline
            if dataMode != oldValue { prepareAhead() }
        }
    }
    private(set) var queueEnded = false
    private(set) var error: String?
    /// The kept cover of a song, or nil. AppModel reads it from the cover store, so the system players never
    /// wait for the network (ADR 0059).
    @ObservationIgnored var coverImage: (@MainActor (Song) async -> UIImage?)?
    /// The identity of the kept cover of a song, or nil. Songs with the same key share one picture, so the system
    /// players keep their artwork when the movement changes inside one recording.
    @ObservationIgnored var coverKey: (@MainActor (Song) -> String?)?
    /// The cover in the system players and the key that it belongs to.
    @ObservationIgnored private(set) var nowPlayingArtwork: (key: String, artwork: MPMediaItemArtwork)?
    /// The cover key that loads now.
    @ObservationIgnored private var artworkLoading: String?
    var leveling: VolumeLeveling {
        didSet {
            defaults.set(leveling.rawValue, forKey: Self.levelingKey)
            applyGain()
            syncGainStage()
        }
    }

    /// Shows the quality line under the playback bar.
    var showsAudioQuality: Bool {
        didSet {
            defaults.set(showsAudioQuality, forKey: Self.showsAudioQualityKey)
            refreshQuality()
        }
    }
    /// The quality line of the playing movement, or nil when the setting is off or nothing plays (sz-u8f4).
    private(set) var qualityLine: String?

    var scrobblesEnabled: Bool {
        willSet { savePosition() }
        didSet { defaults.set(scrobblesEnabled, forKey: Self.scrobblesKey) }
    }
    /// Why listening data waits on the device. The Library shows it in the one server status.
    private(set) var listeningTrouble: ServerTrouble?
    /// Why music stopped loading from the server. It joins the one server status and goes with the next sound
    /// (ADR 0060).
    private(set) var playbackTrouble: ServerTrouble?

    /// A different login must never receive the queue of this login.
    @ObservationIgnored var server: (any ServerPort)? {
        didSet {
            savePosition()
            if item != nil { persistQueue() }
            reset()
            upNext = []
            prepareAhead()
            canSaveQueue = false
            queueRevision += 1
            restored = false
            history?.endListening()
            history = server.map { server in
                let key = server.listeningDataKey
                if let existing = histories[key] {
                    existing.server = server
                    return existing
                }
                let created = PlaybackHistory(server: server, defaults: defaults)
                histories[key] = created
                return created
            }
            listeningTrouble = nil
            playbackTrouble = nil
            let currentHistory = history
            history?.onTrouble = { [weak self, weak currentHistory] trouble in
                guard let self, self.history === currentHistory else { return }
                self.listeningTrouble = trouble
            }
            history?.retryScrobbles()
            nowPlayingArtwork = nil
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
            isPaused: isPaused, isLoading: isLoading, slowLine: slowLine, queueEnded: queueEnded, error: error)
    }

    var progress: Progress? {
        guard recording != nil, let movement, segments.indices.contains(movement) else { return nil }
        return Progress(
            movement: movement, elapsed: position, duration: segments[movement],
            workElapsed: segments[..<movement].reduce(0, +) + position, workDuration: segments.reduce(0, +),
            durations: segments)
    }

    /// Login changes must share pending events and in-flight writes for each account.
    private var histories: [String: PlaybackHistory] = [:]
    private var history: PlaybackHistory?
    private var queueRevision = 0
    private var restored = false
    private var canSaveQueue = false
    private var lastQueueSave = ContinuousClock.now
    private static let scrobblesKey = "player.scrobbles"
    private var playback = PlaybackState()
    private var waiting = SlowConnectionLine()
    private var lineTask: Task<Void, Never>?
    private var readAheadTask: Task<Void, Never>?
    /// When the latest load asked for sound. The time to first sound measures how long an opening takes.
    private var soundRequested: ContinuousClock.Instant?
    /// The measured time from a request to the first sound of a streamed track, in seconds.
    private var openingSeconds = PlaybackSession.defaultOpeningSeconds
    static let defaultOpeningSeconds = 2.0
    /// Speculative bytes never compete with current playback below this much decoded audio (ADR 0060).
    static let competitionFloor = 2.0
    static let readAheadPoll = Duration.milliseconds(250)
    /// The read-ahead set that `readAheadTask` prepares, so that an unchanged set keeps its work.
    private var readAheadPlan: [String] = []
    private let notifications = PlaybackNotifications()
    private let remoteTargets = RemoteCommandTargets()
    private var positionTask: Task<Void, Never>?
    /// Engine reconfiguration can erase its timeline before the notification reaches the main actor.
    private var checkpoint: (movement: Int, elapsed: Double)?
    /// Pause can reach the main actor before the final completion does.
    private var recordingCompleted = false
    /// The current recording starts here in the engine's queue-wide track indices.
    private var engineBase = 0
    /// The tracks that the engine plays, from the first one of its load.
    private var engineSongs: [Song] = []
    /// Internal so that the tests can check the engine that the app builds.
    let engine: any PlaybackEngine
    private let store: TrackStore
    private let defaults: UserDefaults
    /// Replaces the leveling setting as the source of the volume change. Nil keeps the setting.
    private let gainStage: (any GainStage)?
    private static let levelingKey = "player.volumeLeveling"
    private static let showsAudioQualityKey = "player.showsAudioQuality"

    init(
        engine: any PlaybackEngine, store: TrackStore, defaults: UserDefaults = .standard,
        gainStage: (any GainStage)? = nil
    ) {
        self.engine = engine
        self.store = store
        self.defaults = defaults
        self.gainStage = gainStage
        scrobblesEnabled = defaults.object(forKey: Self.scrobblesKey) as? Bool ?? true
        leveling = defaults.string(forKey: Self.levelingKey).flatMap(VolumeLeveling.init) ?? .work
        showsAudioQuality = defaults.bool(forKey: Self.showsAudioQualityKey)
        engine.useGainStage(Self.wantsGainStage(leveling, gainStage))
        engine.onEvent = { [weak self] event in self?.engineEvent(event) }
        store.willClearMusic = { [weak self] in self?.musicCleared() }
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
            listeningTrouble = history.trouble
            guard let saved, let first = saved.items.first else { return }
            upNext = Array(saved.items.dropFirst())
            start(first, from: saved.movement, offset: saved.position, paused: true, save: false)
        } catch {
            if self.history === history, queueRevision == revision {
                listeningTrouble = ServerTrouble([error])
            }
        }
    }

    func synchronizeListeningData() async {
        history?.retryScrobbles()
        await history?.flush()
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

    /// Plays one item. On the item that already plays, it pauses or resumes, as a tap on its tinted row does.
    /// Any other item replaces the queue.
    func play(_ item: QueueItem) {
        if let playing = self.item, playing.recording.id == item.recording.id {
            togglePause()
        } else {
            play(queue: [item])
        }
    }

    /// Plays one item from a movement. A movement of the playing item only moves the position and keeps the
    /// queue. Any other item replaces the queue.
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
        queueChanged()
    }

    /// Puts an item at the end of the queue. With nothing playing, it plays at once.
    func addToQueue(_ item: QueueItem) {
        guard self.item != nil else { return play(queue: [item]) }
        upNext.append(item)
        queueChanged()
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
        queueChanged()
    }

    func moveInQueue(from source: IndexSet, to destination: Int) {
        upNext.move(fromOffsets: source, toOffset: destination)
        queueChanged()
    }

    /// A queue edit changes the tracks that the engine has not asked for yet, so the sound goes on. Only an edit of
    /// a track that the engine already scheduled loads again from the audible place.
    private func queueChanged() {
        savePosition()
        if let item {
            let songs = Array(engineSongs.prefix(engineBase)) + ([item] + upNext).flatMap { $0.recording.songs }
            if engine.replace(songs.map(\.playbackTrack)) {
                engineSongs = songs
            } else if playback.shouldPlay {
                rebuild()
            } else {
                discardEngine()
            }
        }
        persistQueue()
        prepareAhead()
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
        // Stop cancels all automatic preparation (ADR 0060).
        prepareAhead()
        nowPlayingArtwork = nil
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
            completeRecording(resuming: true)
            return
        }
        switch action {
        case .none: break
        case .pause:
            savePosition()
            engine.pause()
            // Pause cancels the transfer of the next track, unless a download owns it. The engine can already
            // decode that transfer, so Resume then rebuilds from the audible checkpoint.
            if let next = nextAudibleSong(), store.transfers[next.id] != nil, !store.isDownloading(next.id) {
                discardEngine()
            }
            clearWait()
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
        prepareAhead()
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
        case .waiting(let wait): waited(wait)
        case .scheduled(let scheduled):
            refreshSegments()
            if scheduled == movement.map({ $0 + engineBase }) { updateNowPlaying() }
        case .formatChanged:
            // `finished` already moved the checkpoint to the movement that needs the new format. A paused session
            // drops the engine, so that Resume builds the graph for that movement.
            if playback.shouldPlay { rebuild() } else { discardEngine() }
        case .configurationChanged: handle(.configurationChanged)
        case .problem(let text): error = text
        case .failed(let text): playbackFailed(text)
        case .serverFailed(let failure): playbackFailed(nil, trouble: ServerTrouble(engine: failure))
        }
    }

    private func finished(_ absolute: Int) {
        let ended = absolute - engineBase
        guard let item, let movement, ended >= movement, segments.indices.contains(ended) else { return }
        hear(through: (ended, segments[ended]))
        if ended + 1 < item.recording.songs.count {
            checkpoint = (ended + 1, 0)
            position = 0
            self.movement = ended + 1
            history?.begin(item: item, movement: ended + 1, position: 0)
            persistQueue()
            prepareAhead()
        } else {
            recordingCompleted = true
            if playback.shouldPlay { completeRecording() }
        }
    }

    private func completeRecording(resuming: Bool = false) {
        if upNext.isEmpty {
            stop()
            queueEnded = true
        } else if let previous = item {
            history?.endListening()
            engineBase += previous.recording.songs.count
            item = upNext.removeFirst()
            recordingCompleted = false
            checkpoint = (0, 0)
            position = 0
            refreshSegments()
            movement = 0
            if let item { history?.begin(item: item, movement: 0, position: 0) }
            // A final completion can arrive after Pause. Keep the same node and its scheduled successor.
            if resuming {
                do { try engine.resume() } catch { playbackFailed(error.localizedDescription) }
            }
            updateNowPlaying()
            persistQueue()
            prepareAhead()
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
        prepareAhead()
    }

    private func rebuild() {
        guard playback.shouldPlay, let item, let server, let checkpoint else { return }
        discardEngine()
        position = checkpoint.elapsed
        movement = checkpoint.movement
        error = nil
        let store = store
        engineBase = 0
        let songs = ([item] + upNext).flatMap { $0.recording.songs }
        engineSongs = songs
        soundRequested = .now
        engine.load(songs.map(\.playbackTrack), from: checkpoint.movement, offset: checkpoint.elapsed) {
            [weak self] track in
            // A queue edit changes the songs after the load, so the song comes from the current list.
            guard let song = self?.engineSongs.first(where: { $0.id == track.id }) else { throw CancellationError() }
            return try await store.source(for: song, client: server)
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

    /// A server failure pauses quietly: the Library shows its cause in the one server status (ADR 0060).
    private func playbackFailed(_ text: String?, trouble: ServerTrouble? = nil) {
        savePosition()
        _ = playback.handle(.pause)
        discardEngine()
        error = text.map(Localization.shared.translated)
        if let trouble { playbackTrouble = trouble }
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
        engineBase = 0
    }

    private func discardEngine() {
        positionTask?.cancel()
        positionTask = nil
        engine.discard()
        isLoading = false
        clearWait()
    }

    /// Where playback is: the engine's answer, else the last saved place.
    private func located() -> (movement: Int, elapsed: Double)? {
        guard let movement, let checkpoint else { return nil }
        guard let found = engine.position(from: movement + engineBase) else { return checkpoint }
        // Render position can cross several boundaries before the audio-thread completions reach this actor.
        while let item, found.movement >= engineBase + item.recording.songs.count, !upNext.isEmpty,
            playback.shouldPlay
        {
            let last = item.recording.songs.count - 1
            hear(through: (last, segments[last]))
            completeRecording()
        }
        let local = found.movement - engineBase
        guard let item, item.recording.songs.indices.contains(local) else { return checkpoint }
        return (local, found.elapsed)
    }

    private func savePosition() {
        refreshQuality()
        guard let found = located(), let movement, found.movement >= movement else { return }
        refreshSegments()
        if playback.shouldPlay { hear(through: found) }
        checkpoint = (found.movement, found.elapsed)
        if position != found.elapsed { position = found.elapsed }
        refreshSegments()
        if movement != found.movement {
            self.movement = found.movement
            prepareAhead()
        }
    }

    private func refreshSegments() {
        guard let songs = item?.recording.songs else { return }
        let lengths = songs.indices.map { engine.duration(of: $0 + engineBase) ?? Double(songs[$0].duration ?? 0) }
        if lengths != segments { segments = lengths }
    }

    /// ReplayGain off leaves the gain stage out of the graph, so no stage scales the samples.
    private static func wantsGainStage(_ leveling: VolumeLeveling, _ gainStage: (any GainStage)?) -> Bool {
        if let gainStage { return !(gainStage is NoGainStage) }
        return leveling != .off
    }

    /// A graph that is already built keeps its stage. A change of the setting reloads it at the checkpoint.
    private func syncGainStage() {
        let wanted = Self.wantsGainStage(leveling, gainStage)
        engine.useGainStage(wanted)
        guard let path = engine.signalPath, path.gainStage != wanted else { return }
        if playback.shouldPlay { rebuild() } else { discardEngine() }
        // A discarded graph has no path, so the old reason must leave the line now, not at the next play.
        refreshQuality()
    }

    private func refreshQuality() {
        var line: String?
        if showsAudioQuality, let songs = item?.recording.songs, let movement, songs.indices.contains(movement) {
            line = AudioQuality.line(track: songs[movement].playbackTrack, path: engine.signalPath)
        }
        if line != qualityLine { qualityLine = line }
    }

    /// Album and recording gains are the same for each movement, so a change at the movement boundary is not
    /// audible.
    private func applyGain() {
        guard let recording, let movement, recording.songs.indices.contains(movement) else { return engine.setGain(0) }
        let track = recording.songs[movement].playbackTrack
        if let gainStage { return engine.setGain(gainStage.gain(for: track)) }
        // Only the work setting reads the other tracks, so the other settings skip the mapping.
        let group = leveling == .work ? recording.levelGroup(of: movement) : []
        engine.setGain(leveling.gain(for: track, in: group))
    }

    // MARK: Waiting and read-ahead

    /// The engine waits for bytes, or sound started. The line follows after one second (ADR 0060).
    private func waited(_ wait: PlaybackWait?) {
        if wait == nil { playbackTrouble = nil }
        if wait == nil, let requested = soundRequested {
            soundRequested = nil
            if let song = coverSong, store.transfers[song.id] != nil {
                openingSeconds = requested.duration(to: .now) / .seconds(1)
            }
        }
        isLoading = wait != nil
        waiting.update(wait, at: .now)
        refreshLine()
    }

    private func clearWait() {
        waiting.clear()
        refreshLine()
    }

    private func refreshLine() {
        lineTask?.cancel()
        lineTask = nil
        let now = ContinuousClock.now
        let text = waiting.text(at: now)
        if slowLine != text { slowLine = text }
        guard text == nil, let due = waiting.due, due > now else { return }
        lineTask = Task { [weak self] in
            try? await Task.sleep(until: due, clock: .continuous)
            guard !Task.isCancelled else { return }
            self?.refreshLine()
        }
    }

    /// Clear Music removes the files that playback reads. Playback pauses at its place, releases its decoders,
    /// and loads music again only on Play or Resume (ADR 0060).
    private func musicCleared() {
        guard item != nil else { return }
        if playback.wantsPlayback { handle(.pause) }
        savePosition()
        discardEngine()
        prepareAhead()
    }

    /// The track that plays after the audible one, across a recording boundary.
    private func nextAudibleSong() -> Song? {
        guard let item, let movement else { return nil }
        return ReadAhead.plan(item, movement: movement, upNext: upNext, mode: .constrained).first
    }

    /// Prepares the tracks that ADR 0060 allows for the current place in the queue, and cancels the rest.
    /// The current track and the next audible one keep their transfers; a pause or offline mode starts no new one.
    private func prepareAhead() {
        guard let item, let movement, let server, item.recording.songs.indices.contains(movement) else {
            readAheadTask?.cancel()
            readAheadTask = nil
            readAheadPlan = []
            store.pinned = []
            store.wanted = []
            store.playing = nil
            store.cancelTransfers()
            return
        }
        let current = item.recording.songs[movement]
        let preparing = playback.wantsPlayback && dataMode != .offline
        let next = preparing ? ReadAhead.plan(item, movement: movement, upNext: upNext, mode: .constrained) : []
        let plan =
            playback.wantsPlayback ? ReadAhead.plan(item, movement: movement, upNext: upNext, mode: dataMode) : []
        let kept = Set(([current] + next + (preparing ? plan : [])).map(\.id))
        // Only the current track and the next opening keep their files under a full limit (ADR 0060).
        store.pinned = Set(([current] + next).map(\.id))
        store.wanted = kept
        store.playing = current.id
        store.cancelTransfers(except: kept)
        let ids = plan.map(\.id)
        guard ids != readAheadPlan else { return }
        readAheadTask?.cancel()
        readAheadPlan = ids
        guard let opening = plan.first else { return }
        let store = store
        // Starting the current transfer here lets read-ahead yield to it before the engine asks for its bytes.
        let running =
            preparing ? store.playbackTransfer(for: current, client: server) : store.transfers[current.id]
        readAheadTask = Task { [weak self] in
            do {
                if let running { try await self?.prepareOpening(opening, after: running, client: server) }
                for (index, song) in plan.enumerated() {
                    // The rest of the set waits for the current track's bytes.
                    if index > 0, let running { _ = try? await running.finished() }
                    try Task.checkCancellation()
                    _ = try await store.file(for: song, client: server)
                }
            } catch {
                // A failed read-ahead is not a playback error; playback asks for the track again.
            }
        }
    }

    /// The current track has priority. The next opening starts before the current transfer ends only when the
    /// current track would end before the opening is ready, and it waits while current playback has less than
    /// `competitionFloor` playable seconds: decoded audio plus arrived bytes that wait undecoded (ADR 0060).
    private func prepareOpening(_ opening: Song, after running: TrackTransfer, client: any ServerPort) async throws {
        func current() -> Bool { !running.snapshot.complete && store.transfers[running.songID] === running }
        func buffered() -> Double { engine.bufferedSeconds ?? 0 }
        while current() {
            if let movement, segments.indices.contains(movement),
                segments[movement] - position <= openingSeconds + Self.competitionFloor,
                buffered() >= Self.competitionFloor
            {
                break
            }
            try await Task.sleep(for: Self.readAheadPoll)
        }
        guard current(), !store.isOffline(opening) else { return }
        let transfer = store.transfer(for: opening, client: client)
        defer { transfer.hold(false) }
        // Once the engine asked for the opening's source, it reads this shared transfer: a hold would starve the join.
        func engineReads() -> Bool { (engine.requestedMovement ?? -1) > (movement ?? .max) }
        while current(), !engineReads() {
            transfer.hold(buffered() < Self.competitionFloor)
            try await Task.sleep(for: Self.readAheadPoll)
        }
    }

    // MARK: System

    /// The lock screen shows Next as unavailable where the app has none.
    private func updateNextCommand() {
        MPRemoteCommandCenter.shared().nextTrackCommand.isEnabled = hasNext
    }

    /// Fills the lock screen and Control Center.
    private func updateNowPlaying() {
        guard let work, let recording, let movement, segments.indices.contains(movement) else { return }
        let song = recording.songs[movement]
        let text = NowPlayingText(song: song, work: work)
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: text.title,
            MPMediaItemPropertyArtist: text.artist,
            MPMediaItemPropertyAlbumTitle: text.album,
            MPMediaItemPropertyPlaybackDuration: segments[movement],
            MPNowPlayingInfoPropertyElapsedPlaybackTime: position,
            MPNowPlayingInfoPropertyPlaybackRate: isPaused ? 0.0 : 1.0,
        ]
        if let shown = nowPlayingArtwork, shown.key == coverKey?(song) {
            info[MPMediaItemPropertyArtwork] = shown.artwork
        } else {
            nowPlayingArtwork = nil
            loadArtwork(for: song)
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    /// The kept cover of the playing song changed, for example after it arrived from the server. The shown
    /// cover stays until the new one is loaded.
    func coverChanged() {
        guard let song = coverSong, movement != nil else { return }
        artworkLoading = nil
        loadArtwork(for: song)
    }

    /// A track change shows the new cover when it is loaded. Until then, the system players show none, never the
    /// cover of another album.
    private func loadArtwork(for song: Song) {
        guard let key = coverKey?(song), artworkLoading != key, let coverImage else { return }
        artworkLoading = key
        Task { [weak self] in
            let image = await coverImage(song)
            guard let self, self.artworkLoading == key else { return }
            self.artworkLoading = nil
            guard let image, self.coverSong.flatMap({ self.coverKey?($0) }) == key else { return }
            self.nowPlayingArtwork = (key, Self.artwork(image))
            self.updateNowPlaying()
        }
    }

    /// The system asks for the image on a thread of its own, so the handler has no actor (see `remoteHandlers`).
    nonisolated static func artwork(_ image: UIImage) -> MPMediaItemArtwork {
        MPMediaItemArtwork(boundsSize: image.size) { @Sendable _ in image }
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
        notifications.observe(AVAudioSession.didBecomeInactiveNotification) { [weak self] notification in
            guard
                let context = notification.userInfo?[AVAudioSession.deactivationContextKey]
                    as? AVAudioSession.DeactivationContext,
                context.source == .system
            else { return }
            Task { @MainActor in self?.handle(.interruptionBegan) }
        }
        notifications.observe(AVAudioSession.resumptionRecommendationNotification) { [weak self] notification in
            guard
                let context = notification.userInfo?[AVAudioSession.resumptionContextKey]
                    as? AVAudioSession.ResumptionContext
            else { return }
            let shouldResume = context.recommendation == .shouldResume
            Task { @MainActor in self?.handle(.interruptionEnded(shouldResume: shouldResume)) }
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
