import AVFoundation

/// Plays the queued recordings back to back, without gaps, on one node timeline.
/// A complete file plays as a segment. A track that is still arriving plays from decoded buffers, as soon as the
/// start threshold allows (ADR 0060). Both cut MP3 encoder delay and padding in decoded sample coordinates.
@MainActor
final class GaplessEngine: PlaybackEngine {
    typealias CompletionDelivery = @Sendable (@escaping @MainActor @Sendable () -> Void) -> Void

    /// Each decoded buffer holds this much audio.
    nonisolated static let chunkSeconds = 0.25
    /// The decoded audio that may wait on the node ahead of the render position (ADR 0060).
    static let aheadSeconds = 2.0
    static let watchInterval = Duration.milliseconds(100)

    var onEvent: (@MainActor (PlaybackEngineEvent) -> Void)?
    var isRunning: Bool { engine?.isRunning == true && node != nil }

    private var engine: AVAudioEngine?
    private var node: AVAudioPlayerNode?
    /// Applies the ReplayGain. The node volume cannot go above 1, so it cannot boost.
    private var gain: AVAudioUnitEQ?
    private var decibels: Float = 0
    private var engineNotifications: PlaybackNotifications?
    private var task: Task<Void, Never>?
    private var watcher: Task<Void, Never>?
    private var activation: Task<Void, Never>?
    /// Completion handlers of an earlier load must not reach the session.
    private var generation = 0
    /// Whether the session wants sound. A load that finishes after a pause must stay silent.
    private var playing = false
    /// Where each scheduled movement sits on the player's timeline, in samples.
    private var timeline = AudioTimeline()
    private var convertedFrames = ConvertedFrameCount()
    private var sampleRate = 44_100.0
    private var format: AVAudioFormat?
    /// A paused node reports no player time, so the position is kept here.
    private var pausedAt: Int64?
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
    private var reported: PlaybackWait?
    /// Stops the blocked reads of the worker when a load ends.
    private var cancelled = CancelFlag()
    private var worker: DispatchQueue?
    private let deliverCompletion: CompletionDelivery
    private let rendered: (@Sendable (AVReadOnlyAudioPCMBuffer) -> Void)?

    init(
        deliverCompletion: @escaping CompletionDelivery = { completion in
            Task { @MainActor in completion() }
        },
        rendered: (@Sendable (AVReadOnlyAudioPCMBuffer) -> Void)? = nil
    ) {
        self.deliverCompletion = deliverCompletion
        self.rendered = rendered
    }

    func load(_ songs: [Song], from movement: Int, offset: Double, file: @escaping PlaybackFileSource) {
        discard()
        playing = true
        let generation = generation
        cancelled = CancelFlag()
        worker = DispatchQueue(label: "de.whnr.klassik.decoder", qos: .default)
        task = Task {
            await schedule(songs, from: movement, offset: offset, file: file, generation: generation)
        }
    }

    func pause() {
        pausedAt = playedSamples()
        node?.pause()
        playing = false
        report()
    }

    func resume() throws {
        playing = true
        // Before the first sound and during a refill, the scheduler starts the node when enough audio waits.
        guard started && !starved, let node else { return report() }
        let generation = generation
        activation?.cancel()
        activation = Task {
            do {
                try await Self.activateSession()
                try check(generation)
                guard playing else { return }
                try node.playAudio()
                pausedAt = nil
            } catch {
                guard generation == self.generation, !Task.isCancelled else { return }
                onEvent?(.failed(error.localizedDescription))
            }
        }
    }

    func discard() {
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
        engine?.stop()
        engine = nil
        node = nil
        gain = nil
        format = nil
        pausedAt = nil
        timeline = AudioTimeline()
        convertedFrames = ConvertedFrameCount()
        scheduledEnd = 0
        started = false
        starved = false
        decoding = false
        stream = nil
        reported = nil
        playing = false
    }

    func setGain(_ decibels: Float) {
        self.decibels = decibels
        gain?.globalGain = decibels
    }

    func position(from movement: Int) -> (movement: Int, elapsed: Double)? {
        guard let sample = playedSamples(), let found = timeline.position(at: sample, from: movement) else {
            return nil
        }
        return (found.movement, Double(found.frame) / sampleRate)
    }

    func duration(of movement: Int) -> Double? {
        timeline.length(movement).map { Double($0) / sampleRate }
    }

