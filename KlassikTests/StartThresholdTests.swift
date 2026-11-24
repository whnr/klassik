import Foundation
import Testing

@testable import Klassik
@testable import KlassikEngine

/// The start threshold and its inputs follow the formula and the table of ADR 0060.
struct StartThresholdTests {
    /// The rows of the table in ADR 0060, for a long track: encoded bitrate, throughput, target seconds.
    @Test(arguments: [
        (320_000.0, 1_280_000.0, 0.25),
        (1_000_000.0, 2_000_000.0, 0.5),
        (1_000_000.0, 1_000_000.0, 1.0),
        (1_000_000.0, 750_000.0, 9.5),
        (1_000_000.0, 500_000.0, 17.0),
    ])
    func theTableOfTheRecord(bitrate: Double, throughput: Double, target: Double) throws {
        let seconds = try #require(StartThreshold.seconds(bitrate: bitrate, throughput: throughput, remaining: 600))
        #expect(abs(seconds - target) < 0.000_1)
    }

    @Test func aFastConnectionStillDecodesAQuarterSecond() {
        #expect(StartThreshold.seconds(bitrate: 320_000, throughput: 100_000_000, remaining: 600) == 0.25)
    }

    @Test func aShortTrackNeedsNoMoreThanItself() {
        #expect(StartThreshold.seconds(bitrate: 1_000_000, throughput: 500_000, remaining: 4) == 4)
        #expect(StartThreshold.seconds(bitrate: 1_000_000, throughput: 4_000_000, remaining: 0.1) == 0.1)
    }

    /// The deficit counts at most 30 seconds of the track, so a slow start never waits for most of a long file.
    @Test func theDeficitHorizonBoundsASlowStart() throws {
        let long = try #require(StartThreshold.seconds(bitrate: 1_000_000, throughput: 250_000, remaining: 3600))
        let short = try #require(StartThreshold.seconds(bitrate: 1_000_000, throughput: 250_000, remaining: 20))
        #expect(long == 2 + 0.75 * 30)
        #expect(short == 2 + 0.75 * 20)
    }

    @Test func aNewPathWaitsForTwoSecondsBeforeItsFirstWindow() {
        #expect(StartThreshold.seconds(bitrate: 1_000_000, throughput: nil, remaining: 600) == 2)
        #expect(StartThreshold.seconds(bitrate: 1_000_000, throughput: nil, remaining: 1.5) == 1.5)
    }

    @Test func nothingArrivingMeansWaiting() {
        #expect(StartThreshold.seconds(bitrate: 1_000_000, throughput: 0, remaining: 600) == nil)
    }

    // MARK: Throughput

    @Test func throughputNeedsAFirstWindow() {
        var meter = ThroughputMeter()
        meter.start(at: 10)
        meter.record(10_000, at: 10.1)
        #expect(meter.bitsPerSecond(at: 10.2) == nil)
        #expect(meter.bitsPerSecond(at: 10.25) != nil)
    }

    /// The lower of the short window and the two-second average wins, so a burst does not hide a slow line.
    @Test func throughputTakesTheLowerWindow() throws {
        var meter = ThroughputMeter()
        meter.start(at: 0)
        // 125 kB over the first second: 1 Mbit/s.
        for step in 1...20 { meter.record(6_250, at: Double(step) / 20) }
        let steady = try #require(meter.bitsPerSecond(at: 1))
        #expect(abs(steady - 1_000_000) < 1)
        // A stall counts: half a second later, the short window is empty.
        #expect(meter.bitsPerSecond(at: 1.5) == 0)
    }

    @Test func aNewPathStartsANewMeasurement() {
        var meter = ThroughputMeter()
        meter.start(at: 0)
        meter.record(100_000, at: 0.5)
        meter.start(at: 1)
        #expect(meter.bitsPerSecond(at: 1.1) == nil)
        meter.record(1_000, at: 1.2)
        #expect(meter.bitsPerSecond(at: 1.25) == 1_000 * 8 / 0.25)
    }

    // MARK: Bitrate

    @Test func lossyFormatsStartFromAFloor() {
        #expect(AudioBitrate.initial(Song(id: "a", title: "a", suffix: "mp3").playbackTrack) == 320_000)
        #expect(AudioBitrate.initial(Song(id: "a", title: "a", suffix: "m4a").playbackTrack) == 512_000)
        #expect(AudioBitrate.initial(Song(id: "a", title: "a", suffix: "mp3", bitRate: 400).playbackTrack) == 400_000)
    }

    @Test func losslessFormatsStartFromThePCMRate() {
        let song = Song(id: "a", title: "a", suffix: "flac", samplingRate: 96_000, bitDepth: 24, channelCount: 2)
        #expect(AudioBitrate.initial(song.playbackTrack) == 96_000 * 2 * 24)
        #expect(AudioBitrate.initial(Song(id: "a", title: "a", suffix: "flac").playbackTrack) == 44_100 * 2 * 16)
    }

    @Test func theObservedRateReplacesTheFloor() {
        let song = Song(id: "a", title: "a", suffix: "flac", bitRate: 900)
        #expect(AudioBitrate.current(song.playbackTrack, observed: 1_100_000) == 1_100_000)
        #expect(AudioBitrate.current(song.playbackTrack, observed: 700_000) == 900_000)
        #expect(AudioBitrate.current(song.playbackTrack, observed: nil) == AudioBitrate.initial(song.playbackTrack))
    }
}
