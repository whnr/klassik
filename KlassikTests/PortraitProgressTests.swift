import CoreGraphics
import Foundation
import ImageIO
import Testing
import UIKit

@testable import Klassik

@Suite(.serialized) struct PortraitProgressTests {
    private struct Answer: Sendable {
        let name: String
        let portrait: LoadedPortrait?
    }

    /// The gate holds the serial worker while the test fills its queue in a known order.
    private final class Gate: Sendable {
        let release = DispatchSemaphore(value: 0)
        let started = AsyncStream<Void>.makeStream()
        let rendered = AsyncStream<Int>.makeStream()

        func render(_ data: Data, screen: PortraitSize.Screen?) -> LoadedPortrait? {
            let id = Int(data.first ?? 0)
            if id == 0 {
                started.continuation.yield(())
                guard release.wait(timeout: .now() + 10) == .success else { return nil }
            }
            rendered.continuation.yield(id)
            return LoadedPortrait(image: UIImage(), faces: [])
        }
    }

    private static func enqueue(
        _ id: Int, name: String, on decoder: PortraitLoader.Decoder,
        answers: AsyncStream<Answer>.Continuation, opening: Bool = false,
        cancelled: PortraitLoader.Cancelled = PortraitLoader.Cancelled()
    ) {
        decoder.enqueue(
            Data([UInt8(id)]), url: URL(string: "https://upload.wikimedia.org/\(id).jpg")!, screen: nil,
            opening: opening, cancelled: cancelled
        ) { answers.yield(Answer(name: name, portrait: $0)) }
    }

    @Test func tapSharesPendingDecodeAndPassesQueuedRows() async throws {
        let gate = Gate()
        defer { gate.release.signal() }
        let decoder = PortraitLoader.Decoder(render: gate.render)
        let answers = AsyncStream<Answer>.makeStream()
        Self.enqueue(0, name: "blocker", on: decoder, answers: answers.continuation)
        for await _ in gate.started.stream { break }
        Self.enqueue(1, name: "row 1", on: decoder, answers: answers.continuation)
        Self.enqueue(2, name: "row 2", on: decoder, answers: answers.continuation)
        let cancelled = PortraitLoader.Cancelled()
        Self.enqueue(3, name: "row 3", on: decoder, answers: answers.continuation, cancelled: cancelled)
        Self.enqueue(3, name: "tap", on: decoder, answers: answers.continuation, opening: true)
        cancelled.set()
        gate.release.signal()
        var results: [Answer] = []
        for await answer in answers.stream {
            results.append(answer)
            if results.count == 5 { break }
        }
        #expect(results.map(\.name) == ["blocker", "row 3", "tap", "row 1", "row 2"])
        #expect(results[1].portrait == nil)
        #expect(results[2].portrait != nil)
        gate.rendered.continuation.finish()
        var rendered: [Int] = []
        for await id in gate.rendered.stream { rendered.append(id) }
        #expect(rendered == [0, 3, 1, 2])
    }

    /// Each opening decode queues the next one, so opening work is always pending while the row waits.
    private final class Replenish: @unchecked Sendable {
        let release = DispatchSemaphore(value: 0)
        let started = AsyncStream<Void>.makeStream()
        let rendered = AsyncStream<Int>.makeStream()
        let answers = AsyncStream<Answer>.makeStream()
        var decoder: PortraitLoader.Decoder?
        static let last = 29

        func render(_ data: Data, screen: PortraitSize.Screen?) -> LoadedPortrait? {
            let id = Int(data.first ?? 0)
            if id == 0 {
                started.continuation.yield(())
                guard release.wait(timeout: .now() + 10) == .success else { return nil }
            }
            if (10..<Self.last).contains(id), let decoder {
                PortraitProgressTests.enqueue(
                    id + 1, name: "tap \(id + 1)", on: decoder, answers: answers.continuation, opening: true)
            }
            rendered.continuation.yield(id)
            return LoadedPortrait(image: UIImage(), faces: [])
        }
    }

