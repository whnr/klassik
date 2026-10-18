import AVFoundation
import Accelerate
import AudioToolbox
import XCTest

@testable import Klassik

/// Measures how iOS decodes the attacca fixture work as Navidrome streams it, and whether the engine joins
/// its movements without a gap. The screens workflow runs it against the fixture server and keeps the report.
final class GaplessTests: XCTestCase {
    /// The glide from scripts/fixtures.py: 0.5 sin(2π(300 t + 25 t²)), cut into movements of these lengths.
    static let movementSamples = [132_301, 110_017, 154_441]
    static let sampleRate = 44_100.0
    static let glide: [Float] = (0..<movementSamples.reduce(0, +)).map { n in
        let t = Double(n) / sampleRate
        return Float(0.5 * sin(2 * .pi * (300 * t + 25 * t * t)))
    }

    func testAttaccaMovementsJoinWithoutGap() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let server = env["KLASSIK_SERVER_URL"], let url = ServerCredentials.normalizedURL(from: server) else {
            throw XCTSkip("No fixture server configured")
        }
        let client = SubsonicClient(
            credentials: ServerCredentials(
                url: url, username: env["KLASSIK_USERNAME"] ?? "", password: env["KLASSIK_PASSWORD"] ?? ""))
        let found = try await client.searchAlbums("Mendelssohn").first { $0.name == "Mendelssohn: Violin Concerto" }
        let songs = try await client.album(id: XCTUnwrap(found).id).songs
        guard songs.count == Self.movementSamples.count else {
            return XCTFail("Found \(songs.count) movements of Op. 64")
        }

        let folder = FileManager.default.temporaryDirectory.appending(path: "gapless-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var report = ["Gapless report. Lead and trail: decoded samples before and after the movement's own samples."]
        var files: [URL] = []
        var headers: [MP3GaplessInfo?] = []
        var start = 0
        for (index, song) in songs.enumerated() {
            let length = Self.movementSamples[index]
            let stream = client.streamURL(songID: song.id)
            let (data, _) = try await URLSession.shared.data(from: stream)
            let local = folder.appending(path: "\(index + 1).mp3")
            try data.write(to: local)
            files.append(local)
            let header = MP3GaplessInfo.parse(data)
            headers.append(header)

            let file = try AVAudioFile(forReading: local)
            let samples = try Self.read(file)
            let lead = Self.alignment(samples, at: 2048, referenceAt: start + 2048)
            let endShift = Self.alignment(samples, at: lead + length - 4096, referenceAt: start + length - 4096)
            let streamed = try await AVURLAsset(url: stream).load(.duration)
            let downloaded = try await AVURLAsset(url: local).load(.duration)
            report += [
                "Movement \(index + 1): \(length) samples, \(data.count) bytes",
                "  MP3 header: \(header.map { "\($0.frameCount) frames, delay \($0.encoderDelay), padding \($0.padding), valid \($0.validSamples)" } ?? "none")",
                "  AudioFile packet table: \(Self.describe(Self.fileTable(local)))",
                "  AudioFileStream packet table: \(Self.describe(Self.streamTable(data)))",
                "  AVAudioFile: length \(file.length), read \(samples.count), lead \(lead), trail \(samples.count - lead - length), shift at end \(endShift)",
                "  AVURLAsset duration in samples: streamed \(Self.samples(streamed)), downloaded \(Self.samples(downloaded))",
            ]
            start += length
        }

        let whole = try Self.joins(files) { file, _ in 0..<file.length }
        let trimmed = try Self.joins(files) { file, index in
            headers[index]?.playableRange(decodedLength: file.length) ?? 0..<file.length
        }
        report += [
            "Engine, whole decoded files: start \(whole.start), shift after each join \(whole.shifts)",
            "Engine, playable ranges from the MP3 header: start \(trimmed.start), shift after each join \(trimmed.shifts)",
        ]

        let text = report.joined(separator: "\n")
        print(text)
        let attachment = XCTAttachment(string: text)
        attachment.name = "gapless-report.txt"
        attachment.lifetime = .keepAlways
        add(attachment)
        XCTAssertEqual(trimmed.shifts, Array(repeating: 0, count: files.count - 1), text)
    }

    // MARK: Measurement

