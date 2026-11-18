import AVFoundation
import AudioToolbox
import XCTest

@testable import Klassik

/// The decoder must produce PCM without receiving a complete resource before playback changes can ship.
final class EarlyPlaybackTests: XCTestCase {
    func testMP3ProducesPCMBeforeCompleteDelivery() async throws {
        try await measure(suffix: "mp3", type: kAudioFileMP3Type)
    }

    func testFLACProducesPCMBeforeCompleteDelivery() async throws {
        try await measure(suffix: "flac", type: kAudioFileFLACType)
    }

    private func measure(suffix: String, type: AudioFileTypeID) async throws {
        let env = ProcessInfo.processInfo.environment
        guard let server = env["KLASSIK_SERVER_URL"], let url = ServerCredentials.normalizedURL(from: server) else {
            throw XCTSkip("No fixture server configured")
        }
        let client = SubsonicClient(
            credentials: ServerCredentials(
                url: url, username: env["KLASSIK_USERNAME"] ?? "", password: env["KLASSIK_PASSWORD"] ?? ""))
        let album = try await client.searchAlbums("Early Playback").first {
            $0.name == "Early Playback \(suffix.uppercased())"
        }
        let songs = try await client.album(id: XCTUnwrap(album).id).songs
        let song = try XCTUnwrap(songs.first)
        let (data, _) = try await URLSession.shared.data(from: client.streamURL(songID: song.id))
        XCTAssertGreaterThanOrEqual(data.count, 100_000_000, "The gate needs a genuine large encoded resource")
        let source = DecoderProbeBytes(data)
        let started = ContinuousClock.now
        var file: AudioFileID?
        let opened = AudioFileOpenWithCallbacks(
            Unmanaged.passUnretained(source).toOpaque(),
            { context, position, requested, destination, actual in
                let source = Unmanaged<DecoderProbeBytes>.fromOpaque(context).takeUnretainedValue()
                return source.read(position: position, requested: requested, into: destination, actual: actual)
            }, nil,
            { context in
                return Int64(Unmanaged<DecoderProbeBytes>.fromOpaque(context).takeUnretainedValue().data.count)
            }, nil, type, &file)
        XCTAssertEqual(opened, noErr)
        let audioFile = try XCTUnwrap(file)
        defer { AudioFileClose(audioFile) }
        let bytesAtOpen = source.delivered
        var extended: ExtAudioFileRef?
        let wrapped = ExtAudioFileWrapAudioFileID(audioFile, false, &extended)
        XCTAssertEqual(wrapped, noErr)
        let decoder = try XCTUnwrap(extended)
        defer { ExtAudioFileDispose(decoder) }
        var format = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        XCTAssertEqual(ExtAudioFileGetProperty(decoder, kExtAudioFileProperty_FileDataFormat, &size, &format), noErr)
        let pcm = try XCTUnwrap(
            AVAudioFormat(standardFormatWithSampleRate: format.mSampleRate, channels: format.mChannelsPerFrame))
        var description = pcm.streamDescription.pointee
        XCTAssertEqual(
            ExtAudioFileSetProperty(
                decoder, kExtAudioFileProperty_ClientDataFormat,
                UInt32(MemoryLayout<AudioStreamBasicDescription>.size), &description), noErr)
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: pcm, frameCapacity: 11_025))
        var frames: UInt32 = 11_025
        let decoded = ExtAudioFileRead(decoder, &frames, buffer.mutableAudioBufferList)
        let elapsed = started.duration(to: .now)
        let report = """
            \(suffix): resource=\(data.count), bytesAtOpen=\(bytesAtOpen), bytesAtPCM=\(source.delivered)
            reads=\(source.reads), firstPCMFrames=\(frames), status=\(decoded), elapsed=\(elapsed)
            Callback delivery exposes only requested ranges. The decoder has no complete local file.
            """
        print(report)
        let attachment = XCTAttachment(string: report)
        attachment.name = "early-\(suffix)-report.txt"
        attachment.lifetime = .keepAlways
        add(attachment)
        XCTAssertEqual(decoded, noErr, report)
        XCTAssertEqual(frames, 11_025, report)
        XCTAssertLessThan(source.delivered, data.count, report)
        XCTAssertLessThan(source.delivered, 1_000_000, "Initialization must not scan the resource. \(report)")
        XCTAssertLessThan(elapsed, .milliseconds(500), report)
        let samples = try XCTUnwrap(buffer.floatChannelData)[0]
        XCTAssertTrue((0..<Int(frames)).contains { abs(samples[$0]) > 0.001 }, report)
    }
}

/// Records each delivery, including repeated reads, to reject a decoder that consumes the complete resource.
private final class DecoderProbeBytes {
    let data: Data
    var delivered = 0
    var reads = 0

    init(_ data: Data) { self.data = data }

    func read(
        position: Int64, requested: UInt32, into destination: UnsafeMutableRawPointer,
        actual: UnsafeMutablePointer<UInt32>
    ) -> OSStatus {
        guard position >= 0, position <= data.count else { return kAudioFilePositionError }
        let start = Int(position)
        let count = min(Int(requested), data.count - start)
        data.withUnsafeBytes { bytes in
            if count > 0 { destination.copyMemory(from: bytes.baseAddress!.advanced(by: start), byteCount: count) }
        }
        delivered += count
        reads += 1
        actual.pointee = UInt32(count)
        return noErr
    }
}
