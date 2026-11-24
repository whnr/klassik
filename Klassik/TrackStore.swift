import Foundation
import KlassikEngine
import Observation

/// Keeps track files on the device in two places. The cache holds what played and drops the oldest files when it
/// is full. A download stays until the listener removes it, and the cache limit does not count it.
@MainActor @Observable
final class TrackStore {
    /// A recording or an album that the listener downloaded.
    struct Download: Codable, Identifiable, Sendable, Hashable {
        var id: String
        var title: String
        var detail: String
        var songIDs: [String]
        var bytes: Int64
        var date: Date
    }

    /// Loads one track and returns the temporary file. A test replaces it, so no test needs a server.
    typealias Fetch = @MainActor (Song, any ServerPort) async throws -> URL
    /// Delivers the bytes of a transfer. Production starts its URLSession request; a test feeds bytes itself.
    typealias Transport = @MainActor (Song, any ServerPort, TrackTransfer) -> Void
    /// Loads one track of a download in a session that keeps running while the app is suspended.
    typealias BackgroundLoad = @MainActor (Song, any ServerPort) async throws -> URL

    /// A download that was asked for and did not end. It survives a relaunch, so the menu stays truthful.
    private struct Pending: Codable {
        var recording: WorkIndex.Recording
        var title: String
    }

    /// The limit counts whole gigabytes, in the same decimal unit that the screen uses for every size.
    static let gigabyte: Int64 = 1_000_000_000
    static let limitRange = 1...50
    static let defaultLimit = 2 * gigabyte
    /// The encoded bytes that a track larger than the limit keeps on the device while it plays (ADR 0060).
    static let rollingWindow: Int64 = 64_000_000

    private(set) var downloads: [Download] = []
    /// The tracks that play without the server, downloaded or cached.
    private(set) var offline: Set<String> = []
    private(set) var cacheBytes: Int64 = 0
    private(set) var downloadBytes: Int64 = 0
    /// Share of a running download, by recording ID.
    private(set) var progress: [String: Double] = [:]
    private(set) var failures: [String: String] = [:]
    var networkAllowed = true
    enum Failure: LocalizedError {
        case offline

        var errorDescription: String? { "This iPhone has no network for music now." }
    }
    @ObservationIgnored private var downloadTracks: [String: Set<String>] = [:]
    /// Downloads asked for again while their cancelled task still ends. Each starts when its old task ended.
    @ObservationIgnored private var restarts: [String: @MainActor () -> Void] = [:]
    private var generation = 0

    var cacheLimit: Int64 {
        didSet {
            defaults.set(cacheLimit, forKey: Self.limitKey)
            budget.limit = cacheLimit
            evict()
        }
    }
    /// Counts every automatic audio byte under Music: complete files, partial files and open rolling windows.
    let budget: AudioStorageBudget

    private let cacheFolder: URL
    private let downloadFolder: URL
    private let manifestURL: URL
    private let pendingURL: URL
    @ObservationIgnored private var pending: [Pending] = []
    /// Nil in tests that need no background session: downloads then load through `load`.
    private let background: BackgroundLoad?
    private let defaults: UserDefaults
    private var tasks: [String: Task<Void, Never>] = [:]
    private let load: Fetch
    /// Nil when a test replaced the fetch: then every track loads whole.
    private let transport: Transport?
    /// The transfers in flight, by song ID. Playback, read-ahead and downloads share them (ADR 0060).
    @ObservationIgnored private(set) var transfers: [String: TrackTransfer] = [:]
    /// The current track and the next opening. Eviction keeps their files (ADR 0060).
    @ObservationIgnored var pinned: Set<String> = []
    /// The track that plays now. The Music limit interrupts it only after every other automatic byte.
    @ObservationIgnored var playing: String?
    /// Every track of the preparation set. Their transfers keep running when a download ends.
    @ObservationIgnored var wanted: Set<String> = []
    /// Clear Music calls it first, so that playback stops reading the files that it removes.
    @ObservationIgnored var willClearMusic: (@MainActor () -> Void)?
    /// Whole-file loads in flight, by song ID, so that playback and read-ahead share one.
    @ObservationIgnored private var fetches: [String: Task<URL, any Error>] = [:]
    /// A track file is on the device: for playback when the flag is true, else for a download. Its embedded art
    /// is read then, never by a fetch of its own (ADR 0059).
    @ObservationIgnored var loaded: (@MainActor (Song, URL, Bool) -> Void)?
    private static let limitKey = "store.cacheLimit"

