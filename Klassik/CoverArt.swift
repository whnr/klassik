import AVFoundation
import ImageIO
import UIKit

@MainActor enum CoverArt {
    /// The longest side of the kept copy: the page cover at the 3x scale of the largest iPhone screens.
    nonisolated static let storedPixels = Int(Measure.coverPage) * 3

    /// The key of an album cover of the 0.14 builds. `AlbumCovers` adopts those files once.
    nonisolated static func storeKey(album: String, credentials: ServerCredentials) -> String {
        [account(credentials), album].joined(separator: "\n")
    }

    /// The account holds the server and the user but not the password, so that a new password keeps the art.
    nonisolated static func account(_ credentials: ServerCredentials) -> String {
        [credentials.url.absoluteString, credentials.username].joined(separator: "\n")
    }

    /// Decoded covers by content name and size. List updates must keep loaded covers visible while the files
    /// load again.
    final class Cache {
        private let images = NSCache<NSString, UIImage>()

        init() { images.totalCostLimit = 32 * 1_024 * 1_024 }

        func image(hash: String, pixels: Int) -> UIImage? {
            images.object(forKey: Self.key(hash, pixels))
        }

        func store(_ image: UIImage, hash: String, pixels: Int) {
            let cost = image.cgImage.map { $0.bytesPerRow * $0.height } ?? 1
            images.setObject(image, forKey: Self.key(hash, pixels), cost: cost)
        }

        func clear() { images.removeAllObjects() }

        private static func key(_ hash: String, _ pixels: Int) -> NSString { "\(hash)/\(pixels)" as NSString }
    }

    /// The art that an audio file holds, as one kept copy, or nil when the file holds no valid image.
    static func embeddedCover(in file: URL) async -> Data? {
        let flac = await Task.detached(priority: .utility) { FLACArtwork.data(in: file) }.value
        if let flac, let data = await normalized(flac) { return data }
        let asset = AVURLAsset(url: file)
        guard let metadata = try? await asset.load(.commonMetadata) else { return nil }
        for item in AVMetadataItem.metadataItems(from: metadata, filteredByIdentifier: .commonIdentifierArtwork) {
            if let raw = try? await item.load(.dataValue), let data = await normalized(raw) { return data }
        }
        return nil
    }

    /// Art larger than the kept copy scales down to it, so that embedded art takes no more room than a server
    /// cover. Smaller art keeps its bytes. Nil: the bytes are no image.
    nonisolated static func normalized(_ data: Data) async -> Data? {
        await Task.detached(priority: .utility) { () -> Data? in
            guard let source = CGImageSourceCreateWithData(data as CFData, nil), CGImageSourceGetCount(source) > 0,
                let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                let width = properties[kCGImagePropertyPixelWidth] as? Int,
                let height = properties[kCGImagePropertyPixelHeight] as? Int, width > 0, height > 0
            else { return nil }
            guard max(width, height) > storedPixels else { return UIImage(data: data) == nil ? nil : data }
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: storedPixels,
            ]
            guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
                return nil
            }
            return UIImage(cgImage: image).jpegData(compressionQuality: 0.9)
        }.value
    }

    /// The art in `ImageStore.albumArt` is the only copy on the device.
    nonisolated static let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.urlCache = nil
        return URLSession(configuration: configuration)
    }()

    /// The image at most `pixels` on its longest side. A list row needs a small copy of a large kept picture,
    /// and decoding the small copy only saves memory. Zero keeps the full size.
    nonisolated static func scaled(_ data: Data, to pixels: Int) async -> UIImage? {
        await Task.detached(priority: .userInitiated) { () -> UIImage? in
            guard pixels > 0, let source = CGImageSourceCreateWithData(data as CFData, nil) else {
                return UIImage(data: data)
            }
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: pixels,
            ]
            guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
                return UIImage(data: data)
            }
            return UIImage(cgImage: image)
        }.value
    }

    /// The largest centred square of the image, at most `pixels` on a side. Album art shows square everywhere,
    /// whatever its shape (sz-rs30.1.105.82). The short side decodes at `pixels`, so the square keeps its detail.
    nonisolated static func square(_ data: Data, to pixels: Int) async -> UIImage? {
        await Task.detached(priority: .userInitiated) { () -> UIImage? in
            guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                let width = properties[kCGImagePropertyPixelWidth] as? Int,
                let height = properties[kCGImagePropertyPixelHeight] as? Int, width > 0, height > 0
            else { return UIImage(data: data) }
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: squareLimit(width: width, height: height, pixels: pixels),
            ]
            guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
                return UIImage(data: data)
            }
            return UIImage(cgImage: centreSquare(of: image))
        }.value
    }

    /// The long side to decode so that the short side reaches `pixels`, never above the full size. Zero keeps the
    /// full size. The orientation swaps the sides but keeps their ratio.
    nonisolated static func squareLimit(width: Int, height: Int, pixels: Int) -> Int {
        let long = max(width, height)
        let short = max(min(width, height), 1)
        guard pixels > 0 else { return long }
        return min(long, Int((Double(pixels) * Double(long) / Double(short)).rounded(.up)))
    }

    /// The centred square of an image, as wide as its short side.
    nonisolated static func centreSquare(of image: CGImage) -> CGImage {
        guard image.width != image.height else { return image }
        let side = min(image.width, image.height)
        let rect = CGRect(x: (image.width - side) / 2, y: (image.height - side) / 2, width: side, height: side)
        return image.cropping(to: rect) ?? image
    }
}

