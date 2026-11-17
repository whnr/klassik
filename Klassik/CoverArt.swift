import AVFoundation
import CryptoKit
import UIKit

@MainActor enum CoverArt {
    /// Authentication salts change per request, so a signed URL must not identify a view's loading task.
    struct Source: Equatable {
        var files: [URL]
        var coverID: String?
        var pixels: Int
        var credentials: ServerCredentials?

        var cacheKey: NSString? {
            let fields = [
                credentials?.url.absoluteString ?? "", credentials?.username ?? "", credentials?.password ?? "",
                coverID ?? files.first?.absoluteString ?? "", String(pixels),
            ]
            guard let data = try? JSONEncoder().encode(fields) else { return nil }
            return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() as NSString
        }

        var remote: URL? {
            guard let coverID, let credentials else { return nil }
            return SubsonicClient(credentials: credentials).coverArtURL(id: coverID, size: pixels)
        }
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

    static func load(
        files: [URL], remote: URL?,
        embedded: (URL) async -> UIImage? = CoverArt.embedded,
        fetch: (URL) async throws -> (Data, URLResponse) = { try await URLSession.shared.data(from: $0) }
    ) async -> UIImage? {
        for file in files {
            if Task.isCancelled { return nil }
            if let image = await embedded(file) { return image }
        }
        guard !Task.isCancelled, let remote, let (data, response) = try? await fetch(remote),
            let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode)
        else { return nil }
        return UIImage(data: data)
    }
}
