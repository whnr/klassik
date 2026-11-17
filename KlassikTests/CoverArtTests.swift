import AVFoundation
import Testing
import UIKit

@testable import Klassik

@MainActor
struct CoverArtTests {
    private let remote = URL(string: "https://music.example.org/cover")!

    private func picture() -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).image { context in
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
}
