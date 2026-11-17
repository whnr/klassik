import AVFoundation
import CryptoKit
import ImageIO
import UIKit

@MainActor enum CoverArt {
    /// Authentication salts change per request, so a signed URL must not identify a view's loading task.
    struct Source: Equatable {
        /// Tracks on the device that can hold embedded art. Their files resolve in the loading task, off the body.
        var local: [Song]
        var coverID: String?
        var pixels: Int
        var credentials: ServerCredentials?
        /// The album of the cover. The device keeps one copy of the art for each album (ADR 0051).
        var album: String?

        var cacheKey: NSString? {
            let fields = [
                credentials?.url.absoluteString ?? "", credentials?.username ?? "", credentials?.password ?? "",
                coverID ?? local.first?.id ?? "", String(pixels),
            ]
            guard let data = try? JSONEncoder().encode(fields) else { return nil }
            return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() as NSString
        }

        var remote: URL? {
            guard let coverID, let credentials else { return nil }
            return SubsonicClient(credentials: credentials).coverArtURL(id: coverID, size: pixels)
        }

        /// The server copy at the size that the device keeps. Every view scales it down from there.
        var stored: URL? {
            guard let coverID, let credentials else { return nil }
            return SubsonicClient(credentials: credentials).coverArtURL(id: coverID, size: CoverArt.storedPixels)
        }

        var storeKey: String? {
            guard let album, let credentials else { return nil }
            return CoverArt.storeKey(album: album, credentials: credentials)
        }
    }

    /// The longest side of the kept copy: the page cover at the 3x scale of the largest iPhone screens.
    nonisolated static let storedPixels = Int(Measure.coverPage) * 3

    /// The key holds the account but not the password, so that a new password keeps the art.
    nonisolated static func storeKey(album: String, credentials: ServerCredentials) -> String {
        [credentials.url.absoluteString, credentials.username, album].joined(separator: "\n")
    }

    /// List updates must keep loaded covers visible while local files and server artwork load again.
    final class Cache {
        private let images = NSCache<NSString, UIImage>()

        init() { images.totalCostLimit = 32 * 1_024 * 1_024 }

        func image(for source: Source) -> UIImage? {
            source.cacheKey.flatMap { images.object(forKey: $0) }
        }

        func store(_ image: UIImage, for source: Source) {
            guard let key = source.cacheKey else { return }
            let cost = image.cgImage.map { $0.bytesPerRow * $0.height } ?? 1
            images.setObject(image, forKey: key, cost: cost)
        }

        func clear() { images.removeAllObjects() }
    }

    /// The audio file keeps its artwork available for as long as the track stays on the device.
    static func embedded(in file: URL) async -> UIImage? {
        let flac = await Task.detached(priority: .userInitiated) { FLACArtwork.data(in: file) }.value
        if let flac, let image = UIImage(data: flac) { return image }
        let asset = AVURLAsset(url: file)
        guard let metadata = try? await asset.load(.commonMetadata) else { return nil }
        for item in AVMetadataItem.metadataItems(from: metadata, filteredByIdentifier: .commonIdentifierArtwork) {
            if let data = try? await item.load(.dataValue), let image = UIImage(data: data) { return image }
        }
        return nil
    }

    /// The art of a file on the device first, then the kept copy, then the server. With a store, the server copy
    /// comes at the kept size and stays on the device.
    static func load(
        files: [URL], remote: URL?, pixels: Int = 0, kept: (store: ImageStore, key: String)? = nil,
        embedded: (URL) async -> UIImage? = CoverArt.embedded,
        fetch: (URL) async throws -> (Data, URLResponse) = { try await CoverArt.session.data(from: $0) }
    ) async -> UIImage? {
        for file in files {
            if Task.isCancelled { return nil }
            if let image = await embedded(file) { return image }
        }
        if let kept, let data = await kept.store.data(for: kept.key), let image = await scaled(data, to: pixels) {
            return image
        }
        guard !Task.isCancelled, let remote, let (data, response) = try? await fetch(remote),
            let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
            let image = await scaled(data, to: pixels)
        else { return nil }
        if let kept { await kept.store.store(data, for: kept.key) }
        return image
    }

    /// The art in `ImageStore.albumArt` is the only copy on the device.
    nonisolated static let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.urlCache = nil
        return URLSession(configuration: configuration)
    }()

    /// The image at most `pixels` on its longest side. A list row needs a small copy of a large kept picture,
    /// and decoding the small copy only saves memory. Zero keeps the full size.
    nonisolated static func scaled(_ data: Data, to pixels: Int) async -> UIImage? {
        await Task.detached(priority: .userInitiated) { () -> UIImage? in
            guard pixels > 0, let source = CGImageSourceCreateWithData(data as CFData, nil) else {
                return UIImage(data: data)
            }
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: pixels,
            ]
            guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
                return UIImage(data: data)
            }
            return UIImage(cgImage: image)
        }.value
    }

    /// Keeps the art of every album of the library on the device, one album after the other. It stops at the first
    /// file that does not fit under the limit, so it never pushes out art it kept before, and the classical albums
    /// that come first stay. It also stops when the network fails or a write fails. A Low Data Mode connection
    /// refuses each request (ADR 0051).
    static func keepAll(
        _ songs: [Song], credentials: ServerCredentials, store: ImageStore,
        fetch: (URLRequest) async throws -> (Data, URLResponse) = { try await CoverArt.session.data(for: $0) }
    ) async {
        await store.loaded()
        let client = SubsonicClient(credentials: credentials)
        var seen = Set<String>()
        for song in songs {
            guard let cover = song.coverArt, seen.insert(song.albumKey).inserted else { continue }
            let key = storeKey(album: song.albumKey, credentials: credentials)
            if store.contains(key) { continue }
            if store.isFull || Task.isCancelled { return }
            var request = URLRequest(url: client.coverArtURL(id: cover, size: storedPixels))
            request.allowsConstrainedNetworkAccess = false
            guard let (data, response) = try? await fetch(request) else { return }
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                UIImage(data: data) != nil
            else { continue }
            guard store.fits(Int64(data.count)), await store.store(data, for: key) else { return }
        }
    }
}
