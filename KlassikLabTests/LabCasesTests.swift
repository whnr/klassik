import Foundation
import Testing

@testable import KlassikLab

struct LabCasesTests {
    private func song(
        _ id: String, disc: Int?, track: Int?, suffix: String = "flac", path: String? = nil, work: String? = nil,
        depth: Int? = nil, rate: Int? = nil, bitRate: Int? = nil
    ) -> LabSong {
        LabSong(
            id: id, title: id, track: track, discNumber: disc, duration: 60, suffix: suffix, bitRate: bitRate,
            samplingRate: rate, bitDepth: depth, channelCount: 2, path: path,
            works: work.map { [LabSong.Work(name: $0)] }, replayGain: nil)
    }

    @Test func casesFollowDiscOrderAndMovementsFollowTrackOrder() {
        let cases = LabCase.cases(from: [
            song("b2", disc: 2, track: 2), song("a2", disc: 1, track: 2), song("b1", disc: 2, track: 1),
            song("a1", disc: 1, track: 1),
        ])
        #expect(cases.map(\.id) == [1, 2])
        #expect(cases.map { $0.songs.map(\.id) } == [["a1", "a2"], ["b1", "b2"]])
    }

    @Test func theTitleIsTheWorkThenTheFolderThenTheDisc() {
        let cases = LabCase.cases(from: [
            song("a", disc: 1, track: 1, path: "Playback Lab/01 x/01.flac", work: "FLAC 24/96"),
            song("b", disc: 2, track: 1, path: "Playback Lab/02 FLAC 16-44/01.flac"),
            song("c", disc: 3, track: 1),
        ])
        #expect(cases.map(\.title) == ["FLAC 24/96", "FLAC 16-44", "Case 3"])
    }

    @Test func opusIsUnsupportedAndFlacIsNot() {
        let cases = LabCase.cases(from: [
            song("a", disc: 1, track: 1, suffix: "opus"), song("b", disc: 2, track: 1),
        ])
        #expect(cases[0].unsupportedReason == "OPUS is not supported on iOS")
        #expect(cases[1].unsupportedReason == nil)
    }

    @Test func theSourceLineNamesFormatDepthAndRates() {
        let hires = LabCase.cases(from: [song("a", disc: 1, track: 1, depth: 24, rate: 96_000)])[0]
        #expect(hires.sourceLine == "FLAC 24-bit 96 kHz")
        let change = LabCase.cases(from: [
            song("a", disc: 1, track: 1, depth: 24, rate: 96_000),
            song("b", disc: 1, track: 2, depth: 24, rate: 44_100),
        ])[0]
        #expect(change.sourceLine == "FLAC 24-bit 96 then 44.1 kHz")
        let lossy = LabCase.cases(from: [song("a", disc: 1, track: 1, suffix: "m4a", rate: 44_100, bitRate: 256)])[0]
        #expect(lossy.sourceLine == "M4A 44.1 kHz 256 kbit/s")
    }

    @Test func onlyAnMP3WithoutHeaderCarriesTheGapNote() throws {
        let bare = LabCase.cases(from: [song("a", disc: 1, track: 1, suffix: "mp3", work: "MP3 without header")])[0]
        let note = try #require(bare.gapNote)
        #expect(note.contains("no gapless header"))
        #expect(note.contains("no delay and padding data"))
        let lame = LabCase.cases(from: [song("a", disc: 1, track: 1, suffix: "mp3", work: "MP3 with LAME header")])[0]
        #expect(lame.gapNote == nil)
        let flac = LabCase.cases(from: [song("a", disc: 1, track: 1, work: "FLAC without header")])[0]
        #expect(flac.gapNote == nil)
    }

    @Test func onlyTheToneCasesCarryAListenNote() throws {
        let pure = LabCase.cases(from: [song("a", disc: 1, track: 1, work: "Wave 440 Hz")])[0]
        #expect(try #require(pure.listenNote).contains("click"))
        let chord = LabCase.cases(from: [song("a", disc: 1, track: 1, work: "Wave Chord")])[0]
        #expect(chord.listenNote != nil)
        let flac = LabCase.cases(from: [song("a", disc: 1, track: 1, work: "FLAC 24/96")])[0]
        #expect(flac.listenNote == nil)
    }
}
