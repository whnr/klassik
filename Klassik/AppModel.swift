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

    let library: Library
    let tracks: TrackStore
    let playback: PlaybackSession
    let enrichment: Enrichment
    let people: PersonFactsStore
    let swipes = SwipeSettings()
    let libraryRows = LibraryRows()
    private let store: CredentialStore

    var client: SubsonicClient? { credentials.map { SubsonicClient(credentials: $0) } }

    init(store: CredentialStore = CredentialStore(), library: Library = Library()) {
        self.store = store
        self.library = library
        tracks = TrackStore()
        playback = PlaybackSession(engine: GaplessEngine(), store: tracks)
        enrichment = Enrichment.forLaunch()
        people = PersonFactsStore()
        // UI tests start from the connect screen.
        if ProcessInfo.processInfo.arguments.contains("-resetServer") {
            store.clear()
            library.clear()
            tracks.clearAll()
            enrichment.clear()
            people.clear()
            libraryRows.reset()
        }
        credentials = store.load()
        updateServer()
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
    /// Then looks up the works that MusicBrainz has not described yet.
    func start() async {
        guard let credentials, let client else { return }
        await library.load(for: credentials)
        // The UI walk requires a fresh player on each reset launch.
        if !ProcessInfo.processInfo.arguments.contains("-resetServer") { await playback.restoreQueue() }
        await check()
        await library.syncIfChanged(with: client)
        await enrichment.enrich(library.index)
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

    /// Makes a recording the reference of its work: the server stars its tracks and unstars the other recordings.
    /// Returns the error text if the server fails.
    func setReference(_ recording: WorkIndex.Recording, of work: WorkIndex.Work, to reference: Bool) async -> String? {
        guard let client else { return "Not connected." }
        let own = recording.songs.map(\.id)
        let others = work.recordings.filter { $0.id != recording.id }.flatMap(\.songs).filter { $0.starred != nil }
            .map(\.id)
        do {
            if reference {
                try await client.star(own)
                if !others.isEmpty { try await client.unstar(others) }
                library.setStarred(Set(own), true)
                library.setStarred(Set(others), false)
            } else {
                try await client.unstar(own)
                library.setStarred(Set(own), false)
            }
            return nil
        } catch {
            record(error)
            return error.localizedDescription
        }
    }

    func signOut() {
        playback.server = nil
        tracks.clearAll()
        store.clear()
        library.clear()
        credentials = nil
        serverInfo = nil
        lastCheck = nil
    }

    /// The playback session reaches the server through the saved login.
    private func updateServer() {
        playback.server = client
    }

    private func record(_ error: Error) {
        lastError = error.localizedDescription
        lastErrorDate = .now
    }
}