    init(
        cacheFolder: URL = .cachesDirectory.appending(path: "tracks"),
        downloadFolder: URL = .applicationSupportDirectory.appending(path: "downloads"),
        defaults: UserDefaults = .standard, fetch: Fetch? = nil, transport: Transport? = nil,
        background: BackgroundLoad? = nil
    ) {
        self.background = background
        load = fetch ?? Self.stream
        if let transport {
            self.transport = transport
        } else if fetch == nil {
            self.transport = { _, _, transfer in transfer.start() }
        } else {
            self.transport = nil
        }
        self.cacheFolder = cacheFolder
        self.downloadFolder = downloadFolder
        self.manifestURL = downloadFolder.deletingLastPathComponent().appending(path: "downloads.json")
        self.pendingURL = downloadFolder.deletingLastPathComponent().appending(path: "pending-downloads.json")
        self.defaults = defaults
        let limit = defaults.object(forKey: Self.limitKey) as? Int64 ?? Self.defaultLimit
        cacheLimit = limit
        budget = AudioStorageBudget(limit: limit)
        downloads = (try? JSONDecoder().decode([Download].self, from: Data(contentsOf: manifestURL))) ?? []
        // No transfer runs yet, so a partial file is left over from an earlier run.
        for file in Self.files(in: cacheFolder) where file.isPartial {
            try? FileManager.default.removeItem(at: file.url)
        }
        rescan()
        pending = (try? JSONDecoder().decode([Pending].self, from: Data(contentsOf: pendingURL))) ?? []
        // The menu shows a download that the last run did not finish as running, until `resumeDownloads` starts it.
        for item in pending where !isDownloaded(item.recording) { progress[item.recording.id] = 0 }
    }

    /// Starts the downloads that an earlier run left unfinished.
    func resumeDownloads(client: any ServerPort) {
        for item in pending where tasks[item.recording.id] == nil {
            if isDownloaded(item.recording) {
                forget(item.recording.id)
            } else {
                download(item.recording, title: item.title, client: client)
            }
        }
    }

    private func remember(_ item: Pending) {
        pending.removeAll { $0.recording.id == item.recording.id }
        pending.append(item)
        savePending()
    }

    private func forget(_ id: String) {
        guard pending.contains(where: { $0.recording.id == id }) else { return }
        pending.removeAll { $0.recording.id == id }
        savePending()
    }

    private func savePending() {
        try? FileManager.default.createDirectory(
            at: pendingURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(pending) { try? data.write(to: pendingURL, options: .atomic) }
    }

    func isOffline(_ song: Song) -> Bool { offline.contains(song.id) }

    func isOffline(_ recording: WorkIndex.Recording) -> Bool {
        !recording.songs.isEmpty && recording.songs.allSatisfy { offline.contains($0.id) }
    }

    /// True while a download task runs, also a cancelled one that still releases its files.
    var isRunning: Bool { !tasks.isEmpty }

    func isDownloaded(_ recording: WorkIndex.Recording) -> Bool {
        downloads.contains { $0.id == recording.id }
    }

    /// True while an explicit download owns the track's transfer, so automatic preparation never cancels it.
    func isDownloading(_ songID: String) -> Bool {
        downloadTracks.values.contains { $0.contains(songID) }
    }

    /// What playback reads for a track: a file on the device, or the transfer of a format that starts early.
    func source(for song: Song, client: any ServerPort) async throws -> PlaybackSource {
        if let local = localFile(song) { return .file(local) }
        guard networkAllowed else { throw Failure.offline }
        if transport != nil, song.playbackTrack.canStartEarly { return .stream(transfer(for: song, client: client)) }
        return try await .file(file(for: song, client: client))
    }

    /// The local file of a track. A track that is not on the device downloads into the cache first.
    func file(for song: Song, client: any ServerPort) async throws -> URL {
        if let local = localFile(song) { return local }
        guard networkAllowed else { throw Failure.offline }
        if transport != nil { return try await transfer(for: song, client: client).finished() }
        if let running = fetches[song.id] { return try await running.value }
        let cached = cacheFolder.appending(path: Self.fileName(song))
        let task = Task {
            try await fetch(song, to: cached, client: client)
            return cached
        }
        fetches[song.id] = task
        defer { fetches[song.id] = nil }
        _ = try await task.value
        rescan()
        evict(keeping: cached)
        loaded?(song, cached, true)
        return cached
    }

    /// The transfer that playback of a track uses, started at once. Nil when the track is on the device, the
    /// network is off, or a test fetch loads whole files.
    func playbackTransfer(for song: Song, client: any ServerPort) -> TrackTransfer? {
        guard transport != nil, networkAllowed, !isOffline(song) else { return nil }
        return transfer(for: song, client: client)
    }

    /// The running transfer of a track, or a new one into the cache.
    @discardableResult
    func transfer(for song: Song, client: any ServerPort) -> TrackTransfer {
        if let running = transfers[song.id] { return running }
        let name = Self.fileName(song)
        let limit = cacheLimit
        let early = song.playbackTrack.canStartEarly
        let window = min(Self.rollingWindow, limit / 2)
        let transfer = TrackTransfer(
            songID: song.id, partial: cacheFolder.appending(path: name + ".\(UUID().uuidString).partial"),
            target: cacheFolder.appending(path: name), url: client.streamURL(songID: song.id), budget: budget,
            sizing: { length in
                // An unknown length stays whole; the Music limit then stops it, never an endless wait.
                guard let length, length > limit else { return .whole }
                return early ? .rolling(window) : .refuse
            },
            pressure: { [weak self] blocked in
                Task { @MainActor [weak self] in self?.relieve(blocked) }
            })
        transfers[song.id] = transfer
        transfer.whenFinished { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                guard self.transfers[transfer.songID] === transfer else { return }
                self.transferEnded(transfer)
                if transfer.hasCompleteFile { self.loaded?(song, transfer.target, false) }
            }
        }
        transport?(song, client, transfer)
        return transfer
    }

