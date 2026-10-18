import AVFoundation
import MediaPlayer
import Observation

/// Plays one recording: all of its movements back to back, without gaps.
/// Each track is on the device first, because only a whole MP3 file lets the engine cut encoder delay and padding.
@MainActor @Observable
final class Player {
    struct Progress {
        var movement: Int
        var elapsed: Double
        var duration: Double
        var workElapsed: Double
        var workDuration: Double
        /// The length of each track, for the gaps in the whole-work bar.
        var durations: [Double]
    }

    /// One recording in the queue.
    struct Item: Identifiable, Sendable {
        let id = UUID()
        var work: WorkIndex.Work
        var recording: WorkIndex.Recording
    }

    private(set) var item: Item?
    /// The recordings that play after the current one, in order.
    private(set) var upNext: [Item] = []
    var work: WorkIndex.Work? { item?.work }
    var recording: WorkIndex.Recording? { item?.recording }
    /// The movement that is audible now, as an index into `recording.songs`.
    private(set) var current: Int? {
        didSet {
            applyGain()
            updateNowPlaying()
        }
    }
    private(set) var isPaused = false
    private(set) var error: String?
    private(set) var isLoading = false
    var leveling: VolumeLeveling {
        didSet {
            defaults.set(leveling.rawValue, forKey: Self.levelingKey)
            applyGain()
        }
    }

    private var engine: AVAudioEngine?
    private var node: AVAudioPlayerNode?
    /// Applies the ReplayGain. The node volume cannot go above 1, so it cannot boost.
    private var gain: AVAudioUnitEQ?
    private var task: Task<Void, Never>?
    private var client: SubsonicClient?
    /// Completion handlers of an earlier playback must not move the current movement.
    private var generation = 0
    /// Where each scheduled movement sits on the player's timeline, in samples.
    private var segments: [Int: Range<Int64>] = [:]
    private var sampleRate = 44_100.0
    /// A paused node reports no player time, so the position is kept here.
    private var pausedAt: Int64?
    private let defaults: UserDefaults
    private let store: TrackStore
    private static let levelingKey = "player.volumeLeveling"

