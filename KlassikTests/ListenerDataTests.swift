import Foundation
import Testing

@testable import Klassik

/// The device file of the listener: sign-out keeps it, Delete Listening Data removes it (ADR 0013).
@MainActor
struct ListenerDataTests {
    private let listener = ServerCredentials(
        url: URL(string: "https://music.example.org")!, username: "listener", password: "secret")
    private let other = ServerCredentials(
        url: URL(string: "https://music.example.org")!, username: "other", password: "secret")

    private func folder() -> URL {
        FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    }

    private let data = DeviceStore.Data(
        favouriteWorks: ["work"],
        notes: ["recording": [ListeningNote(movement: 0, at: 12, text: "Horns")]],
        recentSearches: [RecentSearch(id: UUID(), text: "Dvořák", conditions: [])])

    @Test func signOutKeepsTheDeviceFile() throws {
        let root = folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let device = ListenerData(folder: root)
        try device.attach(listener).save(data)
        let url = try #require(device.store?.url)

        device.attach(nil)
        #expect(device.store?.url == nil)
        #expect(FileManager.default.fileExists(atPath: url.path))

        #expect(device.attach(listener).data == data)
    }

    @Test func deleteRemovesOnlyTheFileOfThisServerAndUser() throws {
        let root = folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let device = ListenerData(folder: root)
        try device.attach(other).save(data)
        try device.attach(listener).save(data)
        let url = try #require(device.store?.url)

        try device.delete()
        #expect(!FileManager.default.fileExists(atPath: url.path))
        #expect(device.file.data == DeviceStore.Data())
        #expect(device.attach(listener).data == DeviceStore.Data())
        #expect(device.attach(other).data == data)
    }

    /// A damaged file refuses every write. Delete removes it, and the listener can keep data again.
    @Test func deleteReplacesADamagedFile() throws {
        let root = folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let device = ListenerData(folder: root)
        let url = DeviceStore(server: listener.url, username: listener.username, folder: root).url
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("damaged".utf8).write(to: url)
        let file = device.attach(listener)
        #expect(file.loadError != nil)

        try device.delete()
        #expect(device.file.loadError == nil)
        try device.file.save(data)
        #expect(device.attach(listener).data == data)
    }
}