    /// Stops every transfer that no one needs any more. Their partial bytes go.
    func cancelTransfers(except kept: Set<String> = []) {
        let downloads = Set(downloadTracks.values.flatMap { $0 })
        var removed = false
        for (id, transfer) in transfers where !kept.contains(id) && !downloads.contains(id) {
            transfers[id] = nil
            transfer.cancel()
            removed = true
        }
        if removed { rescan() }
    }

    /// The Music limit blocks a write. Old files go first, then speculative transfers. Current playback stops
    /// with a storage failure only when nothing else can go (ADR 0060).
    private func relieve(_ blocked: TrackTransfer) {
        guard transfers[blocked.songID] === blocked else { return }
        // A rolling window needs only its own size, never room for the whole oversized resource.
        evict(room: blocked.storageNeed ?? TrackTransfer.rangeChunk)
        guard budget.availableBytes == 0 else { return }
        let downloading = Set(downloadTracks.values.flatMap { $0 })
        if !pinned.contains(blocked.songID) && !downloading.contains(blocked.songID) {
            transfers[blocked.songID] = nil
            blocked.cancel()
            rescan()
            return
        }
        var removed = false
        for (id, transfer) in transfers where transfer !== blocked && !downloading.contains(id) {
            // The next opening waits for the current track to play; then its file can go.
            guard !pinned.contains(id) || blocked.songID == playing else { continue }
            transfers[id] = nil
            transfer.cancel()
            removed = true
        }
        if removed { rescan() }
        // Other open files can still hold bytes; they close soon. Only a track that fills the limit alone fails.
        guard budget.availableBytes == 0, blocked.songID == playing, blocked.snapshot.available >= cacheLimit else {
            return
        }
        transfers[blocked.songID] = nil
        blocked.finish(.storage)
        rescan()
    }

    /// A new network path starts new throughput measurements.
    func networkPathChanged() {
        for transfer in transfers.values { transfer.restartMeasurement() }
    }

    private func transferEnded(_ transfer: TrackTransfer) {
        if transfers[transfer.songID] === transfer { transfers[transfer.songID] = nil }
        rescan()
        evict(keeping: transfer.target)
    }

    private func localFile(_ song: Song) -> URL? {
        let name = Self.fileName(song)
        let kept = downloadFolder.appending(path: name)
        if FileManager.default.fileExists(atPath: kept.path()) {
            loaded?(song, kept, true)
            return kept
        }
        let cached = cacheFolder.appending(path: name)
        guard FileManager.default.fileExists(atPath: cached.path()) else { return nil }
        // The modification date tells the cache which file was played last.
        try? FileManager.default.setAttributes([.modificationDate: Date.now], ofItemAtPath: cached.path())
        loaded?(song, cached, true)
        return cached
    }

