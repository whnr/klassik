import Foundation
import Testing

@testable import Klassik

struct ServerConnectionTests {
    let url = URL(string: "https://music.example.org")!
    let otherURL = URL(string: "https://other.example.org")!
    let info = ServerInfo(
        apiVersion: "1.16.1", type: "navidrome", serverVersion: "0.64.2 (10114574)", openSubsonic: true)

    /// Defaults of this test alone, so the app's own defaults stay untouched.
    func withDefaults(_ body: (UserDefaults) throws -> Void) rethrows {
        let name = "ServerConnectionTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        try body(defaults)
    }

    @Test func savedAnswerReturnsForTheServerThatGaveIt() {
        withDefaults { defaults in
            SavedServerAnswer(defaults: defaults).save(info, for: url)
            #expect(SavedServerAnswer(defaults: defaults).load(for: url) == info)
        }
    }

    @Test func savedAnswerOfAnotherServerIsIgnored() {
        withDefaults { defaults in
            SavedServerAnswer(defaults: defaults).save(info, for: url)
            #expect(SavedServerAnswer(defaults: defaults).load(for: otherURL) == nil)
        }
    }

    @Test func nothingSavedLoadsNothing() {
        withDefaults { defaults in
            #expect(SavedServerAnswer(defaults: defaults).load(for: url) == nil)
            #expect(SavedServerAnswer(defaults: defaults).load(for: nil) == nil)
        }
    }

    @Test func savingNoAnswerRemovesTheSavedOne() {
        withDefaults { defaults in
            SavedServerAnswer(defaults: defaults).save(info, for: url)
            SavedServerAnswer(defaults: defaults).save(nil, for: url)
            #expect(SavedServerAnswer(defaults: defaults).load(for: url) == nil)
        }
    }

    @Test func clearRemovesTheSavedAnswer() {
        withDefaults { defaults in
            SavedServerAnswer(defaults: defaults).save(info, for: url)
            SavedServerAnswer(defaults: defaults).clear()
            #expect(SavedServerAnswer(defaults: defaults).load(for: url) == nil)
        }
    }

    @Test func serverNameMatchesTheSpecimen() {
        #expect(ServerConnectionView.name(of: info) == "Navidrome 0.64.2")
        #expect(ServerConnectionView.name(of: nil) == "Unknown")
    }

    @Test func countIsNoNumberBeforeTheFirstSync() {
        #expect(ServerConnectionView.countText(7, syncedAt: nil) == "—")
        #expect(ServerConnectionView.countText(7, syncedAt: Date.now) == 7.formatted())
    }
}
