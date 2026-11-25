import AVFoundation
import Accelerate
import Foundation
import Testing

@testable import KlassikEngine

private final class BundleToken {}

/// The glide fixtures of scripts/format_fixtures.py: one continuous tone cut into two tracks per format.
enum FormatFixtures {
    static let lengths = [22_051, 18_017]
    static let rate = 44_100.0
    static let glide: [Float] = (0..<lengths.reduce(0, +)).map { n in
        let t = Double(n) / rate
        return Float(0.5 * sin(2 * .pi * (300 * t + 25 * t * t)))
    }

    /// The file name and extension of every format whose tracks carry exact gapless data.
    static let formats = [
        ("aac", "m4a"), ("alac", "m4a"), ("wav", "wav"), ("aiff", "aiff"), ("flac", "flac"), ("mp3", "mp3"),
    ]

    static func url(_ name: String, _ ext: String) throws -> URL {
        try #require(Bundle(for: BundleToken.self).url(forResource: name, withExtension: ext))
    }

    /// The recording of one track, as the engine cuts it.
    static func recording(_ name: String, _ ext: String) throws -> (range: Range<Int64>, samples: [Float]) {
        let file = try AVAudioFile(forReading: try url(name, ext))
        let range = GaplessEngine.playableRange(of: file)
        file.framePosition = range.lowerBound
        let count = AVAudioFrameCount(range.count)
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: count))
        try file.read(into: buffer, frameCount: count)
        return (range, Array(UnsafeBufferPointer(start: buffer.floatChannelData![0], count: Int(buffer.frameLength))))
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
}

/// Every format that iOS decodes joins two tracks of one recording without a missing or repeated sample.
struct FormatGaplessTests {
    /// Formats with exact gapless data: the engine must cut every priming and remainder frame.
    @Test(arguments: FormatFixtures.formats)
    func tracksHoldExactlyTheirSamples(name: String, ext: String) throws {
        let first = try FormatFixtures.recording("\(name)-1", ext)
        let second = try FormatFixtures.recording("\(name)-2", ext)
        #expect(first.samples.count == FormatFixtures.lengths[0], "\(name) first: range \(first.range)")
        #expect(second.samples.count == FormatFixtures.lengths[1], "\(name) second: range \(second.range)")
    }

    @Test(arguments: FormatFixtures.formats)
    func theJoinKeepsTheTone(name: String, ext: String) throws {
        let first = try FormatFixtures.recording("\(name)-1", ext)
        let second = try FormatFixtures.recording("\(name)-2", ext)
        let joined = first.samples + second.samples
        let join = FormatFixtures.lengths[0]
        let start = FormatFixtures.alignment(joined, at: 2048, referenceAt: 2048)
        let across = FormatFixtures.alignment(joined, at: join + 256, referenceAt: join + 256)
        #expect(start == 0, "\(name) start shift \(start)")
        #expect(across == 0, "\(name) join shift \(across)")
    }

    /// Lossless formats keep every sample: no frame is lost, doubled or changed beyond 16-bit rounding.
    @Test(arguments: [("alac", "m4a"), ("wav", "wav"), ("aiff", "aiff"), ("flac", "flac")])
    func losslessFormatsMatchTheReference(name: String, ext: String) throws {
        let first = try FormatFixtures.recording("\(name)-1", ext)
        let second = try FormatFixtures.recording("\(name)-2", ext)
        let joined = first.samples + second.samples
        #expect(joined.count == FormatFixtures.glide.count)
        let worst = zip(joined, FormatFixtures.glide).map { abs($0 - $1) }.max() ?? 0
        #expect(worst < 0.001, "\(name) worst difference \(worst)")
    }

    /// MP3 without a header has no record of its delay, so the file plays whole. The join is approximate (ADR 0005).
    @Test func anMP3WithoutHeaderPlaysWhole() throws {
        let file = try AVAudioFile(forReading: try FormatFixtures.url("mp3-bare-1", "mp3"))
        #expect(GaplessEngine.playableRange(of: file) == 0..<file.length)
    }
}
