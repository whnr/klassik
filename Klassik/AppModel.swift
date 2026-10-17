import Foundation
import Observation

@MainActor @Observable
final class AppModel {
    private(set) var credentials: ServerCredentials?
    private(set) var serverInfo: ServerInfo?
    private(set) var lastCheck: Date?
    private(set) var lastError: String?
    private(set) var lastErrorDate: Date?
    private(set) var isChecking = false

    private let store: CredentialStore

    init(store: CredentialStore = CredentialStore()) {
        self.store = store
        // UI tests start from the connect screen.
        if ProcessInfo.processInfo.arguments.contains("-resetServer") { store.clear() }
        credentials = store.load()
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
        store.clear()
        credentials = nil
        serverInfo = nil
        lastCheck = nil
    }

    private func record(_ error: Error) {
        lastError = error.localizedDescription
        lastErrorDate = .now
    }
}
