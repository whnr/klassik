import UIKit
import Vision

/// A person picture on the device, upright, with the faces that Vision found.
struct LoadedPortrait: @unchecked Sendable {
    let image: UIImage
    /// Faces in the unit square of the picture, from its top left, largest first.
    let faces: [CGRect]

    /// The largest face: the picture of a composer centres on it.
    var face: CGRect? { faces.first }

    /// A portrait shows one person: a picture with no face or with several faces is no portrait (ADR 0019).
    var isPortrait: Bool { faces.count == 1 }

    /// The brightest quarter of a region of the picture, as one colour. A region is in the unit square of the
    /// picture. The brightest part decides, because the scrim must lift the text over the lightest spot.
    func brightestColour(in region: CGRect) -> PictureScrim.RGB {
        let white = PictureScrim.RGB(red: 1, green: 1, blue: 1)
        guard let cgImage = image.cgImage else { return white }
        let pixels = CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height)
        let crop = CGRect(
            x: region.minX * pixels.width, y: region.minY * pixels.height, width: region.width * pixels.width,
            height: region.height * pixels.height
        ).integral.intersection(pixels)
        guard !crop.isEmpty, let part = cgImage.cropping(to: crop) else { return white }
        let side = 16
        var bytes = [UInt8](repeating: 0, count: side * side * 4)
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard
                let context = CGContext(
                    data: buffer.baseAddress, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            // A coarse copy is a blur: the scrim answers the picture as the eye sees it behind the text.
            context.interpolationQuality = .high
            context.draw(part, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard drawn else { return white }
        let cells = (0..<side * side).map { index in
            PictureScrim.RGB(
                red: Double(bytes[index * 4]) / 255, green: Double(bytes[index * 4 + 1]) / 255,
                blue: Double(bytes[index * 4 + 2]) / 255)
        }.sorted { $0.luminance > $1.luminance }
        let top = cells.prefix(max(1, cells.count / 4))
        let count = Double(top.count)
        return PictureScrim.RGB(
            red: top.map(\.red).reduce(0, +) / count, green: top.map(\.green).reduce(0, +) / count,
            blue: top.map(\.blue).reduce(0, +) / count)
    }
}

enum PortraitLoader {
    /// The longest side of the copy that the app keeps, in pixels.
    static let longestSide: CGFloat = 1600
    /// The most bytes that a picture download may hold. A 1200 point Commons copy is far smaller.
    static let maxBytes = 8_000_000

    struct TooLarge: Error {}

    /// Streams the body and stops at the cap, so that a huge file never sits in memory. A redirect to a host
    /// outside the trusted list ends the request.
    static let download: MusicBrainz.Fetch = { request in
        let (bytes, response) = try await URLSession.shared.bytes(for: request, delegate: RedirectGuard())
        guard response.expectedContentLength <= Int64(maxBytes) else { throw TooLarge() }
        var data = Data()
        for try await byte in bytes {
            data.append(byte)
            if data.count > maxBytes { throw TooLarge() }
        }
        return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
    }

    /// The picture, or nil: for a URL outside the trusted list, a failed or oversize download, or bytes that
    /// are no image.
    static func load(_ url: URL, fetch: MusicBrainz.Fetch = PortraitLoader.download) async -> LoadedPortrait? {
        guard let url = PersonFactsService.trusted(url) else { return nil }
        var request = URLRequest(url: url, timeoutInterval: PersonFactsService.timeout)
        request.setValue(MusicBrainz.userAgent, forHTTPHeaderField: "User-Agent")
        guard let (data, status) = try? await fetch(request), (200..<300).contains(status),
            data.count <= maxBytes
        else { return nil }
        return await Task.detached(priority: .userInitiated) { upright(data) }.value
    }

    private final class RedirectGuard: NSObject, URLSessionTaskDelegate, Sendable {
        func urlSession(
            _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
            newRequest request: URLRequest
        ) async -> URLRequest? {
            PersonFactsService.trusted(request.url) == nil ? nil : request
        }
    }

    private static func upright(_ data: Data) -> LoadedPortrait? {
        guard let source = UIImage(data: data) else { return nil }
        let scale = min(1, longestSide / max(source.size.width, source.size.height, 1))
        let size = CGSize(width: source.size.width * scale, height: source.size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        // Drawing applies the orientation, so every later step reads the pixels as they show.
        let image = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            source.draw(in: CGRect(origin: .zero, size: size))
        }
        return LoadedPortrait(image: image, faces: faces(in: image))
    }

    private static func faces(in image: UIImage) -> [CGRect] {
        guard let cgImage = image.cgImage else { return [] }
        let request = VNDetectFaceRectanglesRequest()
        try? VNImageRequestHandler(cgImage: cgImage).perform([request])
        return (request.results ?? []).map { face in
            // Vision counts from the bottom left.
            let box = face.boundingBox
            return CGRect(x: box.minX, y: 1 - box.maxY, width: box.width, height: box.height)
        }.sorted { $0.width * $0.height > $1.width * $1.height }
    }
}