    @Test func sustainedTapsLetAnOlderRowFinish() async throws {
        let replenish = Replenish()
        defer { replenish.release.signal() }
        let decoder = PortraitLoader.Decoder(render: replenish.render)
        replenish.decoder = decoder
        let answers = replenish.answers
        Self.enqueue(0, name: "blocker", on: decoder, answers: answers.continuation)
        for await _ in replenish.started.stream { break }
        Self.enqueue(1, name: "row", on: decoder, answers: answers.continuation)
        Self.enqueue(10, name: "tap 10", on: decoder, answers: answers.continuation, opening: true)
        replenish.release.signal()
        var results: [Answer] = []
        for await answer in answers.stream {
            results.append(answer)
            if results.count == Replenish.last - 10 + 3 { break }
        }
        let limit = PortraitLoader.Decoder.burstLimit
        let row = try #require(results.firstIndex { $0.name == "row" })
        #expect(results[row].portrait != nil)
        #expect(row == 1 + limit)
        replenish.rendered.continuation.finish()
        var rendered: [Int] = []
        for await id in replenish.rendered.stream { rendered.append(id) }
        #expect(rendered == [0] + Array(10..<10 + limit) + [1] + Array(10 + limit...Replenish.last))
    }

    @Test func cancelledQueuedCallerSkipsDecode() async throws {
        let gate = Gate()
        defer { gate.release.signal() }
        let decoder = PortraitLoader.Decoder(render: gate.render)
        let answers = AsyncStream<Answer>.makeStream()
        Self.enqueue(0, name: "blocker", on: decoder, answers: answers.continuation)
        for await _ in gate.started.stream { break }
        let cancelled = PortraitLoader.Cancelled()
        Self.enqueue(1, name: "cancelled", on: decoder, answers: answers.continuation, cancelled: cancelled)
        Self.enqueue(2, name: "next", on: decoder, answers: answers.continuation)
        cancelled.set()
        gate.release.signal()
        var results: [Answer] = []
        for await answer in answers.stream {
            results.append(answer)
            if results.count == 3 { break }
        }
        #expect(results.map(\.name) == ["blocker", "cancelled", "next"])
        #expect(results[1].portrait == nil)
        #expect(results[2].portrait != nil)
        gate.rendered.continuation.finish()
        var rendered: [Int] = []
        for await id in gate.rendered.stream { rendered.append(id) }
        #expect(rendered == [0, 2])
    }

    @Test func runningDecodeAcceptsAnotherCaller() async throws {
        let gate = Gate()
        defer { gate.release.signal() }
        let decoder = PortraitLoader.Decoder(render: gate.render)
        let answers = AsyncStream<Answer>.makeStream()
        Self.enqueue(0, name: "row", on: decoder, answers: answers.continuation)
        for await _ in gate.started.stream { break }
        Self.enqueue(0, name: "tap", on: decoder, answers: answers.continuation, opening: true)
        gate.release.signal()
        var results: [Answer] = []
        for await answer in answers.stream {
            results.append(answer)
            if results.count == 2 { break }
        }
        let row = try #require(results[0].portrait)
        let tap = try #require(results[1].portrait)
        #expect(row.image === tap.image)
        gate.rendered.continuation.finish()
        var count = 0
        for await _ in gate.rendered.stream { count += 1 }
        #expect(count == 1)
    }

    @Test func cancelledTaskReturnsNilWithoutRendering() async {
        let gate = Gate()
        defer { gate.release.signal() }
        let decoder = PortraitLoader.Decoder(render: gate.render)
        let answers = AsyncStream<Answer>.makeStream()
        Self.enqueue(0, name: "blocker", on: decoder, answers: answers.continuation)
        for await _ in gate.started.stream { break }
        let task = Task {
            await decoder.decode(Data([1]), url: URL(string: "https://upload.wikimedia.org/1.jpg")!, screen: nil)
        }
        task.cancel()
        gate.release.signal()
        #expect(await task.value == nil)
        for await _ in answers.stream { break }
        gate.rendered.continuation.finish()
        var rendered: [Int] = []
        for await id in gate.rendered.stream { rendered.append(id) }
        #expect(rendered == [0])
    }

