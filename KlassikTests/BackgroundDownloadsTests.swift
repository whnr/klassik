import Foundation
import Testing

@testable import Klassik

struct BackgroundDownloadsTests {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)

    func makeDownloads() -> BackgroundDownloads {
        BackgroundDownloads(identifier: "test.\(UUID().uuidString)", staging: root.appending(path: "incoming"))
    }

    /// A task that never runs: the tests drive the delegate by hand.
    func makeTask(_ songID: String) -> URLSessionDownloadTask {
        let task = URLSession(configuration: .ephemeral).downloadTask(with: URL(string: "https://music.example.org/a")!)
        task.taskDescription = songID
        return task
    }

    func makeFile(_ text: String) throws -> URL {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let file = root.appending(path: UUID().uuidString)
        try Data(text.utf8).write(to: file)
        return file
    }

    func waitFor(_ downloads: BackgroundDownloads, _ task: URLSessionTask, count: Int) async {
        while downloads.waiterCount(task) < count { await Task.yield() }
    }

    @Test func everyWaiterOfASharedTrackFinishes() async throws {
        let downloads = makeDownloads()
        let task = makeTask("a")
        let first = Task { try await downloads.join(task, resume: false) }
        let second = Task { try await downloads.join(task, resume: false) }
        await waitFor(downloads, task, count: 2)
        downloads.received(try makeFile("bytes"), for: task, status: 200)
        downloads.finish(task, error: nil)
        let one = try await first.value
        let two = try await second.value
        #expect(one != two)
        #expect(try String(contentsOf: one, encoding: .utf8) == "bytes")
        #expect(try String(contentsOf: two, encoding: .utf8) == "bytes")
    }

    @Test func copiesExistBeforeTheFirstWaiterMovesTheFile() async throws {
        let downloads = makeDownloads()
        // A slow copy gives the first consumer time to move the staged file, as TrackStore does.
        downloads.copyFile = {
            Thread.sleep(forTimeInterval: 0.3)
            try FileManager.default.copyItem(at: $0, to: $1)
        }
        let task = makeTask("a")
        let first = Task {
            let file = try await downloads.join(task, resume: false)
            let moved = file.appendingPathExtension("moved")
            try FileManager.default.moveItem(at: file, to: moved)
            return moved
        }
        let second = Task { try await downloads.join(task, resume: false) }
        await waitFor(downloads, task, count: 2)
        downloads.received(try makeFile("bytes"), for: task, status: 200)
        downloads.finish(task, error: nil)
        _ = try await first.value
        let copy = try await second.value
        #expect(try String(contentsOf: copy, encoding: .utf8) == "bytes")
    }

    @Test func attachCallsTheEarlierHandlerToo() async {
        let downloads = makeDownloads()
        let calls = LockedCalls()
        downloads.attach { calls.add(1) }
        downloads.attach { calls.add(2) }
        downloads.urlSessionDidFinishEvents(forBackgroundURLSession: URLSession(configuration: .ephemeral))
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            DispatchQueue.main.async { done.resume() }
        }
        #expect(calls.values == [1, 2])
    }

    @Test func refusedAnswerFailsEveryWaiter() async throws {
        let downloads = makeDownloads()
        let task = makeTask("a")
        let first = Task { try await downloads.join(task, resume: false) }
        let second = Task { try await downloads.join(task, resume: false) }
        await waitFor(downloads, task, count: 2)
        downloads.received(try makeFile("not found"), for: task, status: 404)
        downloads.finish(task, error: nil)
        for waiter in [first, second] {
            await #expect(throws: SubsonicError.self) { try await waiter.value }
        }
    }

    @Test func transportErrorFailsTheWaiter() async throws {
        let downloads = makeDownloads()
        let task = makeTask("a")
        let waiter = Task { try await downloads.join(task, resume: false) }
        await waitFor(downloads, task, count: 1)
        downloads.finish(task, error: URLError(.notConnectedToInternet))
        await #expect(throws: URLError.self) { try await waiter.value }
    }

    @Test func cancellingOneWaiterKeepsTheOther() async throws {
        let downloads = makeDownloads()
        let task = makeTask("a")
        let first = Task { try await downloads.join(task, resume: false) }
        let second = Task { try await downloads.join(task, resume: false) }
        await waitFor(downloads, task, count: 2)
        first.cancel()
        await #expect(throws: CancellationError.self) { try await first.value }
        #expect(task.state != .canceling)
        downloads.received(try makeFile("bytes"), for: task, status: 200)
        downloads.finish(task, error: nil)
        #expect(try String(contentsOf: try await second.value, encoding: .utf8) == "bytes")
    }

    @Test func cancellingTheLastWaiterStopsTheTask() async throws {
        let downloads = makeDownloads()
        let task = makeTask("a")
        let waiter = Task { try await downloads.join(task, resume: false) }
        await waitFor(downloads, task, count: 1)
        waiter.cancel()
        await #expect(throws: CancellationError.self) { try await waiter.value }
        #expect(downloads.waiterCount(task) == 0)
        #expect(task.state == .canceling || task.state == .completed)
    }

    @Test func fileOfATransferWithoutWaiterStaysForTheNextLoad() async throws {
        let downloads = makeDownloads()
        let task = makeTask("a")
        downloads.received(try makeFile("bytes"), for: task, status: 200)
        downloads.finish(task, error: nil)
        let file = try await downloads.load("a", from: URL(string: "https://music.example.org/a")!)
        #expect(try String(contentsOf: file, encoding: .utf8) == "bytes")
    }

    @Test func completionHandlerRunsOnceWhenTheSessionHasDeliveredItsEvents() async throws {
        let downloads = makeDownloads()
        await confirmation { called in
            await withCheckedContinuation { done in
                downloads.attach {
                    called()
                    done.resume()
                }
                downloads.urlSessionDidFinishEvents(forBackgroundURLSession: URLSession.shared)
                downloads.urlSessionDidFinishEvents(forBackgroundURLSession: URLSession.shared)
            }
        }
    }
}

final class LockedCalls: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [Int] = []
    func add(_ value: Int) { lock.lock(); stored.append(value); lock.unlock() }
    var values: [Int] { lock.lock(); defer { lock.unlock() }; return stored }
}
