import Testing

@testable import Klassik
@testable import KlassikEngine

/// The quality line says what the app and iOS report, and never claims a bit-perfect path (sz-u8f4).
struct AudioQualityTests {
    private func path(
        engine: Double, hardware: Double, mixer: Double? = nil, channels: Int = 2, gainStage: Bool = false
    ) -> PlaybackSignalPath {
        PlaybackSignalPath(
            engineRate: engine, engineChannels: 2,
            outputs: PlaybackOutputFormats(
                mixerRate: mixer ?? engine, mixerChannels: channels, hardwareRate: hardware,
                hardwareChannels: channels),
            gainStage: gainStage)
    }

    private let flac = PlaybackTrack(id: "t", suffix: "flac", samplingRate: 96_000, bitDepth: 24)

    @Test func aNativeRateWithoutAGainStageIsNotVerified() {
        let line = AudioQuality.line(track: flac, path: path(engine: 96_000, hardware: 96_000))
        #expect(line == "FLAC 24-bit 96 kHz · output 96 kHz · bit-perfect not verified")
    }

    @Test func aRateConversionByIOSIsProcessing() {
        let line = AudioQuality.line(track: flac, path: path(engine: 96_000, hardware: 48_000, mixer: 48_000))
        #expect(line == "FLAC 24-bit 96 kHz · output 48 kHz · processing active: iOS converts to 48 kHz")
    }

    @Test func aGainStageIsProcessingEvenAtTheSameRate() {
        let line = AudioQuality.line(track: flac, path: path(engine: 96_000, hardware: 96_000, gainStage: true))
        #expect(line?.contains("processing active: ReplayGain stage in the path") == true)
    }

    @Test func aChannelChangeIsProcessing() {
        let line = AudioQuality.line(track: flac, path: path(engine: 96_000, hardware: 96_000, channels: 1))
        #expect(line?.contains("iOS changes the channels") == true)
    }

    @Test func aLossySourceIsLabelled() {
        let mp3 = PlaybackTrack(id: "t", suffix: "mp3", samplingRate: 44_100)
        let line = AudioQuality.line(track: mp3, path: path(engine: 44_100, hardware: 44_100))
        #expect(line == "MP3 44.1 kHz · output 44.1 kHz · lossy source · bit-perfect not verified")
    }

    @Test func theFileAloneGivesTheFormatBeforeTheGraphExists() {
        #expect(AudioQuality.line(track: flac, path: nil) == "FLAC 24-bit 96 kHz")
    }

    @Test func opusIsLabelledUnsupported() {
        let opus = PlaybackTrack(id: "t", suffix: "opus")
        #expect(AudioQuality.line(track: opus, path: nil) == "Opus is not supported on iOS.")
    }

    @Test func kilohertzDropsAZeroFraction() {
        #expect(AudioQuality.kilohertz(44_100) == "44.1")
        #expect(AudioQuality.kilohertz(192_000) == "192")
        #expect(AudioQuality.kilohertz(88_200) == "88.2")
    }
}
