import CoreGraphics
import Foundation
import ImageIO
import Testing
import UIKit
import Vision

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

    @Test(.disabled("staged diagnostic runs first"), .timeLimit(.minutes(1)))
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

    /// Runs each stage on its own threads, so a stage that never returns leaves the next stages and the report.
    private static func stage(_ name: String, count: Int = 1, _ work: @escaping @Sendable () -> String) {
        let group = DispatchGroup()
        let start = Date()
        for index in 0..<count {
            group.enter()
            Thread {
                let result = autoreleasepool { work() }
                print("Stage \(name)[\(index)] returned after \(Date().timeIntervalSince(start)) s: \(result)")
                group.leave()
            }.start()
        }
        let outcome = group.wait(timeout: .now() + 20)
        print("STAGE \(name): \(outcome == .success ? "ok" : "TIMEOUT") after \(Date().timeIntervalSince(start)) s")
    }

    private static func image(width: Int, height: Int) -> CGImage? {
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        context?.setFillColor(red: 0.4, green: 0.2, blue: 0.1, alpha: 1)
        context?.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context?.makeImage()
    }

    private static func faces(_ image: CGImage?) -> String {
        guard let image else { return "no image" }
        let request = VNDetectFaceRectanglesRequest()
        do { try VNImageRequestHandler(cgImage: image).perform([request]) } catch { return "error \(error)" }
        return "faces \(request.results?.count ?? -1)"
    }

    private static func thumbnail(_ data: Data, cache: Bool) -> String {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return "no source" }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 3520,
            kCGImageSourceShouldCacheImmediately: cache,
        ]
        guard let pixels = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return "no thumbnail"
        }
        return "\(pixels.width)x\(pixels.height)"
    }

    @Test func stagedPortraitWork() async throws {
        let data = Self.jpeg()
        try #require(!data.isEmpty)
        print("Staged fixture: \(data.count) bytes")
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            Thread {
                Self.stage("vision-2640") { Self.faces(Self.image(width: 2640, height: 3520)) }
                Self.stage("vision-880") { Self.faces(Self.image(width: 880, height: 1173)) }
                Self.stage("uiimage-render") {
                    guard let source = UIImage(data: data) else { return "no image" }
                    let size = CGSize(width: 2640, height: 3520)
                    let format = UIGraphicsImageRendererFormat()
                    format.scale = 1
                    let image = UIGraphicsImageRenderer(size: size, format: format).image { _ in
                        source.draw(in: CGRect(origin: .zero, size: size))
                    }
                    return "\(image.size)"
                }
                Self.stage("thumbnail-cached") { Self.thumbnail(data, cache: true) }
                Self.stage("thumbnail-lazy") { Self.thumbnail(data, cache: false) }
                Self.stage("thumbnail-cached-x3", count: 3) { Self.thumbnail(data, cache: true) }
                Self.stage("load") {
                    let done = DispatchSemaphore(value: 0)
                    let box = Box()
                    Task.detached {
                        let url = URL(string: "https://upload.wikimedia.org/portrait-staged.jpg")!
                        let portrait = await PortraitLoader.load(url, screen: PortraitSizeTests.proMax) { _ in
                            (data, 200)
                        }
                        box.set(portrait.map { "\($0.image.size) faces \($0.faces.count)" } ?? "nil")
                        done.signal()
                    }
                    _ = done.wait(timeout: .now() + 19)
                    return box.value
                }
                continuation.resume()
            }.start()
        }
    }

    private final class Box: @unchecked Sendable {
        private let lock = NSLock()
        private var text = "pending"
        func set(_ value: String) { lock.withLock { text = value } }
        var value: String { lock.withLock { text } }
    }
}