    /// Generated pictures at Commons original sizes measure the tap wait. A slow network cannot use the time limit.
    @Test func largePictureFirstFrameBeforeAndAfter() async throws {
        let done = DispatchSemaphore(value: 0)
        Self.watchdog(done)
        defer { done.signal() }
        let screen = PortraitSizeTests.proMax
        let originals = [("3840 x 5120", Self.jpeg()), ("2400 x 3200", Self.jpeg(width: 2400, height: 3200))]
        for (name, data) in originals {
            try #require(!data.isEmpty)
            let before = ContinuousClock.now
            let legacy = DispatchQueue(label: "PortraitProgressTests.FIFO")
            let old = AsyncStream<Bool>.makeStream()
            // Six visible rows precede the duplicate tap in the original FIFO path.
            for _ in 0..<6 {
                legacy.async { _ = PortraitLoader.upright(data, screen: screen) }
            }
            legacy.async {
                old.continuation.yield(PortraitLoader.upright(data, screen: screen) != nil)
            }
            for await success in old.stream {
                #expect(success)
                break
            }
            let oldTime = before.duration(to: .now)
            let after = ContinuousClock.now
            let gate = DispatchSemaphore(value: 0)
            let entered = AsyncStream<Void>.makeStream()
            let measured = PortraitLoader.Decoder { bytes, size in
                if bytes.isEmpty {
                    entered.continuation.yield(())
                    _ = gate.wait(timeout: .now() + 10)
                    return nil
                }
                return PortraitLoader.upright(bytes, screen: size)
            }
            measured.enqueue(Data(), url: URL(string: "https://upload.wikimedia.org/gate")!, screen: nil) { _ in }
            for await _ in entered.stream { break }
            let tap = AsyncStream<Bool>.makeStream()
            for index in 0..<6 {
                measured.enqueue(
                    data, url: URL(string: "https://upload.wikimedia.org/\(index).jpg")!, screen: screen
                ) { _ in }
            }
            measured.enqueue(
                data, url: URL(string: "https://upload.wikimedia.org/5.jpg")!, screen: screen, opening: true
            ) { tap.continuation.yield($0 != nil) }
            gate.signal()
            for await success in tap.stream {
                #expect(success)
                break
            }
            let newTime = after.duration(to: .now)
            print(
                "First-frame preparation \(name): FIFO \(oldTime), promoted/shared \(newTime)"
            )
            // Drain before the next measurement, so the remaining rows cannot distort its timing.
            let drained = AsyncStream<Void>.makeStream()
            measured.enqueue(Data([1]), url: URL(string: "https://upload.wikimedia.org/end")!, screen: nil) { _ in
                drained.continuation.yield(())
            }
            for await _ in drained.stream { break }
        }
    }

    /// A Commons step of 3840 pixels, at the aspect of a typical portrait. Generated pixels need no network.
    private static func jpeg(width: Int = 3840, height: Int = 5120) -> Data {
        guard
            let context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else { return Data() }
        context.setFillColor(red: 0.4, green: 0.2, blue: 0.1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let data = NSMutableData()
        guard let image = context.makeImage(),
            let destination = CGImageDestinationCreateWithData(data as CFMutableData, "public.jpeg" as CFString, 1, nil)
        else { return Data() }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return Data() }
        return data as Data
    }

    /// A stopped cooperative pool cannot run the time limit of the test or report a failure. A thread outside
    /// the pool ends the run instead, so the stall fails in a minute and not at the job timeout.
    private static func watchdog(_ done: DispatchSemaphore) {
        Thread {
            guard done.wait(timeout: .now() + 60) == .timedOut else { return }
            fatalError("Parallel portrait loads stopped the cooperative pool")
        }.start()
    }

    /// Visible rows decode their pictures together. More loads than processors must leave async work running.
    @Test func parallelPortraitLoadsLeaveAsyncAndMainActorWorkRunning() async throws {
        let done = DispatchSemaphore(value: 0)
        Self.watchdog(done)
        defer { done.signal() }
        let data = Self.jpeg()
        try #require(!data.isEmpty)
        let count = 2 * ProcessInfo.processInfo.activeProcessorCount
        let loads = Task {
            await withTaskGroup(of: Bool.self, returning: Int.self) { group in
                for index in 0..<count {
                    group.addTask(priority: .userInitiated) {
                        let url = URL(string: "https://upload.wikimedia.org/portrait-\(index).jpg")!
                        let portrait = await PortraitLoader.load(url, screen: PortraitSizeTests.proMax) { _ in
                            (data, 200)
                        }
                        return portrait != nil
                    }
                }
                var loaded = 0
                for await success in group where success { loaded += 1 }
                return loaded
            }
        }
        try await Task.sleep(for: .milliseconds(200))
        let sent = ContinuousClock.now
        let background = await Task.detached(priority: .userInitiated) { sent.duration(to: .now) }.value
        let foreground = await MainActor.run { sent.duration(to: .now) }
        if LatencyLimits.enforced {
            #expect(background < .milliseconds(500))
            #expect(foreground < .milliseconds(500))
        }
        #expect(await loads.value == count)
    }
}
