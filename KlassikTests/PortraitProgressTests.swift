import CoreGraphics
import Foundation
import ImageIO
import Testing

@testable import Klassik

struct PortraitProgressTests {
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

    private final class Progress: @unchecked Sendable {
        private let lock = NSLock()
        private var background: [Duration] = []
        private var foreground: [Duration] = []
        private var downloads = 0
        private var clocks = 0
        private var completed = 0

        func probe() {
            lock.withLock { downloads += 1 }
            // Dispatch supplies the clock even when every cooperative worker is decoding a picture.
            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + .milliseconds(50)) {
                self.lock.withLock { self.clocks += 1 }
                let sent = ContinuousClock.now
                Task.detached(priority: .userInitiated) {
                    self.lock.withLock { self.background.append(sent.duration(to: .now)) }
                }
                Task { @MainActor in
                    self.lock.withLock { self.foreground.append(sent.duration(to: .now)) }
                }
            }
        }

        func finish() { lock.withLock { completed += 1 } }

        func report() {
            let status = lock.withLock {
                "downloads=\(downloads), clocks=\(clocks), decoded=\(completed), async=\(background.count), main=\(foreground.count)"
            }
            print("Portrait stages: \(status)")
        }

        var delays: (background: [Duration], foreground: [Duration]) {
            lock.withLock { (background, foreground) }
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func largePortraitLoadsLeaveAsyncAndMainActorWorkResponsive() async throws {
        // Generated pixels keep the test independent of network access and copyrighted pictures.
        let progress = Progress()
        let clock = DispatchQueue(label: "PortraitProgressTests.clock", qos: .userInteractive)
        for seconds in [1, 5, 15] {
            clock.asyncAfter(deadline: .now() + .seconds(seconds)) { progress.report() }
        }
        print("Portrait fixture: generating")
        // Fixture encoding must not occupy a cooperative worker while the test measures image decoding.
        let data: Data = await withCheckedContinuation { continuation in
            DispatchQueue(label: "PortraitProgressTests.fixture").async {
                let data = autoreleasepool { Self.jpeg() }
                print("Portrait fixture: \(data.count) bytes")
                continuation.resume(returning: data)
            }
        }
        try #require(!data.isEmpty)
        let count = 64
        let loaded = await withTaskGroup(of: Bool.self, returning: Int.self) { group in
            for index in 0..<count {
                group.addTask(priority: .userInitiated) {
                    let url = URL(string: "https://upload.wikimedia.org/portrait-\(index).jpg")!
                    let portrait = await PortraitLoader.load(url, screen: PortraitSizeTests.proMax) { _ in
                        progress.probe()
                        return (data, 200)
                    }
                    progress.finish()
                    return portrait != nil
                }
            }
            var loaded = 0
            for await success in group where success { loaded += 1 }
            return loaded
        }
        // Let probes from the final downloads run after the last decode completes.
        try await Task.sleep(for: .milliseconds(600))
        let delays = progress.delays
        print(
            "Portrait progress: async=\(String(describing: delays.background.max())), main=\(String(describing: delays.foreground.max()))"
        )
        #expect(loaded == count)
        #expect(delays.background.count == count)
        #expect(delays.foreground.count == count)
        #expect(delays.background.allSatisfy { $0 < .milliseconds(500) })
        #expect(delays.foreground.allSatisfy { $0 < .milliseconds(500) })
    }
}
