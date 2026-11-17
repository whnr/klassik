import AVFoundation
import Testing
import UIKit

@testable import Klassik

@MainActor
struct CoverArtTests {
    private let remote = URL(string: "https://music.example.org/cover")!

    @Test func requestAuthenticationDoesNotChangeTheLoadingIdentity() throws {
        let credentials = ServerCredentials(url: remote, username: "fixture", password: "fixture")
        let source = CoverArt.Source(files: [], coverID: "album", pixels: 160, credentials: credentials)
        let again = CoverArt.Source(files: [], coverID: "album", pixels: 160, credentials: credentials)
        let request = try #require(source.remote)
        #expect(
            URLComponents(url: request, resolvingAgainstBaseURL: false)?.queryItems?.contains { $0.name == "s" } == true
        )
        #expect(source == again)
        var changed = again
        changed.pixels = 320
        #expect(source != changed)
        changed = again
        changed.files = [URL(filePath: "/downloaded.mp3")]
        #expect(source != changed)
        changed = again
        changed.credentials?.password = "replacement"
        #expect(source != changed)
    }

    private func picture() -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8), format: format).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        }
    }

    @Test func localArtworkWorksWithoutANetworkRequest() async throws {
        let first = URL(filePath: "/missing.mp3")
        let second = URL(filePath: "/downloaded.mp3")
        let cover = picture()
        var read: [URL] = []
        var fetched = false
        let image = await CoverArt.load(
            files: [first, second], remote: remote,
            embedded: { file in
                read.append(file)
                return file == second ? cover : nil
            },
            fetch: { _ in
                fetched = true
                throw URLError(.notConnectedToInternet)
            })
        #expect(image === cover)
        #expect(read == [first, second])
        #expect(!fetched)
    }

    @Test func serverArtworkRemainsTheFallback() async throws {
        let data = try #require(picture().pngData())
        for status in [200, 404] {
            let image = await CoverArt.load(
                files: [], remote: remote,
                fetch: { url in
                    #expect(url == remote)
                    return (data, HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!)
                })
            #expect((image != nil) == (status == 200))
        }
        #expect(await CoverArt.load(files: [], remote: nil) == nil)
    }

    @Test func readsArtworkFromAnAudioFileWithoutAServerID() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let wav = root.appending(path: "tone.wav")
        let output = root.appending(path: "tone.m4a")
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1))
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4_410))
        buffer.frameLength = buffer.frameCapacity
        let samples = try #require(buffer.floatChannelData?[0])
        for index in 0..<Int(buffer.frameLength) { samples[index] = 0 }
        do {
            let file = try AVAudioFile(forWriting: wav, settings: format.settings)
            try file.write(from: buffer)
        }
        let exporter = try #require(
            AVAssetExportSession(asset: AVURLAsset(url: wav), presetName: AVAssetExportPresetAppleM4A))
        let artwork = AVMutableMetadataItem()
        artwork.identifier = .commonIdentifierArtwork
        artwork.value = try #require(picture().pngData()) as NSData
        exporter.metadata = [artwork]
        try await exporter.export(to: output, as: .m4a)
        let image = await CoverArt.load(files: [output], remote: nil)
        #expect(image?.size == CGSize(width: 8, height: 8))
        #expect(await CoverArt.embedded(in: wav) == nil)
        #expect(await CoverArt.embedded(in: root.appending(path: "absent.mp3")) == nil)
    }

    @Test func decodesThePictureInAFLACDownload() async throws {
        let file = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString + ".flac")
        defer { try? FileManager.default.removeItem(at: file) }
        func integer(_ value: Int) -> Data {
            withUnsafeBytes(of: UInt32(value).bigEndian) { Data($0) }
        }
        let png = try #require(picture().pngData())
        let pictureBlock =
            integer(3) + integer(9) + Data("image/png".utf8) + integer(0)
            + integer(8) + integer(8) + integer(24) + integer(0) + integer(png.count) + png
        let data = Data("fLaC".utf8) + Data([0x86]) + integer(pictureBlock.count).dropFirst() + pictureBlock
        try data.write(to: file)
        let image = await CoverArt.load(files: [file], remote: nil)
        #expect(image?.size == CGSize(width: 8, height: 8))
    }
}
