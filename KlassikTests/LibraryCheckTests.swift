import Foundation
import Testing

@testable import Klassik

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

/// A server by host name: `changed` answers with a new change marker, `down` refuses every call.
private final class CheckServerProtocol: URLProtocol {
    private static let lock = NSLock()
    private nonisolated(unsafe) static var calls: [String: Int] = [:]

    static func songRequests(from host: String) -> Int {
        lock.withLock { calls[host, default: 0] }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let host = request.url?.host ?? ""
        let path = request.url?.lastPathComponent ?? ""
        if host.hasPrefix("down") {
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
            return
        }
        if path == "search3" { Self.lock.withLock { Self.calls[host, default: 0] += 1 } }
        let body: String
        switch path {
        case "getIndexes":
            body = #""indexes":{"lastModified":\#(host.hasPrefix("changed") ? 2 : 1)}"#
        case "getScanStatus":
            body = #""scanStatus":{"scanning":false,"lastScan":"2026-10-18T01:29:20Z"}"#
        default:
            body = #""searchResult3":{"song":[{"id":"a-1","title":"Movement 1","album":"a","albumId":"a"}]}"#
        }
        let json = #"{"subsonic-response":{"status":"ok","version":"1.16.1",\#(body)}}"#
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(json.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

#if !canImport(FoundationNetworking)
    extension CheckServerProtocol: @unchecked Sendable {}
#endif

@MainActor
struct LibraryCheckTests {
    private func client(_ host: String) -> SubsonicClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CheckServerProtocol.self]
        return SubsonicClient(
            credentials: ServerCredentials(url: URL(string: "https://\(host)")!, username: "joe", password: "x"),
            session: URLSession(configuration: configuration))
    }

    private func makeLibrary() throws -> Library {
        let defaults = try #require(UserDefaults(suiteName: UUID().uuidString))
        return Library(
            cacheURL: FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).json"),
            defaults: defaults)
    }

    @Test func aCheckWithoutChangeKeepsTheLastChangeAndShowsTheCheck() async throws {
        let library = try makeLibrary()
        let host = "same-\(UUID().uuidString.prefix(8)).test"
        await library.sync(with: client(host))
        let changedAt = try #require(library.syncedAt)
        #expect(library.unchangedCheck == nil)
        #expect(library.statusText?.hasPrefix("Synced") == true)

        await library.syncIfChanged(with: client(host))

        #expect(library.syncedAt == changedAt)
        #expect(try #require(library.checkedAt) > changedAt)
        #expect(CheckServerProtocol.songRequests(from: host) == 1)
        let text = try #require(library.statusText)
        #expect(text.hasPrefix("Checked"))
        #expect(text.hasSuffix(", no changes."))
        #expect(library.unchangedCheck == library.checkedAt)
    }

    @Test func aChangeRunsTheSync() async throws {
        let library = try makeLibrary()
        let host = "changed-\(UUID().uuidString.prefix(8)).test"
        await library.sync(with: client("old-\(host)"))
        let before = try #require(library.syncedAt)

        await library.syncIfChanged(with: client(host))

        #expect(try #require(library.syncedAt) > before)
        #expect(CheckServerProtocol.songRequests(from: host) == 1)
        #expect(library.unchangedCheck == nil)
    }

    @Test func aFailedCheckStaysQuiet() async throws {
        let library = try makeLibrary()
        await library.sync(with: client("up-\(UUID().uuidString.prefix(8)).test"))
        let before = library.checkedAt

        await library.syncIfChanged(with: client("down-\(UUID().uuidString.prefix(8)).test"))

        #expect(library.syncError == nil)
        #expect(library.checkedAt == before)
        #expect(library.statusText?.hasPrefix("Synced") == true)
    }

    /// Foreground and reconnect call the same check.
    @Test func theForegroundCheckLeavesTheLibraryAloneWhenNothingChanged() async throws {
        let library = try makeLibrary()
        let host = "same-\(UUID().uuidString.prefix(8)).test"
        await library.sync(with: client(host))
        let changedAt = library.syncedAt

        await AppModel.checkForChanges(library: library, client: client(host))
        await AppModel.checkForChanges(library: library, client: client(host))

        #expect(library.syncedAt == changedAt)
        #expect(library.unchangedCheck != nil)
        #expect(CheckServerProtocol.songRequests(from: host) == 1)
    }
}
