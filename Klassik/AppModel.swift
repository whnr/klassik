import Foundation
import Observation

@MainActor @Observable
final class AppModel {
    private(set) var credentials: ServerCredentials? {
        didSet { updateServer() }
    }
    private(set) var serverInfo: ServerInfo?
    private(set) var lastCheck: Date?
    private(set) var lastError: String?
    private(set) var lastErrorDate: Date?
    private(set) var isChecking = false
    /// True while a finger scrubs the timeline or the position bar. The rows of the player stay still until it
    /// lifts (ADR 0027).
    var isScrubbing = false

    let library: Library
    private(set) var recordingOrder: RecordingOrder
    /// Listening notes share the device file with the favourites (ADR 0013).
    private(set) var notes: ListeningNotes
    /// Recent searches share the device file too; they never reach the server (ADR 0029).
    private(set) var recentSearches: RecentSearches
    let tracks: TrackStore
    let covers = CoverArt.Cache()
    let pictures = ImageStore.pictures
    let albumArt = ImageStore.albumArt
    let albumCovers: AlbumCovers
    let playback: PlaybackSession
    /// The timeline and the mini player show while an item is in playback; the page insets follow them.
    var showsTimeline: Bool { playback.item != nil }
    let enrichment: Enrichment
    let people: PersonFactsStore
    let sweep: PersonSweep
    let swipes = SwipeSettings()
    let libraryRows = LibraryRows()
    let chronology = ChronologyPlace()
    @ObservationIgnored private var reconnect: ConnectionMonitor?
    private let store: CredentialStore

    var client: SubsonicClient? { credentials.map { SubsonicClient(credentials: $0) } }

