import AVFoundation

/// Plays the queued recordings back to back, without gaps, on one node timeline.
/// A complete file plays as a segment. A track that is still arriving plays from decoded buffers, as soon as the
/// start threshold allows (ADR 0060). Both cut MP3 and M4A encoder delay and padding in decoded sample coordinates.
/// The graph runs at the sample rate and channel count of its first track and never resamples. A track of another
/// format ends the load: the session reloads from it once the track before it has played out.
@MainActor
public final class GaplessEngine: PlaybackEngine {
    public typealias CompletionDelivery = @Sendable (@escaping @MainActor @Sendable () -> Void) -> Void

    /// Each decoded buffer holds this much audio.
    nonisolated static let chunkSeconds = 0.25
    /// The decoded audio that may wait on the node ahead of the render position (ADR 0060).
    nonisolated static let aheadSeconds = 2.0
    /// The most decoded audio on the node: the decoder stops two chunks below `aheadSeconds` and adds one chunk.
    nonisolated static let decodedPeak = aheadSeconds - chunkSeconds
    static let watchInterval = Duration.milliseconds(100)

    public var onEvent: (@MainActor (PlaybackEngineEvent) -> Void)?
    public var isRunning: Bool { engine?.isRunning == true && node != nil }
    /// Decoded audio on the node ahead of the render position. It stays below `decodedPeak`.
    var decodedSeconds: Double? {
        guard started, let played = playedSamples() else { return nil }
        return Double(max(scheduledEnd - played, 0)) / sampleRate
    }
    /// Playable audio ahead of the render position (ADR 0060): decoded audio, the buffer that waits off the node,
    /// and the arrived bytes after the decoder's place in the file.
    public var bufferedSeconds: Double? {
        guard let decoded = decodedSeconds else { return nil }
        guard let stream else { return decoded }
        let encoded = Double(stream.transfer.bufferedBytes(from: consumed)) * 8 / stream.bitrate
        return decoded + Double(heldFrames) / sampleRate + encoded
    }

    public var requestedMovement: Int? { task == nil ? nil : requested }

