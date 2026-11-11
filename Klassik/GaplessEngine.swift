import AVFoundation

/// Plays the movements of one recording back to back, without gaps.
/// Each track is on the device first, because only a whole MP3 file lets the engine cut encoder delay and padding.
@MainActor
final class GaplessEngine: PlaybackEngine {
    typealias CompletionDelivery = @Sendable (@escaping @MainActor @Sendable () -> Void) -> Void

    var onEvent: (@MainActor (PlaybackEngineEvent) -> Void)?
    var isRunning: Bool { engine?.isRunning == true && node != nil }

    private var engine: AVAudioEngine?
    private var node: AVAudioPlayerNode?
    /// Applies the ReplayGain. The node volume cannot go above 1, so it cannot boost.
    private var gain: AVAudioUnitEQ?
    private var decibels: Float = 0
    private var engineNotifications: PlaybackNotifications?
    private var task: Task<Void, Never>?
    /// Completion handlers of an earlier load must not reach the session.
    private var generation = 0
    /// Whether the session wants sound. A load that finishes after a pause must stay silent.
    private var playing = false
    /// Where each scheduled movement sits on the player's timeline, in samples.
    private var segments: [Int: Range<Int64>] = [:]
    private var sampleRate = 44_100.0
    /// A paused node reports no player time, so the position is kept here.
    private var pausedAt: Int64?
    private let deliverCompletion: CompletionDelivery

    init(
        deliverCompletion: @escaping CompletionDelivery = { completion in
            Task { @MainActor in completion() }
        }
    ) {
        self.deliverCompletion = deliverCompletion
    }

    func load(_ songs: [Song], from movement: Int, offset: Double, file: @escaping PlaybackFileSource) {
        discard()
        playing = true
        let generation = generation
        task = Task {
            await schedule(songs, from: movement, offset: offset, file: file, generation: generation)
        }
    }

    func pause() {
        pausedAt = playedSamples()
        node?.pause()
        playing = false
    }

    func resume() throws {
        guard let node else { return }
        try Self.activateSession()
        node.play()
        pausedAt = nil
        playing = true
    }

    func discard() {
        // Invalidate callbacks before stopping: node teardown also calls completion handlers.
        generation += 1
        task?.cancel()
        task = nil
        engineNotifications = nil
        engine?.stop()
        engine = nil
        node = nil
        gain = nil
        pausedAt = nil
        segments = [:]
        playing = false
    }

    func setGain(_ decibels: Float) {
        self.decibels = decibels
        gain?.globalGain = decibels
    }

    func position(from movement: Int) -> (movement: Int, elapsed: Double)? {
        guard let sample = playedSamples(), let range = segments[movement] else { return nil }
        // Completion can arrive before the render clock reflects the next movement.
        if let playing = segments.first(where: { $0.key >= movement && $0.value.contains(sample) }) {
            return (playing.key, Double(sample - playing.value.lowerBound) / sampleRate)
        }
        if sample >= range.upperBound { return (movement, Double(range.count) / sampleRate) }
        return nil
    }

    func duration(of movement: Int) -> Double? {
        segments[movement].map { Double($0.count) / sampleRate }
    }

    private static func activateSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default)
        try session.setActive(true)
    }

    private func playedSamples() -> Int64? {
        if let pausedAt { return pausedAt }
        guard engine?.isRunning == true, let node, let time = node.lastRenderTime,
            let playerTime = node.playerTime(forNodeTime: time)
        else {
            return nil
        }
        return playerTime.sampleTime
    }

    private func schedule(
        _ songs: [Song], from index: Int, offset: Double, file source: PlaybackFileSource, generation: Int
    ) async {
        let engine = AVAudioEngine()
        let node = AVAudioPlayerNode()
        let gain = AVAudioUnitEQ(numberOfBands: 0)
        engine.attach(node)
        engine.attach(gain)
        self.engine = engine
        self.node = node
        self.gain = gain
        gain.globalGain = decibels
        let observers = PlaybackNotifications()
        observers.observe(.AVAudioEngineConfigurationChange, object: engine) { [weak self] _ in
            // The engine posts from an internal queue; teardown must run after that callback returns.
            Task { @MainActor in
                guard let self, generation == self.generation else { return }
                self.onEvent?(.configurationChanged)
            }
        }
        engineNotifications = observers
        var format: AVAudioFormat?
        var scheduledEnd: Int64 = 0
        do {
            for position in index..<songs.count {
                onEvent?(.loading(true))
                let url = try await source(songs[position])
                try Task.checkCancellation()
                guard generation == self.generation else { return }
                let file = try AVAudioFile(forReading: url)
                onEvent?(.loading(false))
                let playable = Self.playableRange(of: file)
                let range =
                    position == index
                    ? Self.seekRange(playable, to: offset, sampleRate: file.processingFormat.sampleRate) : playable
                if format == nil {
                    format = file.processingFormat
                    sampleRate = file.processingFormat.sampleRate
                    engine.connect(node, to: gain, format: file.processingFormat)
                    engine.connect(gain, to: engine.mainMixerNode, format: file.processingFormat)
                    guard playing else { return }
                    try Self.activateSession()
                    try engine.start()
                } else if file.processingFormat != format {
                    onEvent?(.problem("Movement \(position + 1) has a different audio format."))
                    return
                }
                // A slow download leaves the player idle; the movement then starts at the current position.
                let start = max(scheduledEnd, playedSamples() ?? 0)
                scheduledEnd = start + Int64(range.count)
                // The segment covers the whole movement, so that elapsed time counts from the movement's start.
                segments[position] = (start - (range.lowerBound - playable.lowerBound))..<scheduledEnd
                let deliverCompletion = deliverCompletion
                node.scheduleSegment(
                    file, startingFrame: range.lowerBound, frameCount: AVAudioFrameCount(range.count), at: nil,
                    completionCallbackType: .dataPlayedBack
                ) { @Sendable [weak self] _ in
                    // The engine calls this on its own thread.
                    deliverCompletion { [weak self] in self?.finished(position, generation: generation) }
                }
                if playing && !node.isPlaying { node.play() }
                onEvent?(.scheduled(position))
            }
        } catch {
            guard generation == self.generation, !Task.isCancelled else { return }
            onEvent?(.failed(error.localizedDescription))
        }
    }

    private func finished(_ position: Int, generation: Int) {
        guard generation == self.generation, engine?.isRunning == true else { return }
        onEvent?(.movementEnded(position))
    }

    /// The part of a movement that plays after a seek. It keeps at least one frame, so the movement still ends
    /// and the next one follows.
    nonisolated static func seekRange(_ range: Range<Int64>, to seconds: Double, sampleRate: Double) -> Range<Int64> {
        let frame = seconds.isFinite ? Int64((seconds * sampleRate).rounded()) : 0
        let skip = min(max(frame, 0), max(Int64(range.count) - 1, 0))
        return (range.lowerBound + skip)..<range.upperBound
    }

    private static func playableRange(of file: AVAudioFile) -> Range<Int64> {
        guard file.url.pathExtension.lowercased() == "mp3",
            let data = try? Data(contentsOf: file.url, options: .mappedIfSafe),
            let header = MP3GaplessInfo.parse(data)
        else { return 0..<file.length }
        return header.playableRange(decodedLength: file.length)
    }
}