    /// Downloads every track of a recording. It runs in the background; `progress` shows how far it is.
    func download(_ recording: WorkIndex.Recording, title: String, client: any ServerPort) {
        guard !isDownloaded(recording) else { return }
        if let running = tasks[recording.id] {
            // The menu shows the new download at once. It starts when the cancelled task released its files.
            guard running.isCancelled, restarts[recording.id] == nil else { return }
            failures[recording.id] = nil
            progress[recording.id] = 0
            restarts[recording.id] = { [weak self] in self?.download(recording, title: title, client: client) }
            return
        }
        failures[recording.id] = nil
        progress[recording.id] = 0
        downloadTracks[recording.id] = Set(recording.songs.map(\.id))
        remember(Pending(recording: recording, title: title))
        let generation = generation
        tasks[recording.id] = Task {
            do {
                var bytes: Int64 = 0
                for (index, song) in recording.songs.enumerated() {
                    try Task.checkCancellation()
                    let target = downloadFolder.appending(path: Self.fileName(song))
                    if !FileManager.default.fileExists(atPath: target.path()) {
                        let cached = cacheFolder.appending(path: Self.fileName(song))
                        // With a background session, only a transfer that runs already is shared: a new one would
                        // stop when the app is suspended.
                        if transport != nil, background == nil || transfers[song.id] != nil,
                            !FileManager.default.fileExists(atPath: cached.path())
                        {
                            // The download reuses the bytes that playback or read-ahead already loads. A wrapped
                            // rolling window lacks discarded bytes, so that track then loads whole below.
                            let shared = transfer(for: song, client: client)
                            if shared.promote() { _ = try await shared.finished() }
                            try Task.checkCancellation()
                        }
                        // Another recording can publish this shared track while the transfer wait suspends.
                        if !FileManager.default.fileExists(atPath: target.path()) {
                            if FileManager.default.fileExists(atPath: cached.path()) {
                                try FileManager.default.createDirectory(
                                    at: downloadFolder, withIntermediateDirectories: true)
                                try FileManager.default.moveItem(at: cached, to: target)
                            } else {
                                try await fetch(song, to: target, client: client)
                            }
                        }
                    }
                    guard generation == self.generation else { return }
                    try Task.checkCancellation()
                    loaded?(song, target, false)
                    bytes += Self.size(of: target)
                    progress[recording.id] = Double(index + 1) / Double(recording.songs.count)
                    rescan()
                }
                downloads.append(
                    Download(
                        id: recording.id, title: title, detail: recording.summary,
                        songIDs: recording.songs.map(\.id), bytes: bytes, date: .now))
                saveManifest()
            } catch {
                guard generation == self.generation else { return }
                // Failed recordings release their tracks only when no other explicit download owns them.
                let kept = Set(downloads.flatMap(\.songIDs)).union(
                    downloadTracks.filter { $0.key != recording.id }.values.flatMap { $0 })
                for song in recording.songs where !kept.contains(song.id) {
                    removeFiles(of: song.id, in: downloadFolder)
                }
                if !(error is CancellationError) { failures[recording.id] = error.localizedDescription }
            }
            guard generation == self.generation else { return }
            forget(recording.id)
            progress[recording.id] = nil
            tasks[recording.id] = nil
            downloadTracks[recording.id] = nil
            // A promoted transfer that playback still needs stays outside the limit until it ends.
            cancelTransfers(except: pinned.union(wanted))
            rescan()
            restarts.removeValue(forKey: recording.id)?()
        }
    }

    /// The download stops at once for the listener. Its task releases the files in the background.
    func cancelDownload(_ id: String) {
        restarts[id] = nil
        progress[id] = nil
        forget(id)
        tasks[id]?.cancel()
    }

    /// Removes a download. A track that another download also holds stays.
    func remove(_ download: Download) {
        downloads.removeAll { $0.id == download.id }
        let kept = Set(downloads.flatMap(\.songIDs))
        for id in download.songIDs where !kept.contains(id) { removeFiles(of: id, in: downloadFolder) }
        saveManifest()
        rescan()
    }

    func clearCache() {
        willClearMusic?()
        cancelTransfers()
        // An explicit download owns its shared partial file until it publishes the recording.
        let downloading = Set(downloadTracks.values.flatMap { $0 })
        for file in Self.files(in: cacheFolder) where !downloading.contains(file.id) {
            try? FileManager.default.removeItem(at: file.url)
        }
        rescan()
    }