    static func read(_ file: AVAudioFile) throws -> [Float] {
        let buffer = try XCTUnwrap(
            AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)))
        try file.read(into: buffer)
        return Array(UnsafeBufferPointer(start: buffer.floatChannelData![0], count: Int(buffer.frameLength)))
    }

    /// The shift that lines `signal[at...]` up best with the glide from `referenceAt`, within ±3000 samples.
    static func alignment(_ signal: [Float], at: Int, referenceAt: Int, window: Int = 2048) -> Int {
        let reference = glide[referenceAt..<referenceAt + window]
        var best = (shift: 0, error: Float.infinity)
        for shift in -3000...3000 where at + shift >= 0 && at + shift + window <= signal.count {
            let error = vDSP.distanceSquared(signal[at + shift..<at + shift + window], reference)
            if error < best.error { best = (shift, error) }
        }
        return best.shift
    }

    /// Renders the files back to back through AVAudioPlayerNode, offline.
    /// Returns where the glide starts in the output and how far each join moves it.
    static func joins(
        _ urls: [URL], range: (AVAudioFile, Int) -> Range<Int64>
    ) throws -> (start: Int, shifts: [Int]) {
        let files = try urls.map { try AVAudioFile(forReading: $0) }
        let format = files[0].processingFormat
        let engine = AVAudioEngine()
        let node = AVAudioPlayerNode()
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 4096)
        try engine.start()
        var total = 8192
        for (index, file) in files.enumerated() {
            let frames = range(file, index)
            total += frames.count
            node.scheduleSegment(
                file, startingFrame: frames.lowerBound, frameCount: AVAudioFrameCount(frames.count), at: nil,
                completionHandler: nil)
        }
        node.play()
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat, frameCapacity: 4096))
        var output: [Float] = []
        while output.count < total {
            guard try engine.renderOffline(4096, to: buffer) == .success else { break }
            output += UnsafeBufferPointer(start: buffer.floatChannelData![0], count: Int(buffer.frameLength))
        }
        engine.stop()

        let start = alignment(output, at: 2048, referenceAt: 2048)
        var join = 0
        let shifts = movementSamples.dropLast().map { length in
            join += length
            return alignment(output, at: start + join + 256, referenceAt: join + 256)
        }
        return (start, shifts)
    }

    static func fileTable(_ url: URL) -> AudioFilePacketTableInfo? {
        var id: AudioFileID?
        guard AudioFileOpenURL(url as CFURL, .readPermission, kAudioFileMP3Type, &id) == noErr, let id else {
            return nil
        }
        defer { AudioFileClose(id) }
        var info = AudioFilePacketTableInfo()
        var size = UInt32(MemoryLayout<AudioFilePacketTableInfo>.size)
        return AudioFileGetProperty(id, kAudioFilePropertyPacketTableInfo, &size, &info) == noErr ? info : nil
    }

    static func streamTable(_ data: Data) -> AudioFilePacketTableInfo? {
        let found = PacketTable()
        var stream: AudioFileStreamID?
        let opened = AudioFileStreamOpen(
            Unmanaged.passUnretained(found).toOpaque(),
            { client, stream, property, _ in
                guard property == kAudioFileStreamProperty_PacketTableInfo else { return }
                var info = AudioFilePacketTableInfo()
                var size = UInt32(MemoryLayout<AudioFilePacketTableInfo>.size)
                if AudioFileStreamGetProperty(stream, property, &size, &info) == noErr {
                    Unmanaged<PacketTable>.fromOpaque(client).takeUnretainedValue().info = info
                }
            }, { _, _, _, _, _ in }, kAudioFileMP3Type, &stream)
        guard opened == noErr, let stream else { return nil }
        defer { AudioFileStreamClose(stream) }
        _ = data.withUnsafeBytes { AudioFileStreamParseBytes(stream, UInt32($0.count), $0.baseAddress!, []) }
        return found.info
    }

    private final class PacketTable {
        var info: AudioFilePacketTableInfo?
    }

    static func describe(_ info: AudioFilePacketTableInfo?) -> String {
        guard let info else { return "none" }
        return "valid \(info.mNumberValidFrames), priming \(info.mPrimingFrames), remainder \(info.mRemainderFrames)"
    }

    static func samples(_ time: CMTime) -> Int {
        Int((time.seconds * sampleRate).rounded())
    }
}