/// The cover links of one account: each album disc and each track with embedded art points at one content file of
/// `ImageStore.albumArt` (ADR 0059).
struct CoverLinks: Codable, Equatable, Sendable {
    struct Link: Codable, Equatable, Sendable {
        /// The content name of the file.
        var hash: String
        /// The cover ID that gave the file. Another ID on the server means another cover.
        var source: String
    }

    var discs: [String: Link] = [:]
    /// Embedded art by track ID. It wins over the disc cover of the track.
    var tracks: [String: String] = [:]
    /// Discs that a full sync must fetch again. A failed refresh stays here until it succeeds.
    var refresh: Set<String> = []

    init() {}

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        discs = try container.decodeIfPresent([String: Link].self, forKey: .discs) ?? [:]
        tracks = try container.decodeIfPresent([String: String].self, forKey: .tracks) ?? [:]
        refresh = try container.decodeIfPresent(Set<String>.self, forKey: .refresh) ?? []
    }

    func references(_ hash: String) -> Bool {
        tracks.values.contains(hash) || discs.values.contains { $0.hash == hash }
    }
}

/// One album disc and the cover ID that gives its art.
struct CoverJob: Equatable, Sendable {
    var key: String
    var album: String
    var source: String
}

enum CoverPlan {
    /// A disc without a number keeps its own key: it is not disc one.
    static func key(album: String, disc: Int?) -> String {
        "\(album)\n\(disc.map(String.init) ?? "?")"
    }

    static func key(of song: Song) -> String { key(album: song.albumKey, disc: song.discNumber) }

    /// Each album disc once, in library order. A disc takes the cover ID of its first track that has one. A disc
    /// without one takes the cover of the album: the one of its lowest disc with a cover ID. An album without any
    /// cover ID has no job.
    static func jobs(_ songs: [Song]) -> [CoverJob] {
        struct Disc {
            var album: String
            var number: Int?
            var pick: (track: Int, id: String, source: String)?
        }
        var discs: [String: Disc] = [:]
        var order: [String] = []
        for song in songs {
            let key = key(of: song)
            if discs[key] == nil {
                order.append(key)
                discs[key] = Disc(album: song.albumKey, number: song.discNumber)
            }
            guard let source = song.coverArt, !source.isEmpty else { continue }
            let pick = (track: song.track ?? .max, id: song.id, source: source)
            if let old = discs[key]?.pick, (old.track, old.id) <= (pick.track, pick.id) { continue }
            discs[key]?.pick = pick
        }
        var albums: [String: (number: Int, source: String)] = [:]
        for key in order {
            guard let disc = discs[key], let pick = disc.pick else { continue }
            let number = disc.number ?? .max
            if let old = albums[disc.album], old.number <= number { continue }
            albums[disc.album] = (number, pick.source)
        }
        return order.compactMap { key in
            guard let disc = discs[key], let source = disc.pick?.source ?? albums[disc.album]?.source else {
                return nil
            }
            return CoverJob(key: key, album: disc.album, source: source)
        }
    }
}

/// The order of the disc covers to check. A page or the playback puts its discs in front of the pass.
struct CoverQueue: Equatable {
    enum Reason: Int, Comparable {
        /// The pass over the library. It stops on the first failure.
        case pass
        /// A page shows the cover.
        case page
        /// The cover of what starts playing. It loads in Low Data Mode too.
        case playback

