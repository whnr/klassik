import AVFoundation
import MediaPlayer
import Observation

/// Plays one recording: all of its movements back to back, without gaps.
/// Each track is downloaded first, because only a whole MP3 file lets the engine cut encoder delay and padding.
@MainActor @Observable
final class Player {
    struct Progress {
        var movement: Int
        var elapsed: Double
        var duration: Double
        var workElapsed: Double
        var workDuration: Double
    }

    private(set) var work: WorkIndex.Work?
    private(set) var recording: WorkIndex.Recording?
    /// The movement that is audible now, as an index into `recording.songs`.
    private(set) var current: Int? {
        didSet { updateNowPlaying() }
    }
    private(set) var isPaused = false
    private(set) var error: String?
    private(set) var isLoading = false

    private var engine: AVAudioEngine?
    private var node: AVAudioPlayerNode?
    private var task: Task<Void, Never>?
    private var client: SubsonicClient?
    /// Completion handlers of an earlier playback must not move the current movement.
    private var generation = 0
    /// Where each scheduled movement sits on the player's timeline, in samples.
    private var segments: [Int: Range<Int64>] = [:]
    private var sampleRate = 44_100.0
    /// A paused node reports no player time, so the position is kept here.
    private var pausedAt: Int64?

    init() {
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

    func play(_ recording: WorkIndex.Recording, of work: WorkIndex.Work, from index: Int = 0, client: SubsonicClient) {
        stop()
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            self.error = error.localizedDescription
            return
        }
        self.work = work
        self.recording = recording
        self.client = client
        current = index
        generation += 1
        let generation = generation
        task = Task { await schedule(recording.songs, from: index, client: client, generation: generation) }
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

    func next() {
        guard let recording, let work, let client, let current, current + 1 < recording.songs.count else { return }
        play(recording, of: work, from: current + 1, client: client)
    }

    /// Goes back to the start of the movement, or to the movement before if it has only just begun.
    func previous() {
        guard let recording, let work, let client, let current else { return }
        let restart = (progress()?.elapsed ?? 0) > 3 || current == 0
        play(recording, of: work, from: restart ? current : current - 1, client: client)
    }

    func stop() {
        generation += 1
        task?.cancel()
        task = nil
        engine?.stop()
        engine = nil
        node = nil
        work = nil
        recording = nil
        current = nil
        isPaused = false
        pausedAt = nil
        isLoading = false
        error = nil
        segments = [:]
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
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
            workElapsed: durations[..<movement].reduce(0, +) + elapsed, workDuration: durations.reduce(0, +))
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
        engine.attach(node)
        self.engine = engine
        self.node = node
        var format: AVAudioFormat?
        var scheduledEnd: Int64 = 0
        do {
            for position in index..<songs.count {
                isLoading = true
                let url = try await Self.download(songs[position], client: client)
                let file = try AVAudioFile(forReading: url)
                isLoading = false
                try Task.checkCancellation()
                let range = Self.playableRange(of: file)
                if format == nil {
                    format = file.processingFormat
                    sampleRate = file.processingFormat.sampleRate
                    engine.connect(node, to: engine.mainMixerNode, format: file.processingFormat)
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
        } else {
            stop()
        }
    }

    /// Fills the lock screen and Control Center.
    private func updateNowPlaying() {
        guard let work, let recording, let current, let progress = progress() else { return }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: recording.songs[current].movementTitle,
            MPMediaItemPropertyArtist: recording.performers,
            MPMediaItemPropertyAlbumTitle: work.title,
            MPMediaItemPropertyPlaybackDuration: progress.duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: progress.elapsed,
            MPNowPlayingInfoPropertyPlaybackRate: isPaused ? 0.0 : 1.0,
        ]
    }

    /// Keeps each track in the caches folder, so playing it again needs no download.
    private static func download(_ song: Song, client: SubsonicClient) async throws -> URL {
        let folder = URL.cachesDirectory.appending(path: "tracks")
        let local = folder.appending(path: "\(song.id).\(song.suffix ?? "mp3")")
        if FileManager.default.fileExists(atPath: local.path()) { return local }
        let (temporary, response) = try await URLSession.shared.download(from: client.streamURL(songID: song.id))
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw SubsonicError.http(status: http.statusCode)
        }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: local)
        try FileManager.default.moveItem(at: temporary, to: local)
        return local
    }

    private static func playableRange(of file: AVAudioFile) -> Range<Int64> {
        guard file.url.pathExtension.lowercased() == "mp3",
              let data = try? Data(contentsOf: file.url, options: .mappedIfSafe),
              let header = MP3GaplessInfo.parse(data) else { return 0..<file.length }
        return header.playableRange(decodedLength: file.length)
    }
}