    init(store: TrackStore, defaults: UserDefaults = .standard) {
        self.store = store
        self.defaults = defaults
        leveling = defaults.string(forKey: Self.levelingKey).flatMap(VolumeLeveling.init) ?? .album
        let center = MPRemoteCommandCenter.shared()
        // The system calls these on the main thread.
        center.playCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.resume() }
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.pause() }
            return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.togglePause() }
            return .success
        }
        center.nextTrackCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.next() }
            return .success
        }
        center.previousTrackCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.previous() }
            return .success
        }
    }

    /// Plays one recording and empties the queue.
    func play(_ recording: WorkIndex.Recording, of work: WorkIndex.Work, from index: Int = 0, client: SubsonicClient) {
        play([Item(work: work, recording: recording)], client: client, from: index)
    }

    /// Plays the first item and queues the others.
    func play(_ items: [Item], client: SubsonicClient, from index: Int = 0) {
        guard let first = items.first else { return }
        upNext = Array(items.dropFirst())
        start(first, from: index, client: client)
    }

    /// Puts an item at the top of the queue. With nothing playing, it plays at once.
    func playNext(_ item: Item, client: SubsonicClient) {
        guard self.item != nil else { return play([item], client: client) }
        upNext.insert(item, at: 0)
    }

    /// Puts an item at the end of the queue. With nothing playing, it plays at once.
    func addToQueue(_ item: Item, client: SubsonicClient) {
        guard self.item != nil else { return play([item], client: client) }
        upNext.append(item)
    }

    /// Skips to the next recording in the queue.
    func nextWork() {
        guard let client, !upNext.isEmpty else { return }
        start(upNext.removeFirst(), from: 0, client: client)
    }

    /// Plays a queued item and drops the items before it.
    func playQueued(_ id: Item.ID) {
        guard let client, let index = upNext.firstIndex(where: { $0.id == id }) else { return }
        let item = upNext[index]
        upNext.removeFirst(index + 1)
        start(item, from: 0, client: client)
    }

    func removeFromQueue(at offsets: IndexSet) {
        upNext.remove(atOffsets: offsets)
    }

    func moveInQueue(from source: IndexSet, to destination: Int) {
        upNext.move(fromOffsets: source, toOffset: destination)
    }

    private func start(_ item: Item, from index: Int, client: SubsonicClient) {
        reset()
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            self.error = error.localizedDescription
            return
        }
        self.item = item
        self.client = client
        current = index
        generation += 1
        let generation = generation
        task = Task { await schedule(item.recording.songs, from: index, client: client, generation: generation) }
    }

    func togglePause() {
        if isPaused { resume() } else { pause() }
    }

    func pause() {
        guard let node, !isPaused else { return }
        pausedAt = playedSamples()
        node.pause()
        isPaused = true
        updateNowPlaying()
    }

    func resume() {
        guard let node, isPaused else { return }
        node.play()
        isPaused = false
        pausedAt = nil
        updateNowPlaying()
    }

    /// Goes to the next movement, or to the next recording in the queue after the last movement.
    func next() {
        guard let item, let client, let current else { return }
        if current + 1 < item.recording.songs.count {
            start(item, from: current + 1, client: client)
        } else {
            nextWork()
        }
    }

    /// Goes back to the start of the movement, or to the movement before if it has only just begun.
    func previous() {
        guard let item, let client, let current else { return }
        let restart = (progress()?.elapsed ?? 0) > 3 || current == 0
        start(item, from: restart ? current : current - 1, client: client)
    }

    /// Stops playback and empties the queue.
    func stop() {
        reset()
        upNext = []
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    private func reset() {
        generation += 1
        task?.cancel()
        task = nil
        engine?.stop()
        engine = nil
        node = nil
        gain = nil
        item = nil
        current = nil
        isPaused = false
        pausedAt = nil
        isLoading = false
        error = nil
        segments = [:]
    }

    /// The position in the current movement and in the whole work.
    func progress() -> Progress? {
        guard let recording, let current else { return nil }
        var movement = current
        var elapsed = 0.0
        if let sample = playedSamples() {
            if let playing = segments.first(where: { $0.value.contains(sample) }) {
                movement = playing.key
                elapsed = Double(sample - playing.value.lowerBound) / sampleRate
            } else if let range = segments[current], sample >= range.upperBound {
                elapsed = Double(range.count) / sampleRate
            }
        }
        let durations = recording.songs.indices.map { index in
            segments[index].map { Double($0.count) / sampleRate } ?? Double(recording.songs[index].duration ?? 0)
        }
        return Progress(
            movement: movement, elapsed: elapsed, duration: durations[movement],
            workElapsed: durations[..<movement].reduce(0, +) + elapsed, workDuration: durations.reduce(0, +),
            durations: durations)
    }

    private func playedSamples() -> Int64? {
        if let pausedAt { return pausedAt }
        guard let node, let time = node.lastRenderTime, let playerTime = node.playerTime(forNodeTime: time) else {
            return nil
        }
        return playerTime.sampleTime
    }

    private func schedule(_ songs: [Song], from index: Int, client: SubsonicClient, generation: Int) async {
        let engine = AVAudioEngine()
        let node = AVAudioPlayerNode()
        let gain = AVAudioUnitEQ(numberOfBands: 0)
        engine.attach(node)
        engine.attach(gain)
        self.engine = engine
        self.node = node
        self.gain = gain
        applyGain()
        var format: AVAudioFormat?
        var scheduledEnd: Int64 = 0
        do {
            for position in index..<songs.count {
                isLoading = true
                let url = try await store.file(for: songs[position], client: client)
                let file = try AVAudioFile(forReading: url)
                isLoading = false
                try Task.checkCancellation()
                let range = Self.playableRange(of: file)
                if format == nil {
                    format = file.processingFormat
                    sampleRate = file.processingFormat.sampleRate
                    engine.connect(node, to: gain, format: file.processingFormat)
                    engine.connect(gain, to: engine.mainMixerNode, format: file.processingFormat)
                    try engine.start()
                    node.play()
                } else if file.processingFormat != format {
                    error = "Movement \(position + 1) has a different audio format."
                    return
                }
                // A slow download leaves the player idle; the movement then starts at the current position.
                let start = max(scheduledEnd, playedSamples() ?? 0)
                scheduledEnd = start + Int64(range.count)
                segments[position] = start..<scheduledEnd
                node.scheduleSegment(
                    file, startingFrame: range.lowerBound, frameCount: AVAudioFrameCount(range.count), at: nil,
                    completionCallbackType: .dataPlayedBack
                ) { @Sendable [weak self] _ in
                    // The engine calls this on its own thread.
                    Task { @MainActor in self?.finished(position, generation: generation) }
                }
                if position == current { updateNowPlaying() }
            }
        } catch {
            isLoading = false
            if !Task.isCancelled { self.error = error.localizedDescription }
        }
    }

    private func finished(_ position: Int, generation: Int) {
        guard generation == self.generation, let recording else { return }
        if position + 1 < recording.songs.count {
            current = position + 1
        } else if !upNext.isEmpty {
            nextWork()
        } else {
            stop()
        }
    }

    /// Album gains are the same for each movement, so a change at the movement boundary is not audible.
    private func applyGain() {
        guard let gain else { return }
        gain.globalGain = current.flatMap { index in recording.map { leveling.gain(for: $0.songs[index]) } } ?? 0
    }

    /// Fills the lock screen and Control Center.
    private func updateNowPlaying() {
        guard let work, let recording, let current, let progress = progress() else { return }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: recording.title(of: recording.songs[current]),
            MPMediaItemPropertyArtist: recording.performers,
            MPMediaItemPropertyAlbumTitle: work.title,
            MPMediaItemPropertyPlaybackDuration: progress.duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: progress.elapsed,
            MPNowPlayingInfoPropertyPlaybackRate: isPaused ? 0.0 : 1.0,
        ]
    }

    private static func playableRange(of file: AVAudioFile) -> Range<Int64> {
        guard file.url.pathExtension.lowercased() == "mp3",
            let data = try? Data(contentsOf: file.url, options: .mappedIfSafe),
            let header = MP3GaplessInfo.parse(data)
        else { return 0..<file.length }
        return header.playableRange(decodedLength: file.length)
    }
}