        static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
    }

    private var storage: [String] = []
    private var cursor = 0
    var keys: [String] { Array(storage[cursor...]) }
    private(set) var reasons: [String: Reason] = [:]

    var isEmpty: Bool { cursor == storage.count }

    /// Adds the keys at the end. A key in the queue keeps its place.
    mutating func append(_ added: [String]) {
        for key in added where reasons[key] == nil {
            storage.append(key)
            reasons[key] = .pass
        }
    }

    /// Moves the keys to the front, in their order. A key keeps its strongest reason.
    mutating func front(_ moved: [String], reason: Reason) {
        var seen: Set<String> = []
        let unique = moved.filter { seen.insert($0).inserted }
        storage = unique + storage[cursor...].filter { !seen.contains($0) }
        cursor = 0
        for key in unique { reasons[key] = max(reasons[key] ?? reason, reason) }
    }

    mutating func pop() -> (key: String, reason: Reason)? {
        guard !isEmpty else { return nil }
        let key = storage[cursor]
        cursor += 1
        if isEmpty {
            storage.removeAll(keepingCapacity: true)
            cursor = 0
        }
        return (key, reasons.removeValue(forKey: key) ?? .pass)
    }

    /// Ends the pass. The page and playback requests stay.
    mutating func dropPass() {
        storage = storage[cursor...].filter { reasons[$0] != .pass }
        cursor = 0
        reasons = reasons.filter { $0.value != .pass }
    }
}

/// Keeps a cover for every album disc that passes the classical filter, before a page needs it (ADR 0059).
/// Pages read the links at once and ask for the covers that they miss.
@MainActor @Observable
final class AlbumCovers {
    typealias Fetch = @MainActor (URLRequest) async throws -> (Data, URLResponse)

    private(set) var links = CoverLinks()
    /// Counts the stored covers of each disc. A view loads again on a change, also when the link stays the same
    /// because the server sent the same bytes.
    private(set) var arrivals: [String: Int] = [:]

    @ObservationIgnored private var jobs: [String: CoverJob] = [:]
    @ObservationIgnored private var order: [String] = []
    /// Every album of the library, for the files of the 0.14 builds.
    @ObservationIgnored private var libraryAlbums: Set<String> = []
    @ObservationIgnored private var eligibleAlbums: Set<String> = []
    /// Files stay until the replacement links reach disk.
    @ObservationIgnored private var pendingRelease: Set<String> = []
    @ObservationIgnored private var adopted = false
    @ObservationIgnored private var queue = CoverQueue()
    /// The file of each cover ID in this pass, so that discs with one ID cost one download.
    @ObservationIgnored private var passSources: [String: String] = [:]
    /// Tracks that were read for embedded art in this session.
    @ObservationIgnored private var inspected: Set<String> = []
    @ObservationIgnored private var inspection: Task<Void, Never>?
    @ObservationIgnored private var worker: Task<Void, Never>?
    @ObservationIgnored private var workerID = UUID()
    @ObservationIgnored private var save: Task<Void, Never>?
    @ObservationIgnored private var saveQueued = false
    @ObservationIgnored private var saveFailed = false
    @ObservationIgnored private var credentials: ServerCredentials?
    @ObservationIgnored private var file: URL?
    let store: ImageStore
    private let folder: URL
    private let fetch: Fetch

    init(
        store: ImageStore, folder: URL = .applicationSupportDirectory.appending(path: "covers"),
        fetch: @escaping Fetch = { try await CoverArt.session.data(for: $0) }
    ) {
        self.store = store
        self.folder = folder
        self.fetch = fetch
    }

    // MARK: Account

    /// Reads the links of the account. A new password keeps them.
    func attach(_ credentials: ServerCredentials?) {
        let next = credentials.map { folder.appending(path: ImageStore.name(CoverArt.account($0)) + ".json") }
        self.credentials = credentials
        guard next != file else { return }
        stop()
        file = next
        // The links load before the first frame, so that a page never shows a placeholder for a kept cover.
        links = next.flatMap { try? JSONDecoder().decode(CoverLinks.self, from: Data(contentsOf: $0)) } ?? CoverLinks()
        arrivals = [:]
        jobs = [:]
        order = []
        adopted = false
        inspected = []
        pendingRelease = []
        saveFailed = false
    }

