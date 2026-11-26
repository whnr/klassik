import AVFoundation
import KlassikEngine
import Observation

/// Plays one test case with the real engine. It owns the two switches of the Lab: ReplayGain and the throttle.
@MainActor @Observable
final class LabPlayer {
    private(set) var isPlaying = false
    private(set) var status = "Stopped"
    /// The movement that sounds, counted from 0.
    private(set) var movement = 0
    private(set) var elapsed = 0.0
    private(set) var movementLength = 0.0
    /// The sample rate that iOS reports for the output.
    private(set) var outputRate = 0.0
    /// The sample rate and channel count that the engine's graph runs at: the rate of the file that plays.
    private(set) var engineRate = 0.0
    private(set) var engineChannels = 0
    /// What iOS reports about the output route, read live.
    private(set) var route = LabRoute()
    private(set) var graph = LabRoute.Graph(sourceRate: 0, sourceChannels: 0, outputs: nil)
    private(set) var routeChange: String?
    private(set) var join = "not played yet"
    private(set) var note: String?
    /// True while the output is recorded to a WAV.
    private(set) var capturing = false
    /// The files of the last capture. Setting it back to nil closes the share sheet.
    var captured: CapturedFiles?
    private(set) var captureNote: String?

    var selected: LabCase? {
        didSet {
            guard oldValue?.id != selected?.id else { return }
            stop()
            // A case switch is the only event that drops the audio files.
            Self.wipe()
        }
    }
    /// Off builds the engine without its gain node, so the stage is absent from the signal path.
    var replayGain = true {
        didSet { if oldValue != replayGain { restart() } }
    }
    /// The fades at skip, seek, pause, resume and the underrun stop. A change reaches the running engine at once.
    var fade = LabFadeSettings() {
        didSet { engine?.fadeOptions = fade.options }
    }
    var throttle = LabThrottle() {
        didSet { if oldValue != throttle { restart() } }
    }

    struct CapturedFiles: Identifiable {
        let id = UUID()
        let wav: URL
        let sidecar: URL
    }

    private let client: LabClient
    private var recorder: CaptureRecorder?
    private var captureStart = Date()
    private var captureTitle = ""
    private var finishTask: Task<Void, Never>?
    /// Removes its observers when the player goes away.
    private let routeNotifications = PlaybackNotifications()
    private var engine: GaplessEngine?
    private var feeders: [LabFeeder] = []
    private var ticker: Task<Void, Never>?
    private var ended: Set<Int> = []
    private var gainMovement: Int?
    /// Where Play starts after a switch discarded the paused engine.
    private var resumePlace: (movement: Int, offset: Double)?

    /// Audio files stay here from their first download until a case switch or the next start. Stop, seek, pause,
    /// throttle, gain and output changes keep them, so that a test repeats without a refetch.
    static var folder: URL { URL.temporaryDirectory.appending(path: "lab-audio") }

    init(client: LabClient, cases: [LabCase]) {
        self.client = client
        selected = cases.first
        Self.wipe()
        route = LabRoute.read()
        routeNotifications.observe(AVAudioSession.routeChangeNotification) { [weak self] note in
            let raw = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
            Task { @MainActor in self?.routeChanged(raw) }
        }
    }

    /// The lines of the routing section.
    var routeLines: [String] { LabRoute.lines(route: route, graph: graph, change: routeChange) }

    /// The lines as the screen shows them: never fewer than `LabRoute.reservedLines`, so the box keeps its height.
    var reservedRouteLines: [String] { LabRoute.reserved(routeLines) }

    private func routeChanged(_ raw: UInt?) {
        routeChange = LabRoute.reason(raw)
        refreshRoute()
    }

    private func refreshRoute() {
        route = LabRoute.read()
        outputRate = route.sampleRate
        // A seek builds a new graph that has no format until its first track connects. The lines keep the last graph
        // meanwhile, so that the routing box does not lose lines and shift the screen.
        if let rate = engine?.sourceSampleRate, rate > 0 {
            graph = LabRoute.Graph(
                sourceRate: rate, sourceChannels: engine?.sourceChannelCount ?? 0, outputs: engine?.outputFormats)
        } else if engine == nil {
            graph = LabRoute.Graph(sourceRate: 0, sourceChannels: 0, outputs: nil)
        }
        engineRate = graph.sourceRate
        engineChannels = graph.sourceChannels
    }