    /// Signing out removes everything the account stored.
    func clearAll() {
        generation += 1
        downloadTracks = [:]
        cancelTransfers()
        for task in tasks.values { task.cancel() }
        tasks = [:]
        restarts = [:]
        progress = [:]
        pending = []
        try? FileManager.default.removeItem(at: pendingURL)
        for task in fetches.values { task.cancel() }
        fetches = [:]
        downloads = []
        try? FileManager.default.removeItem(at: downloadFolder)
        try? FileManager.default.removeItem(at: manifestURL)
        clearCache()
    }

    /// Reads both folders again. The sets in this object follow the files, not the other way round.
    func rescan() {
        let cached = Self.files(in: cacheFolder)
        let kept = Self.files(in: downloadFolder)
        // Partial bytes count under Music, but only a complete file plays offline (ADR 0060).
        cacheBytes = cached.reduce(0) { $0 + $1.size }
        downloadBytes = kept.reduce(0) { $0 + $1.size }
        offline = Set((cached + kept).filter { !$0.isPartial }.map(\.id))
        budget.synchronize(Dictionary(cached.map { ($0.url, $0.size) }, uniquingKeysWith: { $1 }))
    }

    /// Deletes the least recently played cache files until every automatic byte, plus `room`, fits the limit.
    /// Partial files, the current track, the next opening and tracks of a running download stay.
    func evict(keeping keep: URL? = nil, room: Int64 = 0) {
        rescan()
        var excess = budget.storedBytes + max(room, 0) - cacheLimit
        guard excess > 0 else { return }
        let downloading = Set(downloadTracks.values.flatMap { $0 })
        for file in Self.files(in: cacheFolder).sorted(by: { $0.date < $1.date }) where excess > 0 {
            if file.url == keep || file.isPartial || pinned.contains(file.id) || downloading.contains(file.id) {
                continue
            }
            try? FileManager.default.removeItem(at: file.url)
            excess -= file.size
        }
        rescan()
    }

    private func fetch(_ song: Song, to target: URL, client: any ServerPort) async throws {
        let temporary: URL
        if let background {
            temporary = try await background(song, client)
        } else {
            temporary = try await load(song, client)
        }
        defer { try? FileManager.default.removeItem(at: temporary) }
        try Task.checkCancellation()
        try FileManager.default.createDirectory(
            at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: target)
        try FileManager.default.moveItem(at: temporary, to: target)
    }

    private static let stream: Fetch = { song, client in
        let (temporary, response) = try await URLSession.shared.download(from: client.streamURL(songID: song.id))
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw SubsonicError.http(status: http.statusCode)
        }
        return temporary
    }

    private func saveManifest() {
        try? FileManager.default.createDirectory(at: downloadFolder, withIntermediateDirectories: true)
        // A download can load again from the server, so it does not belong in the device backup.
        var folder = downloadFolder
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? folder.setResourceValues(values)
        if let data = try? JSONEncoder().encode(downloads) { try? data.write(to: manifestURL, options: .atomic) }
    }

    private func removeFiles(of songID: String, in folder: URL) {
        for file in Self.files(in: folder) where file.id == songID { try? FileManager.default.removeItem(at: file.url) }
    }

    private struct StoredFile {
        var url: URL
        var id: String
        var size: Int64
        var date: Date
        var isPartial: Bool { url.pathExtension == "partial" }
    }

    private static func files(in folder: URL) -> [StoredFile] {
        let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey]
        let urls = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys)) ?? []
        return urls.map { url in
            let values = try? url.resourceValues(forKeys: Set(keys))
            var track = url.pathExtension == "partial" ? url.deletingPathExtension() : url
            // A transfer owns its path until its last decoder closes, including after a replacement starts.
            if url.pathExtension == "partial", UUID(uuidString: track.pathExtension) != nil {
                track = track.deletingPathExtension()
            }
            return StoredFile(
                url: url, id: track.deletingPathExtension().lastPathComponent, size: Int64(values?.fileSize ?? 0),
                date: values?.contentModificationDate ?? .distantPast)
        }
    }

    private static func size(of url: URL) -> Int64 {
        Int64((try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
    }

    private static func fileName(_ song: Song) -> String { "\(song.id).\(song.suffix ?? "mp3")" }
}
