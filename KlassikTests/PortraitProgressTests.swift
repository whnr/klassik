import CoreGraphics
import Foundation
import ImageIO
import Testing

@testable import Klassik

struct PortraitProgressTests {
    /// A Commons step of 3840 pixels, at the aspect of a typical portrait. Generated pixels need no network.
    private static func jpeg() -> Data {
        guard
            let context = CGContext(
                data: nil, width: 3840, height: 5120, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else { return Data() }
        context.setFillColor(red: 0.4, green: 0.2, blue: 0.1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 3840, height: 5120))
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
        #expect(background < .milliseconds(500))
        #expect(foreground < .milliseconds(500))
        #expect(await loads.value == count)
    }
}