    /// The line that the screen always shows: source format, the rate of the engine's graph, the rate that iOS
    /// reports for the output, and the join. Commas separate the fields. It claims no bit-perfect playback and
    /// names no output bit depth, because iOS reports none.
    var qualityLine: String {
        Self.qualityLine(
            source: selected?.sourceLine ?? "no case", engineRate: engineRate, engineChannels: engineChannels,
            outputRate: outputRate, output: route.outputName, join: join)
    }

    nonisolated static func qualityLine(
        source: String, engineRate: Double, engineChannels: Int, outputRate: Double, output: String, join: String
    ) -> String {
        var fields = ["Source \(source)"]
        if engineRate > 0 {
            let channels = engineChannels == 1 ? "mono" : engineChannels == 2 ? "stereo" : "\(engineChannels) channels"
            fields.append("engine \(kilohertz(engineRate)) kHz \(channels)")
        }
        if outputRate <= 0 {
            fields.append("iOS output unknown")
        } else if engineRate > 0, outputRate == engineRate {
            fields.append("iOS output \(kilohertz(outputRate)) kHz on \(output), native")
        } else if engineRate > 0 {
            fields.append("iOS output \(kilohertz(outputRate)) kHz on \(output), iOS converts")
        } else {
            fields.append("iOS output \(kilohertz(outputRate)) kHz on \(output)")
        }
        fields.append("join \(join)")
        return fields.joined(separator: ", ")
    }

    nonisolated private static func kilohertz(_ hertz: Double) -> String {
        LabCase.kilohertz(Int(hertz.rounded()))
    }

    var canPlay: Bool { selected != nil && selected?.unsupportedReason == nil }

    func togglePlay() {
        guard canPlay else { return }
        if isPlaying {
            engine?.pause()
            isPlaying = false
            status = "Paused"
        } else if let place = resumePlace {
            start(movement: place.movement, offset: place.offset)
        } else if let engine, engine.isRunning, !ended.contains(lastIndex) {
            do {
                try engine.resume()
                isPlaying = true
                status = "Playing"
            } catch {
                status = error.localizedDescription
            }
        } else {
            start(movement: 0, offset: 0)
        }
    }

    /// Starts or stops the recording of the engine's output. Neither touches the graph or the engine: the engine only
    /// gets a tap that copies blocks.
    func toggleCapture() {
        if capturing { endCapture() } else { beginCapture() }
    }

    static var captureFolder: URL { URL.temporaryDirectory.appending(path: "lab-capture") }

    private func beginCapture() {
        // The previous finish writes into the folder, so it ends before the folder goes.
        let previous = finishTask
        previous?.cancel()
        finishTask = nil
        captured = nil
        capturing = true
        captureNote = nil
        // The files of the last capture stay until now: a share target can read a file after the sheet has closed.
        Task {
            await previous?.value
            startRecording()
        }
    }

    private func startRecording() {
        guard capturing, recorder == nil else { return }
        try? FileManager.default.removeItem(at: Self.captureFolder)
        try? FileManager.default.createDirectory(at: Self.captureFolder, withIntermediateDirectories: true)
        let title = selected?.title ?? "no case"
        let stamp = UUID().uuidString.prefix(8)
        let slug = String(title.lowercased().map { $0.isLetter || $0.isNumber ? $0 : "-" })
        let url = Self.captureFolder.appending(path: "lab-\(slug)-\(stamp).wav")
        let recorder = CaptureRecorder(url: url) { [weak self] in
            Task { @MainActor in self?.endCapture() }
        }
        self.recorder = recorder
        captureStart = Date()
        captureTitle = title
        engine?.setOutputTap { recorder.makeSource(startSeconds: $0) }
    }