    nonisolated private static func activateSession() async throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default)
        guard try await session.activate() else { throw CancellationError() }
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
        // A `discard()` can run between `load` and the start of this task. Then no state may change.
        guard generation == self.generation, !Task.isCancelled else { return }
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
        decoding = true
        watch(generation)
        do {
            for position in index..<songs.count {
                // Only the audible track and its immediate successor may request playback bytes.
                while !playing || (position > index + 1 && audibleMovement() < position - 1) {
                    try await Task.sleep(for: Self.watchInterval)
                    try check(generation)
                }
                let seconds = position == index ? offset : 0
                report()
                let track = try await source(songs[position])
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
                            transfer, song: songs[position], position: position, offset: seconds,
                            generation: generation)
                    else { return }
                }
                onEvent?(.scheduled(position))
            }
            decoding = false
        } catch {
            guard generation == self.generation, !Task.isCancelled else { return }
            onEvent?(.failed(error.localizedDescription))
        }
    }

    private func audibleMovement() -> Int {
        let sample = playedSamples() ?? 0
        return timeline.position(at: sample, from: 0)?.movement ?? -1
    }

    private func check(_ generation: Int) throws {
        guard generation == self.generation, !Task.isCancelled else { throw CancellationError() }
    }

    /// The first track fixes the node format. Later tracks convert their PCM before they reach this graph.
    private func connect(_ incoming: AVAudioFormat, position: Int, generation: Int) async throws -> Bool {
        guard let engine, let node, let gain else { return false }
        if format != nil { return true }
        format = incoming
        sampleRate = incoming.sampleRate
        try engine.connectNode(node, to: gain, format: incoming)
        try engine.connectNode(gain, to: engine.mainMixerNode, format: incoming)
        if let rendered {
            try gain.installAudioTap(
                onBus: 0, bufferSize: AVAudioFrameCount(incoming.sampleRate * Self.chunkSeconds), format: incoming
            ) { buffer, _ in rendered(buffer) }
        }
        try await Self.activateSession()
        try check(generation)
        try engine.start()
        return true
    }

    private func scheduleFile(_ url: URL, position: Int, offset: Double, generation: Int) async throws -> Bool {
        let file = try AVAudioFile(forReading: url)
        guard try await connect(file.processingFormat, position: position, generation: generation), let node else {
            return false
        }
        stream = nil
        let playable = Self.playableRange(of: file)
        let range =
            offset > 0 ? Self.seekRange(playable, to: offset, sampleRate: file.processingFormat.sampleRate) : playable
        if let format, file.processingFormat != format {
            return try await scheduleConvertedFile(
                file, playable: playable, range: range, position: position, generation: generation)
        }
        // A slow download leaves the player idle; the movement then starts at the current position.
        timeline.declare(position, frames: Int64(playable.count))
        let skipped = range.lowerBound - playable.lowerBound
        let placed = timeline.append(
            position, audio: skipped..<(skipped + Int64(range.count)), rendered: playedSamples() ?? 0)
        scheduledEnd = placed.upperBound
        node.scheduleSegment(
            file, startingFrame: range.lowerBound, frameCount: AVAudioFrameCount(range.count),
            at: AVAudioTime(sampleTime: placed.lowerBound, atRate: sampleRate),
            completionCallbackType: .dataPlayedBack, completionHandler: ended(position, generation: generation))
        try sound()
        return true
    }

    private func scheduleConvertedFile(
        _ file: AVAudioFile, playable: Range<Int64>, range: Range<Int64>, position: Int, generation: Int
    ) async throws -> Bool {
        guard let format else { return false }
        let output = Box(format)
        let url = file.url
        let inputRate = file.processingFormat.sampleRate
        let skipped = Int64((Double(range.lowerBound - playable.lowerBound) * sampleRate / inputRate).rounded())
        let count = convertedFrames.frames(Int64(range.count), from: inputRate, to: sampleRate)
        let conversion = try await work {
            let decoder = try FilePCMDecoder(url, playable: range)
            return try PCMConversion(from: decoder.file.processingFormat, to: output.value, frames: count) {
                try decoder.read(frames: $0)
            }
        }
        try check(generation)
        timeline.declare(position, frames: skipped + count)
        var cursor = skipped
        var held: AVAudioPCMBuffer?
        var heldStart = cursor
        let rate = sampleRate
        let chunk = AVAudioFrameCount(Self.chunkSeconds * rate)
        while true {
            while scheduledEnd - (playedSamples() ?? 0) >= Int64((Self.aheadSeconds - Self.chunkSeconds * 2) * rate) {
                try await Task.sleep(for: Self.watchInterval)
                try check(generation)
            }
            let next = try await work { try Box(conversion.read(frames: chunk)) }.value
            try check(generation)
            if let held {
                enqueue(held, position: position, audioStart: heldStart, last: next == nil, generation: generation)
                try sound()
            }
            guard let next else { break }
            heldStart = cursor
            cursor += Int64(next.frameLength)
            held = next
        }
        return true
    }

    /// Decodes a track while it arrives, and keeps at most `aheadSeconds` of it on the node.
    private func scheduleStream(
        _ transfer: TrackTransfer, song: Song, position: Int, offset: Double, generation: Int
    ) async throws -> Bool {
        stream = (transfer, AudioBitrate.initial(song))
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
        guard try await connect(decoder.format, position: position, generation: generation) else { return false }
        let sourceRate = decoder.sampleRate
        let playable = decoder.playable ?? 0..<Int64(Double(song.duration ?? 0) * sourceRate)
        let selected = offset > 0 ? Self.seekRange(playable, to: offset, sampleRate: sourceRate) : playable
        let skipped = selected.lowerBound - playable.lowerBound
        if skipped > 0 { _ = try await work { try Box(decoder.seek(to: selected.lowerBound)) } }
        let rate = sampleRate
        let output = Box(format!)
        let expected = decoder.playable.map { _ in
            convertedFrames.frames(Int64(selected.count), from: sourceRate, to: rate)
        }
        let conversion = try await work {
            try PCMConversion(from: decoder.format, to: output.value, frames: expected) { try decoder.read(frames: $0) }
        }
        try check(generation)
        var emitted = Int64((Double(skipped) * rate / sourceRate).rounded())
        let fullLength = emitted + (expected ?? Int64(Double(playable.count) * rate / sourceRate))
        timeline.declare(position, frames: fullLength)
        let ahead = Int64((Self.aheadSeconds - Self.chunkSeconds * 2) * rate)
        // One buffer waits off the node, so that the last buffer of the track carries the end callback.
        var held: AVAudioPCMBuffer?
        var heldStart = emitted
        var consumed: Int64 = 0
        while true {
            if scheduledEnd - (playedSamples() ?? 0) >= ahead {
                try startIfReady(
                    transfer, consumed: consumed, remaining: Double(fullLength - emitted) / rate,
                    pending: held.map { Int64($0.frameLength) } ?? 0)
                try await Task.sleep(for: Self.watchInterval)
                try check(generation)
                continue
            }
            let decoded = try await work { try Decoded(decoder, conversion: conversion) }
            try check(generation)
            stream = (transfer, AudioBitrate.current(song, observed: decoded.bitrate))
            consumed = decoded.consumed
            if let held {
                enqueue(
                    held, position: position, audioStart: heldStart, last: decoded.buffer == nil, generation: generation
                )
            }
            guard let buffer = decoded.buffer else { break }
            held = buffer
            heldStart = emitted
            emitted += Int64(buffer.frameLength)
            try startIfReady(
                transfer, consumed: consumed, remaining: Double(fullLength - emitted) / rate,
                pending: held.map { Int64($0.frameLength) } ?? 0)
        }
        guard held != nil else {
            throw StreamDecoder.Failure.status(kAudioFileEndOfFileError)
        }
        // The decoder knows the exact length now, also where the file declared none.
        timeline.declare(position, frames: emitted)
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
            completionCallbackType: .dataPlayedBack,
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
    private func startIfReady(_ transfer: TrackTransfer, consumed: Int64, remaining: Double, pending: Int64) throws {
        guard !started || starved, let stream else { return }
        let snapshot = transfer.snapshot
        let decoded = Double(scheduledEnd - (playedSamples() ?? 0)) / sampleRate
        let encoded = Double(max(snapshot.available - consumed, 0)) * 8 / stream.bitrate
        // A complete file needs no network estimate.
        let throughput = snapshot.complete ? Double.infinity : transfer.throughput
        guard decoded >= StartThreshold.minimum || remaining <= 0 else { return report() }
        if let target = StartThreshold.seconds(bitrate: stream.bitrate, throughput: throughput, remaining: remaining),
            decoded + encoded + Double(pending) / sampleRate >= target
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
        if playing, let node, !node.isPlaying {
            try node.playAudio()
            pausedAt = nil
        }
        report()
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

    private func checkStarvation() {
        if playing, started, !starved, decoding, let node, node.isPlaying, let played = playedSamples(),
            played >= scheduledEnd
        {
            // A pause keeps the next sample in place on the timeline until the refill is ready.
            starved = true
            pausedAt = played
            node.pause()
        }
        if let played = playedSamples() { timeline.prune(before: played) }
        report()
    }

    /// Tells the session whether the listener waits, and whether the connection is the reason.
    private func report() {
        var wait: PlaybackWait?
        if playing && (!started || starved) {
            var slow = false
            if let stream, let throughput = stream.transfer.throughput { slow = throughput < stream.bitrate }
            wait = PlaybackWait(kind: started ? .resume : .start, slow: slow)
        }
        guard wait != reported else { return }
        reported = wait
        onEvent?(.waiting(wait))
    }

    private func finished(_ position: Int, generation: Int) {
        guard generation == self.generation, engine?.isRunning == true else { return }
        onEvent?(.movementEnded(position))
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

    /// One decoder read: its buffer, nil at the end, and what the decoder consumed so far.
    private struct Decoded: @unchecked Sendable {
        var buffer: AVAudioPCMBuffer?
        var bitrate: Double?
        var consumed: Int64

        init(_ decoder: StreamDecoder, conversion: PCMConversion) throws {
            buffer = try conversion.read(
                frames: AVAudioFrameCount(GaplessEngine.chunkSeconds * conversion.format.sampleRate))
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

    private static func playableRange(of file: AVAudioFile) -> Range<Int64> {
        guard file.url.pathExtension.lowercased() == "mp3",
            let data = try? Data(contentsOf: file.url, options: .mappedIfSafe),
            let header = MP3GaplessInfo.parse(data)
        else { return 0..<file.length }
        return header.playableRange(decodedLength: file.length)
    }
}
