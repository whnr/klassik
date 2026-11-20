import Foundation
import Testing
import UIKit

@testable import Klassik

struct PortraitProgressTests {
    private final class Progress: @unchecked Sendable {
        private let lock = NSLock()
        private var background: [Duration] = []
        private var foreground: [Duration] = []

        func probe() {
            // Dispatch supplies the clock even when every cooperative worker is decoding a picture.
            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + .milliseconds(50)) {
                let sent = ContinuousClock.now
                Task.detached(priority: .userInitiated) {
                    self.lock.withLock { self.background.append(sent.duration(to: .now)) }
                }
                Task { @MainActor in
                    self.lock.withLock { self.foreground.append(sent.duration(to: .now)) }
                }
            }
        }

        var delays: (background: [Duration], foreground: [Duration]) {
            lock.withLock { (background, foreground) }
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func largePortraitLoadsLeaveAsyncAndMainActorWorkResponsive() async throws {
        // Generated pixels keep the test independent of network access and copyrighted pictures.
        let data = PortraitLoaderSizeTests.jpeg(width: 3840)
        let progress = Progress()
        let count = 64
        let loaded = await withTaskGroup(of: Bool.self, returning: Int.self) { group in
            for index in 0..<count {
                group.addTask(priority: .userInitiated) {
                    let url = URL(string: "https://upload.wikimedia.org/portrait-\(index).jpg")!
                    let portrait = await PortraitLoader.load(url, screen: PortraitSizeTests.proMax) { _ in
                        progress.probe()
                        return (data, 200)
                    }
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
