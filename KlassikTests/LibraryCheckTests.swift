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

    private nonisolated(unsafe) static var markerCalls: [String: Int] = [:]

    static func markerRequests(from host: String) -> Int {
        lock.withLock { markerCalls[host, default: 0] }
    }

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
        if path == "getIndexes" {
            Self.lock.withLock { Self.markerCalls[host, default: 0] += 1 }
            if host.hasPrefix("slow") { Thread.sleep(forTimeInterval: 0.5) }
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

    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<400 where !condition() { try? await Task.sleep(for: .milliseconds(5)) }
    }

    @Test func aCheckDuringACheckDoesNothing() async throws {
        let library = try makeLibrary()
        let host = "slow-\(UUID().uuidString.prefix(8)).test"
        await library.sync(with: client(host))
        let before = CheckServerProtocol.markerRequests(from: host)

        let first = Task { await library.syncIfChanged(with: client(host)) }
        await waitUntil { library.isChecking }
        #expect(library.isChecking)
        await library.syncIfChanged(with: client(host))
        await first.value

        #expect(CheckServerProtocol.markerRequests(from: host) - before == 1)
    }

    @Test func aCheckDuringASyncDoesNothing() async throws {
        let library = try makeLibrary()
        let host = "slow-\(UUID().uuidString.prefix(8)).test"
        await library.sync(with: client(host))
        let before = CheckServerProtocol.markerRequests(from: host)

        let running = Task { await library.sync(with: client(host)) }
        await waitUntil { library.isSyncing }
        #expect(library.isSyncing)
        await library.syncIfChanged(with: client(host))
        await running.value

        #expect(CheckServerProtocol.markerRequests(from: host) - before == 1)
    }

    @Test func theDiagnosticsRowShowsDateAndTimeOnlyForAnUnchangedCheck() async throws {
        let library = try makeLibrary()
        let host = "same-\(UUID().uuidString.prefix(8)).test"
        #expect(library.unchangedCheckRow == nil)
        await library.sync(with: client(host))
        #expect(library.unchangedCheckRow == nil)

        await library.syncIfChanged(with: client(host))

        let checked = try #require(library.checkedAt)
        let expected = "Checked \(checked.formatted(date: .abbreviated, time: .standard)), no changes"
        #expect(library.unchangedCheckRow == expected)
    }
}

/// Fails the first call of a host with a time-out, then answers.
private final class StallOnceProtocol: URLProtocol {
    private static let lock = NSLock()
    private nonisolated(unsafe) static var failed: Set<String> = []
    private nonisolated(unsafe) static var seen: [String: [TimeInterval]] = [:]

    static func timeouts(_ host: String) -> [TimeInterval] { lock.withLock { seen[host] ?? [] } }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let host = request.url?.host ?? ""
        Self.lock.withLock { Self.seen[host, default: []].append(request.timeoutInterval) }
        if Self.lock.withLock({ Self.failed.insert(host).inserted }) {
            client?.urlProtocol(self, didFailWithError: URLError(.timedOut))
            return
        }
        let json = #"{"subsonic-response":{"status":"ok","version":"1.16.1"}}"#
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(json.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

#if !canImport(FoundationNetworking)
    extension StallOnceProtocol: @unchecked Sendable {}
#endif

struct StalledReadTests {
    private func client(_ host: String) -> SubsonicClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StallOnceProtocol.self]
        return SubsonicClient(
            credentials: ServerCredentials(url: URL(string: "https://\(host)")!, username: "joe", password: "x"),
            session: URLSession(configuration: configuration))
    }

    @Test func aReadThatTimesOutRunsOnceMore() async throws {
        let info = try await client("stall-\(UUID().uuidString.prefix(8)).test").ping()
        #expect(info.apiVersion == "1.16.1")
    }

    @Test func startUpReadsUseTheShortTimeoutAndWritesDoNot() async throws {
        let host = "limits-\(UUID().uuidString.prefix(8)).test"
        let client = client(host)
        _ = try await client.ping()
        #expect(StallOnceProtocol.timeouts(host).allSatisfy { $0 == SubsonicClient.quickReadTimeout })
        try await client.star(["s1"])
        #expect(StallOnceProtocol.timeouts(host).last == URLRequest(url: URL(string: "https://x.test")!).timeoutInterval)
    }

    @Test func aTimedOutWriteIsNotRepeated() async throws {
        let client = client("write-\(UUID().uuidString.prefix(8)).test")
        await #expect(throws: URLError.self) { try await client.scrobble(id: "s1", time: Date()) }
    }
}
