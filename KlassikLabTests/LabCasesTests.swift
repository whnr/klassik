import Foundation
import Testing

@testable import KlassikLab

struct LabCasesTests {
    /// The works of `scripts/playback_lab.py`, in disc order. `scripts/test_playback_lab.py` checks this list against
    /// the script.
    static let labTitles = [
        "FLAC 24/96", "FLAC 16/44.1", "FLAC 24/192", "ALAC 24/96", "ALAC 16/44.1", "AAC 256 with encoder delay",
        "MP3 with LAME header", "MP3 without header", "WAV", "AIFF", "Opus", "Rate change 96 kHz then 44.1 kHz",
    ]

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

    @Test func theTwelveCasesOfTheLabAlbumAllAppear() {
        let songs = Self.labTitles.enumerated().flatMap { index, title in
            (1...2).map { movement in
                song(
                    "\(index)-\(movement)", disc: index + 1, track: movement, suffix: index == 8 ? "wav" : "flac",
                    work: title)
            }
        }
        let cases = LabCase.cases(from: songs)
        #expect(cases.map(\.title) == Self.labTitles)
        #expect(cases.allSatisfy { $0.songs.count == 2 })
    }
}
