import AVFoundation
import Observation

/// Plays one recording: all of its movements back to back, without gaps.
/// Each track is downloaded first, because only a whole MP3 file lets the engine cut encoder delay and padding.
@MainActor @Observable
final class Player {
    private(set) var work: WorkIndex.Work?
    private(set) var recording: WorkIndex.Recording?
    /// The movement that is audible now, as an index into `recording.songs`.
    private(set) var current: Int?
    private(set) var isPaused = false
    private(set) var error: String?
    private(set) var isLoading = false

    private var engine: AVAudioEngine?
    private var node: AVAudioPlayerNode?
    private var task: Task<Void, Never>?
    /// Completion handlers of an earlier playback must not move the current movement.
    private var generation = 0

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
        current = index
        generation += 1
        let generation = generation
        task = Task { await schedule(recording.songs, from: index, client: client, generation: generation) }
    }

    func togglePause() {
        guard let node else { return }
        if isPaused { node.play() } else { node.pause() }
        isPaused.toggle()
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
        isLoading = false
        error = nil
    }

    private func schedule(_ songs: [Song], from index: Int, client: SubsonicClient, generation: Int) async {
        let engine = AVAudioEngine()
        let node = AVAudioPlayerNode()
        engine.attach(node)
        self.engine = engine
        self.node = node
        var format: AVAudioFormat?
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
                    engine.connect(node, to: engine.mainMixerNode, format: file.processingFormat)
                    try engine.start()
                    node.play()
                } else if file.processingFormat != format {
                    error = "Movement \(position + 1) has a different audio format."
                    return
                }
                node.scheduleSegment(
                    file, startingFrame: range.lowerBound, frameCount: AVAudioFrameCount(range.count), at: nil,
                    completionCallbackType: .dataPlayedBack
                ) { @Sendable [weak self] _ in
                    // The engine calls this on its own thread.
                    Task { @MainActor in self?.finished(position, generation: generation) }
                }
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