    private var engine: AVAudioEngine?
    private var node: AVAudioPlayerNode?
    /// Applies the ReplayGain. The node volume cannot go above 1, so it cannot boost.
    private var gain: AVAudioUnitEQ?
    private var decibels: Float = 0
    private var engineNotifications: PlaybackNotifications?
    private var task: Task<Void, Never>?
    private var watcher: Task<Void, Never>?
    private var activation: Task<Void, Never>?
    /// The fade stage of this graph. It ramps the samples before the gain node and the mixer.
    private var fade: FadeControl?
    /// The wait for a fade-out to end before the node stops. A start or a discard replaces it.
    private var halting: Task<Void, Never>?
    /// True from the start of a fade-out until a start ramps the sound up again.
    private var silenced = false
    /// The length of every fade, in seconds. A change takes effect at the next fade, also on a running engine.
    public var fadeSeconds: Double
    /// Completion handlers of an earlier load must not reach the session.
    private var generation = 0
    /// Whether the session wants sound. A load that finishes after a pause must stay silent.
    private var playing = false
    /// Where each scheduled movement sits on the player's timeline, in samples.
    private var timeline = AudioTimeline()
    private var sampleRate = 44_100.0
    private var format: AVAudioFormat?
    /// The track that needs another graph format than the one that plays. Nothing after the track before it is scheduled.
    private var formatBreak: Int?
    /// The last track that played out, so that a format break found late still reports.
    private var lastEnded: Int?
    /// The sample rate that the audio session reported after it activated for this load. The system can differ from
    /// the rate that the engine asked for (Apple QA1631), so the host reads the answer here.
    public private(set) var activatedSampleRate: Double?
    /// The sample rate of the audio on the engine's graph. It is the rate of the file, never a converted rate.
    public var sourceSampleRate: Double? { format?.sampleRate }
    public var sourceChannelCount: Int? { format.map { Int($0.channelCount) } }
    /// A paused node reports no player time, so the position is kept here.
    private(set) var pausedAt: Int64?
    /// The end of the scheduled audio on the node timeline.
    private var scheduledEnd: Int64 = 0
    /// True once the first sound of this load was allowed.
    private var started = false
    /// True while the node waits, paused, for bytes that did not arrive in time.
    private var starved = false
    /// True until the last buffer of the load is on the node.
    private var decoding = false
    /// The transfer that the engine reads now, and the bitrate that it needs.
    private var stream: (transfer: TrackTransfer, bitrate: Double)?
    /// The decoder's place in the file of `stream`.
    private var consumed: Int64 = 0
    /// The decoded frames that wait off the node, so that the last buffer of a track carries its end callback.
    private var heldFrames: AVAudioFrameCount = 0
    /// The tracks of this load. A queue edit replaces the ones that the load has not asked for yet.
    private var songs: [PlaybackTrack] = []
    /// The last track that this load asked a source for.
    private var requested = -1
    /// The open of the track after the one that decodes. A join then needs no open inside the last `aheadSeconds`.
    private var opening: (position: Int, id: String, task: Task<PlaybackSource, Error>)?
    private var opener: PlaybackFileSource?
    /// The first track of this load. `mayRequest` counts from it.
    private var firstIndex = 0
    private var reported: PlaybackWait?
    /// Stops the blocked reads of the worker when a load ends.
    private var cancelled = CancelFlag()
    private var worker: DispatchQueue?
    private let deliverCompletion: CompletionDelivery
    /// Internal so that the app's tests can check which mapper the app passes.
    let failureMapper: any PlaybackFailureMapper
    /// False builds a signal path without the gain node, for a host that applies no ReplayGain.
    private let gainNode: Bool
    private let rendered: (@Sendable (AVReadOnlyAudioPCMBuffer) -> Void)?
    /// Tests only. The engine renders offline and only audio that is already on the node, so the output does not
    /// depend on runner load.
    private let manualRendering: Bool
    private var pump: Task<Void, Never>?
    /// An offline engine has no output device to play back to, so it reports data as consumed.
    private var completionType: AVAudioPlayerNodeCompletionCallbackType {
        manualRendering ? .dataConsumed : .dataPlayedBack
    }
    /// The frames that the pump rendered. An offline node has no valid render time, so this is its position.
    private var pumped: Int64 = 0

    public init(
        deliverCompletion: @escaping CompletionDelivery = { completion in
            Task { @MainActor in completion() }
        },
        rendered: (@Sendable (AVReadOnlyAudioPCMBuffer) -> Void)? = nil,
        manualRendering: Bool = false,
        failureMapper: any PlaybackFailureMapper = TransferFailureMapper(),
        gainNode: Bool = true,
        fadeSeconds: Double = 0.1
    ) {
        self.fadeSeconds = fadeSeconds
        self.deliverCompletion = deliverCompletion
        self.failureMapper = failureMapper
        self.gainNode = gainNode
        self.rendered = rendered
        self.manualRendering = manualRendering
    }

    public func load(_ songs: [PlaybackTrack], from movement: Int, offset: Double, file: @escaping PlaybackFileSource) {
        discard()
        self.songs = songs
        // The track at the load's start is fixed before the scheduler asks for it.
        requested = movement
        playing = true
        let generation = generation
        cancelled = CancelFlag()
        worker = DispatchQueue(label: "de.whnr.klassik.decoder", qos: .default)
        task = Task {
            await schedule(from: movement, offset: offset, file: file, generation: generation)
        }
    }

    public func pause() {
        playing = false
        guard let node, node.isPlaying else {
            pausedAt = playedSamples()
            node?.pause()
            return report()
        }
        // The node keeps playing until the fade-out ends, so the stop lands on silence.
        let generation = generation
        halt(frames: fadeFrames) { [weak self] in
            guard let self, generation == self.generation, !self.playing else { return }
            self.pausedAt = self.playedSamples()
            node.pause()
        }
        report()
    }