    private func endCapture() {
        guard capturing else { return }
        capturing = false
        guard let recorder else { return }
        self.recorder = nil
        engine?.setOutputTap(nil)
        let title = captureTitle
        let started = captureStart
        let fade = fade
        let gain = replayGain
        let throttle = throttle.mode.title
        let route = routeLines
        finishTask = Task {
            defer { finishTask = nil }
            let result = await recorder.finish()
            guard !Task.isCancelled else { return }
            let stopped = result.error.map { "The capture stopped: \($0)" }
            guard let wav = result.url else {
                captureNote = stopped ?? "Nothing was recorded: no sound reached the output."
                return
            }
            let sidecar = wav.deletingPathExtension().appendingPathExtension("txt")
            let text = CaptureSidecar.text(
                caseTitle: title, fade: fade, replayGain: gain, throttle: throttle, route: route, result: result,
                startedAt: started)
            try? text.write(to: sidecar, atomically: true, encoding: .utf8)
            captureNote = stopped ?? (result.capped ? "Stopped at the 60 s cap." : nil)
            captured = CapturedFiles(wav: wav, sidecar: sidecar)
        }
    }

    /// Moves to a place in the movement that sounds. The engine that plays stays, so that the seek mode can keep
    /// the old position until the new one is ready.
    func seek(to fraction: Double) {
        guard canPlay, movementLength > 0 else { return }
        start(movement: movement, offset: min(max(fraction, 0), 1) * movementLength, keepingEngine: true)
    }

    func stop() {
        teardown()
        resumePlace = nil
        isPlaying = false
        status = "Stopped"
        movement = 0
        elapsed = 0
        movementLength = 0
        join = Self.notPlayed
        note = nil
    }

    nonisolated static let notPlayed = "not played yet"

    private var lastIndex: Int { (selected?.songs.count ?? 1) - 1 }

    /// A switch that changes the signal path or the network takes effect at the place where it was.
    private func restart() {
        switch Self.switchAction(isPlaying: isPlaying, hasEngine: engine != nil) {
        case .none: break
        case .restart: start(movement: movement, offset: elapsed)
        case .discard:
            // A paused engine keeps its old gain node and feeders, so Play builds a new one here.
            teardown()
            resumePlace = (movement, elapsed)
            status = "Paused"
        }
    }

    enum SwitchAction: Equatable { case none, restart, discard }

    /// A paused engine cannot take a switch, so it is discarded and Play builds it again.
    nonisolated static func switchAction(isPlaying: Bool, hasEngine: Bool) -> SwitchAction {
        guard hasEngine else { return .none }
        return isPlaying ? .restart : .discard
    }

    private func teardown() {
        stopWork()
        engine?.discard()
        engine = nil
    }

    private func stopWork() {
        ticker?.cancel()
        ticker = nil
        for feeder in feeders { feeder.cancel() }
        feeders = []
    }

