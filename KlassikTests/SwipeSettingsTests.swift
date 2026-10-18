import Foundation
import Testing

@testable import Klassik

@MainActor
struct SwipeSettingsTests {
    func defaults() throws -> UserDefaults { try #require(UserDefaults(suiteName: UUID().uuidString)) }

    @Test func startsWithTheDefaults() throws {
        let settings = SwipeSettings(defaults: try defaults())
        #expect(SwipeSettings.actions(settings.leading) == [.download, .reference])
        #expect(SwipeSettings.actions(settings.trailing) == [.addToQueue, .playNext])
    }

    @Test func choiceIsKeptOnDevice() throws {
        let suite = try defaults()
        SwipeSettings(defaults: suite).trailing = [.reference, nil]
        let again = SwipeSettings(defaults: suite)
        #expect(again.trailing == [.reference, nil])
        #expect(SwipeSettings.actions(again.trailing) == [.reference])
    }

    @Test func actionNeverRepeatsOnOneEdge() {
        #expect(SwipeSettings.actions([.download, .download]) == [.download])
        #expect(SwipeSettings.actions([nil, .playNext]) == [.playNext])
    }

    @Test func restoreGoesBackToTheDefaults() throws {
        let settings = SwipeSettings(defaults: try defaults())
        settings.leading = [nil, nil]
        settings.reset()
        #expect(SwipeSettings.actions(settings.leading) == SwipeSettings.defaultLeading)
    }
}
