import Foundation
import Testing

@testable import Klassik

@MainActor
struct LibraryRowsTests {
    func defaults() throws -> UserDefaults { try #require(UserDefaults(suiteName: UUID().uuidString)) }

    @Test func startsWithEveryRowOnce() throws {
        let rows = LibraryRows(defaults: try defaults())
        #expect(rows.rows == [.composers, .favourites])
    }

    @Test func listenerMovesARow() throws {
        let rows = LibraryRows(defaults: try defaults())
        rows.move(fromOffsets: [1], toOffset: 0)
        #expect(rows.rows == [.favourites, .composers])
        rows.move(fromOffsets: [0], toOffset: 2)
        #expect(rows.rows == [.composers, .favourites])
    }

    @Test func orderIsKeptOnDevice() throws {
        let suite = try defaults()
        LibraryRows(defaults: suite).move(fromOffsets: [1], toOffset: 0)
        #expect(LibraryRows(defaults: suite).rows == [.favourites, .composers])
    }

    @Test func resetGoesBackToTheDefaultOrder() throws {
        let suite = try defaults()
        let rows = LibraryRows(defaults: suite)
        rows.move(fromOffsets: [1], toOffset: 0)
        rows.reset()
        #expect(rows.rows == [.composers, .favourites])
        #expect(LibraryRows(defaults: suite).rows == [.composers, .favourites])
    }

    @Test func storedOrderWithUnknownAndRepeatedNamesStaysWhole() {
        #expect(LibraryRows.order(stored: ["favourites", "playlists", "favourites"]) == [.favourites, .composers])
    }

    @Test func rowMissingFromTheStoredOrderComesLast() {
        #expect(LibraryRows.order(stored: ["favourites"]) == [.favourites, .composers])
        #expect(LibraryRows.order(stored: []) == [.composers, .favourites])
    }
}