    private func start(movement: Int, offset: Double, join opening: String? = nil, keepingEngine: Bool = false) {
        guard let selected, canPlay else { return }
        if keepingEngine, engine != nil { stopWork() } else { teardown() }
        resumePlace = nil
        ended = []
        note = nil
        gainMovement = nil
        // The join tells about the load that plays now. A restart in the middle of a work keeps no earlier join.
        join = opening ?? Self.joinWaiting(movement: movement, count: selected.songs.count)
        try? FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true)
        let active = engine ?? makeEngine()
        self.movement = movement
        elapsed = offset
        let throttle = throttle
        active.load(selected.tracks, from: movement, offset: offset) { [weak self] track in
            guard let self else { throw CancellationError() }
            return try await self.source(for: track, throttle: throttle)
        }
        isPlaying = true
        status = "Loading"
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                self?.tick()
                try? await Task.sleep(for: .milliseconds(200))
            }
        }
    }

    private func makeEngine() -> GaplessEngine {
        let engine = GaplessEngine(gainNode: replayGain)
        engine.fadeOptions = fade.options
        engine.onEvent = { [weak self] event in self?.handle(event) }
        if let recorder { engine.setOutputTap { recorder.makeSource(startSeconds: $0) } }
        self.engine = engine
        return engine
    }

    /// Streams a track through the throttle. A format that cannot start early plays from the whole file.
    private func source(for track: PlaybackTrack, throttle: LabThrottle) async throws -> PlaybackSource {
        let target = Self.cached(track)
        if FileManager.default.fileExists(atPath: target.path) { return .file(target) }
        let transfer = TrackTransfer(
            songID: track.id, partial: Self.folder.appending(path: UUID().uuidString + ".partial"),
            target: target, url: nil)
        let feeder = LabFeeder(transfer: transfer, throttle: throttle)
        feeders.append(feeder)
        feeder.start(client.streamRequest(songID: track.id))
        if track.canStartEarly { return .stream(transfer) }
        return .file(try await transfer.finished())
    }

    private func handle(_ event: PlaybackEngineEvent) {
        switch event {
        case .movementEnded(let index):
            ended.insert(index)
            guard index == lastIndex else {
                // The next movement either waits on the node by now, or the node ran dry.
                join = Self.joinAfterEnd(
                    of: index, nextScheduled: engine?.hasScheduled(movement: index + 1) ?? false)
                return
            }
            isPlaying = false
            status = "Ended"
        case .loading: break
        case .waiting(let wait):
            guard isPlaying else { return }
            guard let wait else {
                status = "Playing"
                return
            }
            status = wait.slow ? "Waiting for bytes: link slower than the file" : "Waiting for bytes"
        case .scheduled: break
        case .formatChanged(let index):
            // The movement before it played out. The next one has another rate or channel count, so the engine
            // starts again at it. The app never converts, and the short gap is the price.
            guard isPlaying else { return }
            start(
                movement: index, offset: 0,
                join: "gap, movement \(index + 1) has another sample rate or channel count")
        case .configurationChanged:
            // The output changed, for example a headset: the engine stopped and the load starts again here. The engine
            // stays, so that a crossfade that waits for its new graph keeps the old sound until that graph sounds.
            if isPlaying { start(movement: movement, offset: elapsed, keepingEngine: true) }
        case .problem(let message): note = message
        case .failed(let message):
            isPlaying = false
            status = "Failed: \(message)"
            join = Self.joinFailure(next: nextToSchedule, reason: message)
        case .serverFailed(let failure):
            isPlaying = false
            let reason = failure == .unreachable ? "Server did not answer" : "Server refused the request"
            status = reason
            join = Self.joinFailure(next: nextToSchedule, reason: reason)
        }
    }

    private func tick() {
        refreshRoute()
        guard let engine, let selected, let place = engine.position(from: 0) else { return }
        movement = place.movement
        elapsed = place.elapsed
        let fallback = selected.songs.indices.contains(place.movement) ? selected.songs[place.movement].duration : nil
        movementLength = engine.duration(of: place.movement) ?? fallback.map(Double.init) ?? 0
        if isPlaying, status == "Loading" { status = "Playing" }
        // The gain follows the movement that sounds. Without the gain node `setGain` changes nothing.
        if replayGain, gainMovement != place.movement, selected.songs.indices.contains(place.movement) {
            gainMovement = place.movement
            engine.setGain(VolumeLeveling.track.gain(for: selected.tracks[place.movement]))
        }
    }

    /// The movement that the engine loads when it fails, unless it is the first one. A failure of a later movement
    /// belongs to that movement.
    private var nextToSchedule: Int? {
        guard let requested = engine?.requestedMovement, requested > 0 else { return nil }
        return requested
    }

    /// The join line while a movement plays and the next one has not ended the earlier one yet.
    nonisolated static func joinWaiting(movement: Int, count: Int) -> String {
        movement + 1 < count ? "waiting for the end of movement \(movement + 1)" : notPlayed
    }

    /// The join at the end of a movement: gapless when the next one already waited on the node.
    nonisolated static func joinAfterEnd(of index: Int, nextScheduled: Bool) -> String {
        let next = "movement \(index + 2)"
        return nextScheduled
            ? "gapless: \(next) was scheduled before movement \(index + 1) ended"
            : "gap: \(next) was not scheduled when movement \(index + 1) ended"
    }

    /// A failure that stops the load before the next movement plays. It names that movement.
    nonisolated static func joinFailure(next: Int?, reason: String) -> String {
        guard let next else { return "load failed: \(reason)" }
        return "movement \(next + 1) failed: \(reason)"
    }

    static func cached(_ track: PlaybackTrack) -> URL {
        let suffix = (track.suffix ?? "").lowercased().filter { $0.isLetter || $0.isNumber }
        return folder.appending(path: suffix.isEmpty ? track.id : "\(track.id).\(suffix)")
    }

    private static func wipe() {
        try? FileManager.default.removeItem(at: folder)
    }
}
