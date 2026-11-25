import Foundation
import Observation

/// The state of the Lab app: not connected, loading the case list, or ready with a player.
@MainActor @Observable
final class LabModel {
    enum Phase {
        case connect
        case loading
        case ready(LabPlayer, [LabCase])
    }

    private(set) var phase = Phase.connect
    private(set) var error: String?
    var address = ""
    var username = ""
    var password = ""

    private let store = LabCredentialStore()

    init() {
        if let saved = store.load() {
            address = saved.url.absoluteString
            username = saved.username
            password = saved.password
            connect()
        }
    }

    func connect() {
        guard let url = LabCredentials.normalizedURL(from: address) else {
            error = "Enter the address of the server, such as http://192.168.1.20:4533."
            return
        }
        guard !username.isEmpty else {
            error = "Enter the user name."
            return
        }
        let credentials = LabCredentials(url: url, username: username, password: password)
        error = nil
        phase = .loading
        Task {
            do {
                let client = LabClient(credentials: credentials)
                let cases = LabCase.cases(from: try await client.albumSongs())
                guard !cases.isEmpty else { throw LabError.noAlbum }
                store.save(credentials)
                phase = .ready(LabPlayer(client: client, cases: cases), cases)
            } catch {
                self.error = error.localizedDescription
                phase = .connect
            }
        }
    }

    func disconnect() {
        if case .ready(let player, _) = phase { player.stop() }
        store.clear()
        address = ""
        username = ""
        password = ""
        phase = .connect
    }
}
