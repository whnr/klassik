import ImageIO
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

    /// The face that the frame centres on. A composer picture centres on its largest face. A performer group or
    /// hall has none: it fills the frame from its centre (ADR 0043).
    func framingFace(performer: Bool) -> CGRect? { performer && !isPortrait ? nil : face }

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
    private final class Prepared: NSObject {
        weak var store: ImageStore?
        let revision: Int
        let portrait: LoadedPortrait

        init(store: ImageStore, revision: Int, portrait: LoadedPortrait) {
            self.store = store
            self.revision = revision
            self.portrait = portrait
        }
    }

    /// Decoded pixels can be discarded under memory pressure; the persistent picture store remains complete.
    @MainActor private static let prepared = NSCache<NSString, Prepared>()

    @MainActor private static func preparedKey(_ portrait: PersonPortrait, store: ImageStore) -> NSString {
        "\(ObjectIdentifier(store))|\(portrait.url.absoluteString)" as NSString
    }

    /// A hero reads decoded pixels synchronously, before its navigation transition draws the first frame.
    @MainActor static func ready(_ portrait: PersonPortrait?, store: ImageStore = .pictures) -> LoadedPortrait? {
        guard let portrait, let found = prepared.object(forKey: preparedKey(portrait, store: store)),
            found.store === store,
            files(of: portrait).contains(where: { store.contains($0.absoluteString) }),
            found.revision == store.revision(of: files(of: portrait).map(\.absoluteString))
        else { return nil }
        return found.portrait
    }

    @MainActor private static func prepare(_ loaded: LoadedPortrait, for portrait: PersonPortrait, store: ImageStore) {
        guard files(of: portrait).contains(where: { store.contains($0.absoluteString) }) else { return }
        let entry = Prepared(
            store: store, revision: store.revision(of: files(of: portrait).map(\.absoluteString)), portrait: loaded)
        let pixels = loaded.image.cgImage
        prepared.setObject(
            entry, forKey: preparedKey(portrait, store: store),
            cost: (pixels?.bytesPerRow ?? 0) * (pixels?.height ?? 0))
    }

    /// The longest side of the copy that the app keeps when it does not know the screen, in pixels.
    static let longestSide = CGFloat(PortraitSize.steps[PortraitSize.steps.count - 1])
    /// The most bytes that a picture download may hold. A Commons JPEG at the largest step is far smaller.
    static let maxBytes = 16_000_000

    struct TooLarge: Error {}

    /// The pictures stay in `ImageStore.pictures`, which the listener can see and limit (ADR 0051). A URL cache
    /// beside it would hold each picture twice.
    static let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.urlCache = nil
        return URLSession(configuration: configuration)
    }()

    /// The download of the app: a picture that is on the device loads from there.
    static let download: MusicBrainz.Fetch = stored(network) { ImageStore.pictures }

    /// A fetch that reads the store first and keeps each successful answer in it.
    static func stored(_ fetch: @escaping MusicBrainz.Fetch, in store: @escaping @MainActor @Sendable () -> ImageStore)
        -> MusicBrainz.Fetch
    {
        { request in
            let key = request.url?.absoluteString ?? ""
            if let data = await store().data(for: key) { return (data, 200) }
            let (data, status) = try await fetch(request)
            if (200..<300).contains(status), !data.isEmpty { await store().store(data, for: key) }
            return (data, status)
        }
    }

    /// Streams the body and stops at the cap, so that a huge file never sits in memory. A redirect to a host
    /// outside the trusted list ends the request.
    static let network: MusicBrainz.Fetch = { request in
        let (bytes, response) = try await session.bytes(for: request, delegate: RedirectGuard())
        guard response.expectedContentLength <= Int64(maxBytes) else { throw TooLarge() }
        var data = Data()
        for try await byte in bytes {
            data.append(byte)
            if data.count > maxBytes { throw TooLarge() }
        }
        return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
    }

    /// The download of the app. A UI test that stubs the facts also stubs the picture.
    static var launchDownload: MusicBrainz.Fetch {
        #if DEBUG
            if PersonLaunchStub.fetch != nil { return PersonLaunchStub.picture }
        #endif
        return download
    }

    /// The network of the people lookup, past the store, because a lookup replaces the kept picture.
    static var launchNetwork: MusicBrainz.Fetch {
        #if DEBUG
            if PersonLaunchStub.fetch != nil { return PersonLaunchStub.picture }
        #endif
        return network
    }

    /// The hero of this device before a page measures it: the screen width, at the specimen proportion.
    @MainActor static var deviceScreen: PortraitSize.Screen {
        let screen = UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.screen }.first
        // Without a scene, as in a background launch, the largest iPhone stands in.
        let width = screen?.bounds.width ?? 440
        return PortraitSize.Screen(
            hero: CGSize(width: width, height: min(width * Layout.pictureRatio, Layout.pictureMaxHeight)),
            scale: screen?.scale ?? 3)
    }

    /// Keeps the picture that a people lookup found, before any page needs it (ADR 0059). Each later lookup
    /// fetches it again, and only a valid picture replaces the kept file. When the picture of the person changed,
    /// the files of the old one go. The lookup stops at the Pictures limit.
    /// People pictures also load in Low Data Mode (ADR 0061). Returns false when nothing was kept.
    @MainActor @discardableResult static func keep(
        _ portrait: PersonPortrait, replacing old: PersonPortrait?, screen: PortraitSize.Screen,
        store: ImageStore, fetch: MusicBrainz.Fetch = PortraitLoader.launchNetwork
    ) async -> Bool {
        await store.loaded()
        guard !store.isFull, store.hasRoomForTypicalFile else { return false }
        let wanted = PortraitSize.candidates(portrait, screen: screen)
        for candidate in wanted {
            guard let url = PersonFactsService.trusted(candidate) else { continue }
            var request = URLRequest(url: url, timeoutInterval: PersonFactsService.timeout)
            request.setValue(MusicBrainz.userAgent, forHTTPHeaderField: "User-Agent")
            request.allowsConstrainedNetworkAccess = true
            guard let (data, status) = try? await fetch(request), (200..<300).contains(status), !data.isEmpty,
                data.count <= maxBytes
            else { continue }
            guard
                let loaded = await Task.detached(priority: .utility, operation: { upright(data, screen: screen) }).value
            else { continue }
            let key = url.absoluteString
            guard store.contains(key) || store.fits(Int64(data.count)), await store.store(data, for: key) else {
                return false
            }
            if let old, old != portrait {
                let kept = Set(wanted.map(\.absoluteString))
                for file in files(of: old) where !kept.contains(file.absoluteString) {
                    store.remove(named: ImageStore.name(file.absoluteString))
                }
            }
            prepare(loaded, for: portrait, store: store)
            return true
        }
        return false
    }

    /// Every file of a picture that a page of any size can keep.
    static func files(of portrait: PersonPortrait) -> [URL] {
        PortraitSize.steps.compactMap { PortraitSize.file(portrait, width: $0) } + [portrait.url]
    }

    /// The picture at the size that the screen needs (`PortraitSize`), or nil when no candidate loads. A
    /// candidate that fails gives way to the next one. Network cost never reduces the requested quality.
    /// A file that the lookup kept for this device loads first, so a page never waits for the network then.
    @MainActor static func load(
        _ portrait: PersonPortrait, screen: PortraitSize.Screen,
        fetch: MusicBrainz.Fetch = PortraitLoader.launchDownload, store: ImageStore = .pictures,
        kept device: PortraitSize.Screen = PortraitLoader.deviceScreen
    ) async -> LoadedPortrait? {
        if let ready = ready(portrait, store: store) { return ready }
        await store.loaded()
        let wanted = PortraitSize.candidates(portrait, screen: screen)
        let stored = (wanted + PortraitSize.candidates(portrait, screen: device)).filter {
            store.contains($0.absoluteString)
        }
        var seen: Set<URL> = []
        for candidate in (stored + wanted).filter({ seen.insert($0).inserted }) {
            let loaded = await load(candidate, screen: screen, fetch: fetch)
            if let loaded {
                prepare(loaded, for: portrait, store: store)
                return loaded
            }
        }
        return nil
    }

    /// The picture, or nil: for a URL outside the trusted list, a failed or oversize download, or bytes that
    /// are no image. With a screen, the copy keeps only the pixels that the screen needs.
    static func load(
        _ url: URL, screen: PortraitSize.Screen? = nil,
        fetch: MusicBrainz.Fetch = PortraitLoader.launchDownload
    ) async -> LoadedPortrait? {
        guard let url = PersonFactsService.trusted(url) else { return nil }
        var request = URLRequest(url: url, timeoutInterval: PersonFactsService.timeout)
        request.setValue(MusicBrainz.userAgent, forHTTPHeaderField: "User-Agent")
        // People pictures stay available on constrained connections; album art has a separate policy.
        request.allowsConstrainedNetworkAccess = true
        guard let (data, status) = try? await fetch(request), (200..<300).contains(status),
            data.count <= maxBytes
        else { return nil }
        return await Task.detached(priority: .userInitiated) { upright(data, screen: screen) }.value
    }

    private final class RedirectGuard: NSObject, URLSessionTaskDelegate, Sendable {
        func urlSession(
            _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
            newRequest request: URLRequest
        ) async -> URLRequest? {
            PersonFactsService.trusted(request.url) == nil ? nil : request
        }
    }

    private static func upright(_ data: Data, screen: PortraitSize.Screen?) -> LoadedPortrait? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            let pixelWidth = properties[kCGImagePropertyPixelWidth] as? NSNumber,
            let pixelHeight = properties[kCGImagePropertyPixelHeight] as? NSNumber,
            pixelWidth.doubleValue > 0, pixelHeight.doubleValue > 0
        else { return nil }
        let width = CGFloat(pixelWidth.doubleValue)
        let height = CGFloat(pixelHeight.doubleValue)
        let orientation = (properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
        let rotated = (5...8).contains(orientation)
        let aspect = rotated ? height / width : width / height
        let need = screen.map { PortraitSize.width(aspect: aspect, screen: $0) } ?? longestSide
        let longest = min(max(width, height), screen == nil ? longestSide : need * max(1, 1 / aspect))
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: Int(longest.rounded(.up)),
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let pixels = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let image = UIImage(cgImage: pixels)
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