    public func resume() throws {
        playing = true
        // Before the first sound and during a refill, the scheduler starts the node when enough audio waits.
        guard started && !starved, let node else { return report() }
        let generation = generation
        activation?.cancel()
        activation = Task {
            do {
                activatedSampleRate = try await Self.activateSession(preferredRate: format?.sampleRate)
                try check(generation)
                guard playing else { return }
                try start(node)
                pausedAt = nil
            } catch {
                guard generation == self.generation, !Task.isCancelled else { return }
                onEvent?(.failed(error.localizedDescription))
            }
        }
    }

    /// Puts the engine in the state of a load that sounds on this graph, for tests that drive the node without a
    /// decoder.
    func adopt(
        _ engine: AVAudioEngine, _ node: AVAudioPlayerNode, started: Bool, fade: FadeControl? = nil,
        scheduledEnd: Int64 = 0, decoding: Bool = false
    ) {
        self.engine = engine
        self.node = node
        self.started = started
        self.fade = fade
        self.scheduledEnd = scheduledEnd
        self.decoding = decoding
        playing = true
    }

    public func replace(_ songs: [PlaybackTrack]) -> Bool {
        let fixed = requested + 1
        guard task != nil, songs.count >= fixed, songs.prefix(fixed).map(\.id) == self.songs.prefix(fixed).map(\.id)
        else { return false }
        self.songs = songs
        return true
    }

    public func discard() {
        // Invalidate callbacks before stopping: node teardown also calls completion handlers.
        generation += 1
        cancelled.set()
        worker = nil
        task?.cancel()
        task = nil
        watcher?.cancel()
        watcher = nil
        engineNotifications = nil
        activation?.cancel()
        activation = nil
        pump?.cancel()
        pump = nil
        pumped = 0
        halting?.cancel()
        halting = nil
        retire(engine, node, fade)
        fade = nil
        silenced = false
        engine = nil
        node = nil
        gain = nil
        format = nil
        pausedAt = nil
        timeline = AudioTimeline()
        formatBreak = nil
        lastEnded = nil
        activatedSampleRate = nil
        scheduledEnd = 0
        started = false
        starved = false
        decoding = false
        stream = nil
        consumed = 0
        heldFrames = 0
        songs = []
        requested = -1
        opening?.task.cancel()
        opening = nil
        opener = nil
        reported = nil
        playing = false
    }

    public func setGain(_ decibels: Float) {
        self.decibels = decibels
        gain?.globalGain = decibels
    }

    public func position(from movement: Int) -> (movement: Int, elapsed: Double)? {
        guard let sample = playedSamples(), let found = timeline.position(at: sample, from: movement) else {
            return nil
        }
        return (found.movement, Double(found.frame) / sampleRate)
    }

    public func duration(of movement: Int) -> Double? {
        timeline.length(movement).map { Double($0) / sampleRate }
    }