    /// Signing out removes the links of the account. The caller clears the files.
    func signOut() {
        let file = file
        attach(nil)
        guard let file else { return }
        let previous = save
        save = Task {
            await previous?.value
            await Task.detached(priority: .utility) { try? FileManager.default.removeItem(at: file) }.value
        }
    }

    /// Album Art Clear removed the files, so no link holds.
    func clear() {
        stop()
        links = CoverLinks()
        arrivals = [:]
        inspected = []
        scheduleSave()
    }

    private func stop() {
        worker?.cancel()
        worker = nil
        workerID = UUID()
        queue = CoverQueue()
        passSources = [:]
    }

    // MARK: Plan

    /// The discs to keep: those of the classical albums. Every other cover stays off the device.
    func plan(classical: [Song], library: [Song]) {
        let planned = CoverPlan.jobs(classical)
        jobs = Dictionary(planned.map { ($0.key, $0) }) { first, _ in first }
        order = planned.map(\.key)
        libraryAlbums = Set(library.map(\.albumKey))
        eligibleAlbums = Set(classical.map(\.albumKey))
        keepAll()
    }

    /// Checks every planned disc. It fetches the missing covers and those with a new cover ID. A full sync
    /// fetches every cover again and keeps each old one until its replacement is stored.
    func keepAll(full: Bool = false) {
        if saveFailed { scheduleSave() }
        passSources = [:]
        if full {
            links.refresh = Set(order)
            scheduleSave()
        }
        queue.append(order)
        run()
    }

    /// A page shows the cover of the song. A missing one goes to the front of the queue.
    func request(_ song: Song, playback: Bool = false) {
        let key = CoverPlan.key(of: song)
        guard jobs[key] != nil else { return }
        queue.front([key], reason: playback ? .playback : .page)
        run()
    }

    /// A person page puts all its covers in front of the queue.
    func prefer(_ songs: [Song]) {
        let keys = songs.map(CoverPlan.key(of:)).filter { jobs[$0] != nil }
        guard !keys.isEmpty else { return }
        queue.front(keys, reason: .page)
        run()
    }

    /// The files to show for the song, best first: its embedded art, then the cover of its disc.
    func candidates(for song: Song) -> [String] {
        guard eligibleAlbums.contains(song.albumKey) else { return [] }
        let legacy = credentials.map { ImageStore.name(CoverArt.storeKey(album: song.albumKey, credentials: $0)) }
        let disc =
            links.discs[CoverPlan.key(of: song)]?.hash
            ?? legacy.flatMap { store.contains(named: $0) ? $0 : nil }
        guard let track = links.tracks[song.id] else { return disc.map { [$0] } ?? [] }
        guard let disc, disc != track else { return [track] }
        return [track, disc]
    }

    func arrival(for song: Song) -> Int { arrivals[CoverPlan.key(of: song)] ?? 0 }

    /// The best kept cover of the song, square, for the system players. Nil while the device keeps none.
    func playbackImage(for song: Song) async -> UIImage? {
        for hash in candidates(for: song) {
            if let data = await store.data(named: hash),
                let image = await CoverArt.square(data, to: CoverArt.storedPixels)
            {
                return image
            }
        }
        return nil
    }

    /// Returns when the queue is empty, the embedded art is read and the links are saved.
    func idle() async {
        while let worker {
            await worker.value
        }
        await inspection?.value
        await save?.value
    }

    // MARK: Embedded art

    /// A track file loaded for playback or a download. Its embedded art replaces the disc cover of this track
    /// only. Missing or invalid art changes nothing.
    func inspect(_ song: Song, file audio: URL) {
        guard eligibleAlbums.contains(song.albumKey) else { return }
        guard inspected.insert(song.id).inserted else { return }
        if let kept = links.tracks[song.id], store.contains(named: kept) { return }
        let account = file
        let previous = inspection
        inspection = Task {
            await previous?.value
            guard let data = await CoverArt.embeddedCover(in: audio), account == self.file,
                let hash = await store.store(content: data), account == self.file
            else { return }
            guard eligibleAlbums.contains(song.albumKey) else { return }
            let old = links.tracks[song.id]
            links.tracks[song.id] = hash
            if let old, old != hash { pendingRelease.insert(old) }
            scheduleSave()
        }
    }

    // MARK: Work

    private func run() {
        guard worker == nil, !queue.isEmpty else { return }
        let id = UUID()
        workerID = id
        worker = Task { [weak self] in
            await self?.work()
            if self?.workerID == id { self?.worker = nil }
        }
    }

