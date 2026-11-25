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
    private(set) var join = "not played yet"
    private(set) var note: String?

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
    /// The fade at skip, seek, pause, resume and the underrun stop. A change reaches the running engine at once.
    nonisolated static let fadeRange: ClosedRange<Double> = 0...300
    nonisolated static let defaultFade = 100.0
    var fadeMilliseconds = LabPlayer.defaultFade {
        didSet { engine?.fadeSeconds = Self.fadeSeconds(milliseconds: fadeMilliseconds) }
    }
    var throttle = LabThrottle() {
        didSet { if oldValue != throttle { restart() } }
    }

    private let client: LabClient
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
    }

    /// The line that the screen always shows: source format, output rate, join.
    var qualityLine: String {
        let source = selected?.sourceLine ?? "no case"
        let output = outputRate > 0 ? "\(LabCase.kilohertz(Int(outputRate))) kHz" : "unknown"
        return "Source \(source) · iOS output \(output) · join \(join)"
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

    /// Moves to a place in the movement that sounds.
    func seek(to fraction: Double) {
        guard canPlay, movementLength > 0 else { return }
        start(movement: movement, offset: min(max(fraction, 0), 1) * movementLength)
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

    /// The slider value as the engine's length, clamped to the range of the slider.
    nonisolated static func fadeSeconds(milliseconds: Double) -> Double {
        min(max(milliseconds, fadeRange.lowerBound), fadeRange.upperBound) / 1000
    }

    enum SwitchAction: Equatable { case none, restart, discard }

    /// A paused engine cannot take a switch, so it is discarded and Play builds it again.
    nonisolated static func switchAction(isPlaying: Bool, hasEngine: Bool) -> SwitchAction {
        guard hasEngine else { return .none }
        return isPlaying ? .restart : .discard
    }

    private func teardown() {
        ticker?.cancel()
        ticker = nil
        engine?.discard()
        engine = nil
        for feeder in feeders { feeder.cancel() }
        feeders = []
    }

    private func start(movement: Int, offset: Double) {
        guard let selected, canPlay else { return }
        teardown()
        resumePlace = nil
        ended = []
        note = nil
        gainMovement = nil
        // The join tells about the load that plays now. A restart in the middle of a work keeps no earlier join.
        join = Self.joinWaiting(movement: movement, count: selected.songs.count)
        try? FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true)
        let engine = GaplessEngine(
            gainNode: replayGain, fadeSeconds: Self.fadeSeconds(milliseconds: fadeMilliseconds))
        engine.onEvent = { [weak self] event in self?.handle(event) }
        self.engine = engine
        self.movement = movement
        elapsed = offset
        let throttle = throttle
        engine.load(selected.tracks, from: movement, offset: offset) { [weak self] track in
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
        case .configurationChanged:
            // The output changed, for example a headset: the engine stopped and the load starts again here.
            if isPlaying { start(movement: movement, offset: elapsed) }
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
        outputRate = AVAudioSession.sharedInstance().sampleRate
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