    init(store: CredentialStore = CredentialStore(), library: Library = Library()) {
        self.store = store
        self.library = library
        recordingOrder = RecordingOrder(library: library)
        notes = ListeningNotes(store: nil)
        recentSearches = RecentSearches(store: nil)
        tracks = TrackStore()
        albumCovers = AlbumCovers(store: ImageStore.albumArt)
        playback = PlaybackSession(engine: GaplessEngine(), store: tracks)
        enrichment = Enrichment.forLaunch()
        people = PersonFactsStore.forLaunch()
        let connection = ConnectionMonitor()
        sweep = PersonSweep(
            store: people, isConnectionGood: { connection.isGood },
            pictures: { portrait, old in
                await PortraitLoader.keep(
                    portrait, replacing: old, screen: PortraitLoader.deviceScreen, store: .pictures)
            },
            hasPicture: { portrait in
                await ImageStore.pictures.loaded()
                return PortraitLoader.isKept(portrait)
            })
        // UI tests start from the connect screen.
        if ProcessInfo.processInfo.arguments.contains("-resetServer") {
            store.clear()
            library.clear()
            tracks.clearAll()
            albumArt.clear()
            albumCovers.clear()
            pictures.clear()
            enrichment.clear()
            people.clear()
            libraryRows.reset()
            chronology.clear()
        }
        credentials = store.load()
        updateServer()
        tracks.loaded = { [weak self] song, file, playing in
            guard let self else { return }
            albumCovers.inspect(song, file: file)
            // Playback fetches its cover in Low Data Mode too (ADR 0059).
            if playing { albumCovers.request(song, playback: true) }
        }
        library.classicalChanged = { [weak self] in self?.planCovers() }
        reconnect = ConnectionMonitor { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.keepAlbumArt()
                Self.start(self.sweep, over: self.library.index)
                await Self.synchronizeAfterReconnect(
                    order: self.recordingOrder,
                    listening: { await self.playback.synchronizeListeningData() })
            }
        }
        // No build reads the URL cache folder of the pictures, so its space goes back to the device.
        Task.detached(priority: .utility) {
            try? FileManager.default.removeItem(at: .cachesDirectory.appending(path: "Portraits"))
        }
    }

    /// Favourites need `refresh`, not `synchronize`: the connection may have been down while another device
    /// changed a star, and only a read picks that up. Both run at once.
    static func synchronizeAfterReconnect(
        order: RecordingOrder,
        listening: @escaping @MainActor () async -> Void
    ) async {
        async let favouritesDone: Void = order.refresh()
        async let listeningDone: Void = listening()
        _ = await (favouritesDone, listeningDone)
    }

    /// Returns the error text if the server rejects the login; nothing is saved then.
    func connect(_ candidate: ServerCredentials) async -> String? {
        do {
            let info = try await SubsonicClient(credentials: candidate).ping()
            credentials = candidate
            serverInfo = info
            lastCheck = .now
            do { try store.save(candidate) } catch { record(error) }
            return nil
        } catch {
            record(error)
            return error.localizedDescription
        }
    }

    /// Shows the cached library at once, then checks the server and syncs again.
    /// Then looks up the works on MusicBrainz and the persons on Wikidata, side by side.
    /// Why changes of the listener wait on this iPhone: favourites, scrobbles and the play queue together.
    var serverTrouble: ServerTrouble? {
        ServerTrouble.worst([recordingOrder.serverTrouble, playback.listeningTrouble])
    }

    func start() async {
        guard let credentials, let client else { return }
        await library.load(for: credentials)
        sweepPeople()
        // The UI walk requires a fresh player on each reset launch.
        if !ProcessInfo.processInfo.arguments.contains("-resetServer") { await playback.restoreQueue() }
        await check()
        await library.syncIfChanged(with: client)
        keepAlbumArt()
        await recordingOrder.refresh()
        await Self.enrich(library.index, enrichment: enrichment, sweep: sweep)
    }

    /// Starts the Wikidata pass over the persons, then runs the MusicBrainz pass beside it (ADR 0042). The person
    /// pass reads the names in the tags only, so it does not wait for MusicBrainz.
    static func enrich(_ index: WorkIndex, enrichment: Enrichment, sweep: PersonSweep) async {
        start(sweep, over: index)
        await enrichment.enrich(index)
    }

    /// Starts the background pass over the persons of the library. Nothing runs while it runs already.
    func sweepPeople() {
        Self.start(sweep, over: library.index)
    }

    private static func start(_ sweep: PersonSweep, over index: WorkIndex) {
        let people = PersonSweep.people(of: index)
        sweep.measure(people)
        sweep.start(people)
    }

    /// The pass that the system starts while Klassik is in the background. It ends when the pass ends or the
    /// system takes the time away.
    func sweepPeopleInBackground() async {
        if library.index.composers.isEmpty, let credentials { await library.load(for: credentials) }
        sweepPeople()
        await sweep.finish()
    }

    /// Starts the pass that keeps the cover of every classical album disc on the device (ADR 0059). A full sync
    /// fetches every cover again and keeps each old one until its replacement is stored.
    func keepAlbumArt(full: Bool = false) {
        guard credentials != nil else { return }
        albumCovers.keepAll(full: full)
    }

    /// The covers follow the classical filter: an album that it keeps out gets no cover fetch.
    private func planCovers() {
        albumCovers.plan(classical: library.classical, library: library.songs)
    }

    /// Pull to refresh: the full sync of ADR 0059 reads the library again and refreshes every cover.
    func fullSync() async {
        guard let client else { return }
        await library.sync(with: client)
        keepAlbumArt(full: true)
        Task {
            await sweep.finish()
            sweepPeople()
        }
    }

    /// Album Art Clear. The next library sync and every page that opens fetch the covers again.
    func clearAlbumArt() {
        albumArt.clear()
        albumCovers.clear()
        covers.clear()
    }

    func check() async {
        guard let credentials, !isChecking else { return }
        isChecking = true
        defer { isChecking = false }
        do {
            serverInfo = try await SubsonicClient(credentials: credentials).ping()
            lastCheck = .now
        } catch {
            record(error)
        }
    }

    func signOut() {
        playback.server = nil
        albumCovers.signOut()
        tracks.clearAll()
        albumArt.clear()
        store.clear()
        library.clear()
        credentials = nil
        serverInfo = nil
        lastCheck = nil
    }

    /// The playback session reaches the server through the saved login.
    private func updateServer() {
        covers.clear()
        albumCovers.attach(credentials)
        playback.server = client
        let deviceStore = credentials.map { DeviceStore(server: $0.url, username: $0.username) }
        // Each UI walk must start with the same local favourites and order.
        if ProcessInfo.processInfo.arguments.contains("-resetServer") { try? deviceStore?.delete() }
        var favourites: (any FavouriteServer)? = client
        #if DEBUG
            // The UI walk reads the fixture library but cannot reach the server for a star.
            if ProcessInfo.processInfo.arguments.contains("-offlineFavourites"), let client {
                favourites = OfflineFavourites(client: client)
            }
        #endif
        let file = ListenerFile(store: deviceStore)
        recordingOrder = RecordingOrder(library: library, file: file, server: favourites)
        notes = ListeningNotes(file: file)
        recentSearches = RecentSearches(file: file)
    }

    private func record(_ error: Error) {
        lastError = error.localizedDescription
        lastErrorDate = .now
    }
}