    private func work() async {
        await store.loaded()
        await adoptOldFiles()
        while !Task.isCancelled, let next = queue.pop() {
            let key = next.key
            guard let job = jobs[key] else { continue }
            let refresh = links.refresh.contains(key)
            if !refresh, let link = links.discs[key], link.source == job.source, store.contains(named: link.hash) {
                continue
            }
            if let hash = passSources[job.source], store.contains(named: hash) {
                link(key, to: hash, source: job.source)
                continue
            }
            let outcome = await download(job, reason: next.reason)
            guard !Task.isCancelled else { return }
            switch outcome {
            case .stored(let hash):
                passSources[job.source] = hash
                link(key, to: hash, source: job.source)
            case .invalid:
                continue
            case .stopped:
                if next.reason == .pass { queue.dropPass() }
            case .storage:
                queue.dropPass()
            }
        }
    }

    private enum Outcome {
        case stored(String)
        /// The server has no valid image. The old cover stays.
        case invalid
        /// No answer. The work waits for the next pass or page.
        case stopped
        /// The device did not write the file.
        case storage
    }

    private func download(_ job: CoverJob, reason: CoverQueue.Reason) async -> Outcome {
        guard let credentials else { return .stopped }
        let client = SubsonicClient(credentials: credentials)
        var request = URLRequest(url: client.coverArtURL(id: job.source, size: CoverArt.storedPixels))
        request.allowsConstrainedNetworkAccess = reason == .playback
        guard let answer = try? await fetch(request) else { return .stopped }
        let data = answer.0
        guard let http = answer.1 as? HTTPURLResponse, (200..<300).contains(http.statusCode),
            UIImage(data: data) != nil
        else { return .invalid }
        guard let hash = await store.store(content: data) else { return .storage }
        return .stored(hash)
    }

    /// The link changes after the file is stored. The old file goes only when no other link needs it.
    private func link(_ key: String, to hash: String, source: String) {
        let old = links.discs[key]?.hash
        links.discs[key] = CoverLinks.Link(hash: hash, source: source)
        links.refresh.remove(key)
        arrivals[key, default: 0] += 1
        if let old, old != hash { pendingRelease.insert(old) }
        scheduleSave()
    }

    private func release(_ hash: String) {
        if !links.references(hash) { store.remove(named: hash) }
    }

    /// The 0.14 builds kept one file per album under a key name. Each such file serves its discs until the pass
    /// replaces it with the disc cover, so the upgrade shows no placeholder.
    private func adoptOldFiles() async {
        guard !adopted, let credentials, !libraryAlbums.isEmpty else { return }
        var complete = true
        var discsOfAlbum: [String: [String]] = [:]
        for key in order {
            if let album = jobs[key]?.album { discsOfAlbum[album, default: []].append(key) }
        }
        for album in libraryAlbums {
            let name = ImageStore.name(CoverArt.storeKey(album: album, credentials: credentials))
            guard store.contains(named: name) else { continue }
            let discs = (discsOfAlbum[album] ?? []).filter { links.discs[$0] == nil }
            if !discs.isEmpty, let data = await store.data(named: name),
                let hash = await store.store(content: data)
            {
                // No cover ID is empty, so the pass fetches the disc cover and replaces this one.
                for key in discs { links.discs[key] = CoverLinks.Link(hash: hash, source: "") }
                pendingRelease.insert(name)
            } else if !discs.isEmpty {
                complete = false
                continue
            } else if !eligibleAlbums.contains(album) || discsOfAlbum[album] != nil {
                pendingRelease.insert(name)
            }
        }
        adopted = complete
        scheduleSave()
    }

    private func scheduleSave() {
        guard !saveQueued, let file else { return }
        saveQueued = true
        let previous = save
        save = Task {
            await previous?.value
            // Links that change together save in one write.
            await Task.yield()
            saveQueued = false
            guard self.file == file else { return }
            let snapshot = self.links
            let releases = pendingRelease
            let written = await Task.detached(priority: .utility) {
                do {
                    try FileManager.default.createDirectory(
                        at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try JSONEncoder().encode(snapshot).write(to: file, options: .atomic)
                    return true
                } catch { return false }
            }.value
            guard self.file == file else { return }
            saveFailed = !written
            guard written else { return }
            for hash in releases where !snapshot.references(hash) && !links.references(hash) {
                release(hash)
                pendingRelease.remove(hash)
            }
        }
    }
}