    /// Asks for `rate` and activates the session. The request is a hint, so the caller reads the rate back.
    nonisolated private static func activateSession(preferredRate: Double? = nil) async throws -> Double {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default)
        // A refused rate leaves the system rate in place, and iOS then converts. That must not stop playback.
        if let preferredRate { try? session.setPreferredSampleRate(preferredRate) }
        guard try await session.activate() else { throw CancellationError() }
        return session.sampleRate
    }

    private func playedSamples() -> Int64? {
        if let pausedAt { return pausedAt }
        if manualRendering { return engine == nil ? nil : pumped }
        guard engine?.isRunning == true, let node, let time = node.lastRenderTime,
            let playerTime = node.playerTime(forNodeTime: time)
        else {
            return nil
        }
        return playerTime.sampleTime
    }

    private func schedule(
        from index: Int, offset: Double, file source: @escaping PlaybackFileSource, generation: Int
    ) async {
        // A `discard()` can run between `load` and the start of this task. Then no state may change.
        guard generation == self.generation, !Task.isCancelled else { return }
        let engine = AVAudioEngine()
        let node = AVAudioPlayerNode()
        let gain = gainNode ? AVAudioUnitEQ(numberOfBands: 0) : nil
        engine.attach(node)
        if let gain { engine.attach(gain) }
        self.engine = engine
        self.node = node
        self.gain = gain
        gain?.globalGain = decibels
        let observers = PlaybackNotifications()
        observers.observe(.AVAudioEngineConfigurationChange, object: engine) { [weak self] _ in
            // The engine posts from an internal queue; teardown must run after that callback returns.
            Task { @MainActor in
                guard let self, generation == self.generation else { return }
                self.onEvent?(.configurationChanged)
            }
        }
        engineNotifications = observers
        decoding = true
        opener = source
        firstIndex = index
        watch(generation)
        do {
            var position = index
            while true {
                // After the last track, the load waits for a queue edit.
                while !mayRequest(position, from: index) {
                    if position >= songs.count { decoding = false }
                    try await Task.sleep(for: Self.watchInterval)
                    try check(generation)
                }
                decoding = true
                requested = position
                let song = songs[position]
                let seconds = position == index ? offset : 0
                report()
                let track: PlaybackSource
                if let opening, opening.position == position, opening.id == song.id {
                    self.opening = nil
                    track = try await opening.task.value
                } else {
                    opening?.task.cancel()
                    opening = nil
                    track = try await source(song)
                }
                try check(generation)
                switch track {
                case .file(let url):
                    guard try await scheduleFile(url, position: position, offset: seconds, generation: generation)
                    else {
                        return
                    }
                case .stream(let transfer):
                    guard
                        try await scheduleStream(
                            transfer, song: song, position: position, offset: seconds, generation: generation)
                    else { return }
                }
                onEvent?(.scheduled(position))
                position += 1
            }
        } catch {
            opening?.task.cancel()
            opening = nil
            guard generation == self.generation, !Task.isCancelled else { return }
            if let failure = failureMapper.serverFailure(for: error) {
                onEvent?(.serverFailed(failure))
            } else {
                onEvent?(.failed(error.localizedDescription))
            }
        }
    }

    /// Only the audible track and its immediate successor may request playback bytes.
    private func mayRequest(_ position: Int, from index: Int) -> Bool {
        playing && position < songs.count && (position <= index + 1 || audibleMovement() >= position - 1)
    }

    /// Opens the next track while this one still decodes, once this one has filled its lookahead. The open of a
    /// recording can take longer than the audio that waits on the node, and a dry node is a gap in a continuous join.
    /// The same `mayRequest` rule applies, so only the audible track's successor ever opens. `decoded` counts the
    /// frames that the decoder produced and the frames that the arrived bytes still hold: a decoder reads a whole
    /// chunk, so it can wait for bytes that the lookahead does not need yet.
    private func openNext(after position: Int, decoded: Int64, ahead: Int64) {
        let next = position + 1
        guard decoded >= ahead, opening?.position != next, mayRequest(next, from: firstIndex),
            let opener, songs.indices.contains(next)
        else { return }
        let song = songs[next]
        opening = (next, song.id, Task { try await opener(song) })
    }

    /// The frames that the bytes after the decoder's place hold, at the bitrate of the stream.
    private func arrivedFrames(_ transfer: TrackTransfer, rate: Double) -> Int64 {
        guard let stream, stream.bitrate > 0 else { return 0 }
        return Int64(Double(transfer.bufferedBytes(from: consumed)) * 8 / stream.bitrate * rate)
    }

    private func audibleMovement() -> Int {
        let sample = playedSamples() ?? 0
        return timeline.position(at: sample, from: 0)?.movement ?? -1
    }

    private func check(_ generation: Int) throws {
        guard generation == self.generation, !Task.isCancelled else { throw CancellationError() }
    }

    /// Whether a track fits the graph.
    private enum Link {
        case ready
        /// The track has another sample rate or channel count. The load ends before it.
        case other
        case gone
    }

    /// The first track sets the graph: its own sample rate and channel count, never converted by the app. The
    /// session is asked for that rate before the graph connects, so that the output node reads the rate that the
    /// hardware runs at (ADR 0060).
    private func connect(_ incoming: AVAudioFormat, generation: Int) async throws -> Link {
        guard let engine, let node else { return .gone }
        if let format {
            return format.sampleRate == incoming.sampleRate && format.channelCount == incoming.channelCount
                ? .ready : .other
        }
        activatedSampleRate = try await Self.activateSession(preferredRate: incoming.sampleRate)
        try check(generation)
        format = incoming
        sampleRate = incoming.sampleRate
        // The fade stage comes first, so that a ramp covers the samples before any other stage. The last node before
        // the mixer is the gain node, or the fade stage when the host builds no gain node.
        var last: AVAudioNode = node
        if let made = FadeAudioUnit.make() {
            engine.attach(made.stage)
            try engine.connectNode(node, to: made.stage, format: incoming)
            fade = made.control
            last = made.stage
        }
        if let gain {
            try engine.connectNode(last, to: gain, format: incoming)
            last = gain
        }
        try engine.connectNode(last, to: engine.mainMixerNode, format: incoming)
        if manualRendering {
            try engine.enableManualRenderingMode(.offline, format: incoming, maximumFrameCount: 1_024)
        }
        if let rendered {
            try last.installAudioTap(
                onBus: 0, bufferSize: AVAudioFrameCount(incoming.sampleRate * Self.chunkSeconds), format: incoming
            ) { buffer, _ in rendered(buffer) }
        }
        try engine.start()
        if manualRendering { startPump(engine, node: node, generation: generation) }
        return .ready
    }

    /// The track at `position` needs another graph format. Nothing after the track before it is scheduled, so that
    /// track plays to its last sample. Then the engine reports the break and the session reloads from `position`.
    private func breakFormat(at position: Int) {
        formatBreak = position
        decoding = false
        opening?.task.cancel()
        opening = nil
        reportFormatBreak()
    }

    private func reportFormatBreak() {
        guard let formatBreak, lastEnded == formatBreak - 1 else { return }
        self.formatBreak = nil
        onEvent?(.formatChanged(formatBreak))
    }

    /// Renders the audio that waits on the node and never more, so a slow decoder cannot put silence in the output.
    private func startPump(_ engine: AVAudioEngine, node: AVAudioPlayerNode, generation: Int) {
        let format = engine.manualRenderingFormat
        let capacity = engine.manualRenderingMaximumFrameCount
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return }
        pump = Task { [weak self] in
            var tailed = false
            while !Task.isCancelled {
                guard let self, generation == self.generation else { return }
                var waiting = self.scheduledEnd - (self.playedSamples() ?? 0)
                // The node reports the end of its last buffer on the render pass after it. One silent block
                // follows the final audio.
                if waiting <= 0, !self.decoding, !tailed, node.isPlaying {
                    tailed = true
                    waiting = Int64(buffer.frameCapacity)
                }
                guard node.isPlaying, waiting > 0 else {
                    try? await Task.sleep(for: .milliseconds(1))
                    continue
                }
                let frames = AVAudioFrameCount(min(waiting, Int64(buffer.frameCapacity)))
                guard (try? engine.renderOffline(frames, to: buffer)) != nil else { return }
                self.pumped += Int64(frames)
                await Task.yield()
            }
        }
    }

    private func scheduleFile(_ url: URL, position: Int, offset: Double, generation: Int) async throws -> Bool {
        let file = try AVAudioFile(forReading: url)
        switch try await connect(file.processingFormat, generation: generation) {
        case .gone: return false
        case .other:
            breakFormat(at: position)
            return false
        case .ready: break
        }
        guard let node else { return false }
        stream = nil
        let playable = Self.playableRange(of: file)
        let range =
            offset > 0 ? Self.seekRange(playable, to: offset, sampleRate: file.processingFormat.sampleRate) : playable
        // A slow download leaves the player idle; the movement then starts at the current position.
        timeline.declare(position, frames: Int64(playable.count))
        let skipped = range.lowerBound - playable.lowerBound
        let placed = timeline.append(
            position, audio: skipped..<(skipped + Int64(range.count)), rendered: playedSamples() ?? 0)
        scheduledEnd = placed.upperBound
        node.scheduleSegment(
            file, startingFrame: range.lowerBound, frameCount: AVAudioFrameCount(range.count),
            at: AVAudioTime(sampleTime: placed.lowerBound, atRate: sampleRate),
            completionCallbackType: completionType, completionHandler: ended(position, generation: generation))
        try sound()
        return true
    }

    /// Decodes a track while it arrives, and keeps at most `aheadSeconds` of it on the node.
    private func scheduleStream(
        _ transfer: TrackTransfer, song: PlaybackTrack, position: Int, offset: Double, generation: Int
    ) async throws -> Bool {
        stream = (transfer, AudioBitrate.initial(song))
        consumed = 0
        heldFrames = 0
        let flag = cancelled
        let suffix = song.suffix ?? ""
        let decoder: StreamDecoder
        do {
            decoder = try await work {
                try Box(StreamDecoder(transfer: transfer, suffix: suffix, cancelled: flag))
            }.value
        } catch {
            guard error is StreamDecoder.Failure || (error as? TrackTransfer.Failure) == .requiresCompleteFile else {
                throw error
            }
            // A decoder or metadata range that prevents early playback requires a complete file (ADR 0060).
            let url = try await transfer.finished()
            try check(generation)
            return try await scheduleFile(url, position: position, offset: offset, generation: generation)
        }
        try check(generation)
        switch try await connect(decoder.format, generation: generation) {
        case .gone: return false
        case .other:
            breakFormat(at: position)
            return false
        case .ready: break
        }
        let sourceRate = decoder.sampleRate
        let playable = decoder.playable ?? 0..<Int64(Double(song.duration ?? 0) * sourceRate)
        let selected = offset > 0 ? Self.seekRange(playable, to: offset, sampleRate: sourceRate) : playable
        let skipped = selected.lowerBound - playable.lowerBound
        if skipped > 0 { _ = try await work { try Box(decoder.seek(to: selected.lowerBound)) } }
        let rate = sampleRate
        let expected = decoder.playable.map { _ in Int64(selected.count) }
        let reader = PCMReader(format: decoder.format, frames: expected) { try decoder.read(frames: $0) }
        var emitted = skipped
        let origin = emitted
        let fullLength = emitted + (expected ?? Int64(playable.count))
        timeline.declare(position, frames: fullLength)
        let ahead = Int64((Self.aheadSeconds - Self.chunkSeconds * 2) * rate)
        // One buffer waits off the node, so that the last buffer of the track carries the end callback.
        var held: AVAudioPCMBuffer?
        var heldStart = emitted
        reading: while true {
            openNext(after: position, decoded: emitted - origin + arrivedFrames(transfer, rate: rate), ahead: ahead)
            if scheduledEnd - (playedSamples() ?? 0) >= ahead {
                try startIfReady(transfer, remaining: Double(fullLength - emitted) / rate)
                try await Task.sleep(for: Self.watchInterval)
                try check(generation)
                continue
            }
            let decoded = try await work { try Decoded(decoder, reader: reader) }
            try check(generation)
            stream = (transfer, AudioBitrate.current(song, observed: decoded.bitrate))
            consumed = decoded.consumed
            switch decoded.output {
            case .audio(let buffer):
                if let held {
                    enqueue(held, position: position, audioStart: heldStart, last: false, generation: generation)
                }
                held = buffer
                heldStart = emitted
                emitted += Int64(buffer.frameLength)
                heldFrames = buffer.frameLength
                try startIfReady(transfer, remaining: Double(fullLength - emitted) / rate)
            case .end:
                guard let held else { throw StreamDecoder.Failure.status(kAudioFileEndOfFileError) }
                enqueue(held, position: position, audioStart: heldStart, last: true, generation: generation)
                // The decoder knows the exact length now, also where the file declared none.
                timeline.declare(position, frames: emitted)
                break reading
            }
        }
        heldFrames = 0
        try sound()
        return true
    }

    private func enqueue(
        _ buffer: AVAudioPCMBuffer, position: Int, audioStart: Int64, last: Bool, generation: Int
    ) {
        guard let node else { return }
        let placed = timeline.append(
            position, audio: audioStart..<(audioStart + Int64(buffer.frameLength)), rendered: playedSamples() ?? 0)
        scheduledEnd = placed.upperBound
        node.scheduleBuffer(
            buffer, at: AVAudioTime(sampleTime: placed.lowerBound, atRate: sampleRate), options: [],
            completionCallbackType: completionType,
            completionHandler: last ? ended(position, generation: generation) : nil)
    }

    private func ended(
        _ position: Int, generation: Int
    ) -> @Sendable (AVAudioPlayerNodeCompletionCallbackType) -> Void {
        let deliverCompletion = deliverCompletion
        return { @Sendable [weak self] _ in
            // The engine calls this on its own thread.
            deliverCompletion { [weak self] in self?.finished(position, generation: generation) }
        }
    }

    /// Starts the first sound, or ends a refill, once the start threshold of ADR 0060 is met. Encoded bytes that
    /// arrived but wait undecoded count as buffered audio.
    private func startIfReady(_ transfer: TrackTransfer, remaining: Double) throws {
        guard !started || starved, let stream else { return }
        let decoded = Double(scheduledEnd - (playedSamples() ?? 0)) / sampleRate
        let encoded = Double(transfer.bufferedBytes(from: consumed)) * 8 / stream.bitrate
        // A complete file needs no network estimate.
        let throughput = transfer.snapshot.complete ? Double.infinity : transfer.throughput
        guard decoded >= StartThreshold.minimum || remaining <= 0 else { return report() }
        if let target = StartThreshold.seconds(bitrate: stream.bitrate, throughput: throughput, remaining: remaining),
            decoded + encoded + Double(heldFrames) / sampleRate >= target
        {
            try sound()
        } else {
            report()
        }
    }

    /// Lets the node sound. A paused session keeps it silent; `resume` starts it.
    private func sound() throws {
        started = true
        starved = false
        if playing, let node {
            try start(node)
            pausedAt = nil
        }
        report()
    }

    /// The length of a fade in frames.
    private var fadeFrames: Int { Int((fadeSeconds * sampleRate).rounded()) }

    /// Starts the node from silence, so a start inside a waveform (a seek, a resume) does not click.
    /// A node that still plays only ramps up again, when a fade-out silenced it: a second start would dip it.
    func start(_ node: AVAudioPlayerNode) throws {
        guard !node.isPlaying else {
            if silenced { rampUp(from: nil) }
            return
        }
        rampUp(from: 0)
        try node.playAudio()
    }

    private func rampUp(from level: Float?) {
        halting?.cancel()
        halting = nil
        silenced = false
        fade?.ramp(from: level, to: 1, frames: fadeFrames)
    }

    /// Ramps the sound to silence over `frames`, then runs `body`. A start or a discard cancels the wait.
    /// `delay` holds the ramp back so that it ends with the scheduled audio, and `extra` keeps the node up after
    /// the ramp for the output latency of the device.
    private func halt(
        frames: Int, delay: Double = 0, extra: Double = 0.03, then body: @escaping @MainActor () -> Void
    ) {
        halting?.cancel()
        guard let fade else { return body() }
        silenced = true
        let wait = Double(frames) / sampleRate + extra
        if delay <= 0 { fade.ramp(to: 0, frames: frames) }
        // The render thread runs the ramp, so the sleeps only place it in time.
        halting = Task {
            if delay > 0 {
                try? await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled else { return }
                fade.ramp(to: 0, frames: frames)
            }
            try? await Task.sleep(for: .seconds(wait))
            guard !Task.isCancelled else { return }
            halting = nil
            body()
        }
    }

    /// Stops a replaced engine after its sound faded out, so a skip does not cut the wave. The replaced load is
    /// already invalid, so nothing of it reaches the session. A silent engine stops at once.
    private func retire(_ engine: AVAudioEngine?, _ node: AVAudioPlayerNode?, _ fade: FadeControl?) {
        guard let engine else { return }
        guard let node, let fade, started, !starved, node.isPlaying else { return engine.stop() }
        // A skip during another fade starts the fade-out from the level that the ramp has reached.
        let frames = fadeFrames
        fade.ramp(to: 0, frames: frames)
        let wait = Double(frames) / sampleRate + 0.03
        Task {
            try? await Task.sleep(for: .seconds(wait))
            engine.stop()
        }
    }

    /// Watches for a node that runs out of audio before the bytes arrive, and reports the wait.
    private func watch(_ generation: Int) {
        watcher = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.watchInterval)
                guard let self, generation == self.generation else { return }
                self.checkStarvation()
            }
        }
    }

    func checkStarvation() {
        if let played = playedSamples() {
            // The fade must end before the audio does, so the check looks one fade and one watch tick ahead.
            let lead = Int64(fadeFrames) + Int64(sampleRate * (Self.watchInterval / .seconds(1)))
            let remaining = scheduledEnd - played
            if playing, started, !starved, decoding, let node, node.isPlaying, remaining <= lead {
                // A pause keeps the next sample in place on the timeline until the refill is ready.
                starved = true
                let generation = generation
                // The ramp ends with the audio, and the node stops one watch tick after the audio, so the end of
                // the movement is reported before the stop.
                let frames = Int(min(Int64(fadeFrames), max(remaining, 0)))
                halt(
                    frames: frames, delay: Double(max(remaining, 0) - Int64(frames)) / sampleRate,
                    extra: Self.watchInterval / .seconds(1)
                ) { [weak self] in
                    guard let self, generation == self.generation, self.starved else { return }
                    self.pausedAt = self.playedSamples()
                    node.pause()
                }
            }
            timeline.prune(before: played)
        }
        report()
    }

    /// Tells the session whether the listener waits, and whether the connection is the reason.
    private func report() {
        var wait: PlaybackWait?
        if playing && (!started || starved) {
            let slow = stream.map { $0.transfer.isSlow(below: $0.bitrate) } ?? false
            wait = PlaybackWait(kind: started ? .resume : .start, slow: slow)
        }
        guard wait != reported else { return }
        reported = wait
        onEvent?(.waiting(wait))
    }

    private func finished(_ position: Int, generation: Int) {
        guard generation == self.generation, engine?.isRunning == true else { return }
        lastEnded = position
        onEvent?(.movementEnded(position))
        reportFormatBreak()
    }

    /// Runs decoder work on the worker queue, where its reads may wait for bytes.
    private func work<T: Sendable>(_ body: @escaping @Sendable () throws -> T) async throws -> T {
        guard let worker else { throw CancellationError() }
        return try await withCheckedThrowingContinuation { continuation in
            worker.async { continuation.resume(with: Result { try body() }) }
        }
    }

    /// The decoder and its buffers cross to the main actor here. Only one queue uses each at a time.
    private struct Box<Value>: @unchecked Sendable {
        var value: Value
        init(_ value: Value) { self.value = value }
    }

    /// One decoder read: its output, and the decoder's bitrate and place in the file after it.
    private struct Decoded: @unchecked Sendable {
        var output: PCMReader.Output
        var bitrate: Double?
        var consumed: Int64

        init(_ decoder: StreamDecoder, reader: PCMReader) throws {
            output = try reader.next(
                frames: AVAudioFrameCount(GaplessEngine.chunkSeconds * reader.format.sampleRate))
            bitrate = decoder.observedBitrate
            consumed = decoder.consumed
        }
    }

    /// The part of a movement that plays after a seek. It keeps at least one frame, so the movement still ends
    /// and the next one follows.
    nonisolated static func seekRange(_ range: Range<Int64>, to seconds: Double, sampleRate: Double) -> Range<Int64> {
        let frame = seconds.isFinite ? Int64((seconds * sampleRate).rounded()) : 0
        let skip = min(max(frame, 0), max(Int64(range.count) - 1, 0))
        return (range.lowerBound + skip)..<range.upperBound
    }

    /// The frames of a decoded file that belong to the recording: the gapless data of an MP3 or an M4A file, else
    /// every frame. The container tells an M4A file, because a stored track may carry no extension.
    nonisolated static func playableRange(of file: AVAudioFile) -> Range<Int64> {
        if file.url.pathExtension.lowercased() == "mp3",
            let data = try? Data(contentsOf: file.url, options: .mappedIfSafe),
            let header = MP3GaplessInfo.parse(data)
        {
            return header.playableRange(decodedLength: file.length)
        }
        if let info = M4AGaplessInfo.parse(fileAt: file.url) {
            return info.playableRange(decodedLength: file.length)
        }
        return 0..<file.length
    }
}
