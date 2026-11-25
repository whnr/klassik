import Foundation
import Testing

@testable import KlassikEngine

struct M4AGaplessInfoTests {
    static func be(_ values: UInt32...) -> [UInt8] {
        values.flatMap { [UInt8($0 >> 24), UInt8($0 >> 16 & 0xFF), UInt8($0 >> 8 & 0xFF), UInt8($0 & 0xFF)] }
    }

    static func box(_ type: String, _ payload: [UInt8]) -> [UInt8] {
        be(UInt32(payload.count + 8)) + Array(type.utf8) + payload
    }

    static func header(_ type: String, scale: UInt32) -> [UInt8] {
        box(type, be(0, 0, 0, scale, 0) + [UInt8](repeating: 0, count: 80))
    }

    static func stts(_ entries: [(UInt32, UInt32)]) -> [UInt8] {
        box("stts", be(0, UInt32(entries.count)) + entries.flatMap { be($0.0, $0.1) })
    }

    static func elst(_ entries: [(duration: UInt32, time: Int32)]) -> [UInt8] {
        let list = entries.flatMap { be($0.duration, UInt32(bitPattern: $0.time), 0x10000) }
        return box("edts", box("elst", be(0, UInt32(entries.count)) + list))
    }

    static func smpb(_ text: String) -> [UInt8] {
        let mean = box("mean", be(0) + Array("com.apple.iTunes".utf8))
        let name = box("name", be(0) + Array("iTunSMPB".utf8))
        let item = mean + name + box("data", be(1, 0) + Array(text.utf8))
        return box("udta", box("meta", be(0) + box("ilst", box("----", item))))
    }

    /// A moov box body with one audio track of 44.1 kHz and a movie time scale of 1000, as ffmpeg writes it.
    static func moov(
        stts entries: [(UInt32, UInt32)], edits: [(duration: UInt32, time: Int32)]?, tag: [UInt8] = []
    ) -> [UInt8] {
        let table = box("stbl", stts(entries))
        let media = box("mdia", header("mdhd", scale: 44_100) + box("minf", box("smhd", be(0, 0)) + table))
        let track = box("trak", (edits.map(elst) ?? []) + media)
        return header("mvhd", scale: 1000) + track + tag
    }

    @Test func readsFFmpegEditList() {
        let body = Self.moov(stts: [(22, 1024), (1, 547)], edits: [(500, 1024)])
        #expect(M4AGaplessInfo.parse(moov: body) == M4AGaplessInfo(priming: 1024, valid: 22_051, total: 23_075))
    }

    @Test func readsAppleTag() {
        let tag = Self.smpb(" 00000000 00000840 000001C0 000000000000EA61 00000000 00000000 00000000")
        let body = Self.moov(stts: [(61, 1024), (1, 97)], edits: nil, tag: tag)
        #expect(M4AGaplessInfo.parse(moov: body) == M4AGaplessInfo(priming: 2112, valid: 60_001, total: 62_561))
    }

    @Test func theTagWinsOverTheEditList() {
        let tag = Self.smpb(" 00000000 00000840 000001C0 000000000000EA61 00000000 00000000 00000000")
        let body = Self.moov(stts: [(61, 1024), (1, 97)], edits: [(1360, 1024)], tag: tag)
        #expect(M4AGaplessInfo.parse(moov: body)?.priming == 2112)
    }

    @Test func skipsAnEmptyEdit() {
        let body = Self.moov(stts: [(22, 1024), (1, 547)], edits: [(100, -1), (500, 1024)])
        #expect(M4AGaplessInfo.parse(moov: body)?.priming == 1024)
    }

    @Test func anEditShorterThanThePacketsEndsTheRecording() {
        let body = Self.moov(stts: [(22, 1024), (1, 547)], edits: [(300, 1024)])
        #expect(M4AGaplessInfo.parse(moov: body)?.valid == 13_230)
    }

    @Test func aFileWithoutTrimDataHasNoInfo() {
        #expect(M4AGaplessInfo.parse(moov: Self.moov(stts: [(22, 1024)], edits: nil)) == nil)
        #expect(M4AGaplessInfo.parse(moov: []) == nil)
    }

    @Test func cutsPrimingAndRemainderWhenTheDecoderDoesNot() {
        let info = M4AGaplessInfo(priming: 1024, valid: 22_051, total: 23_075)
        #expect(info.playableRange(decodedLength: 23_075) == 1024..<23_075)
    }

    @Test func cutsTheRemainderWhenTheDecoderRemovedThePriming() {
        let info = M4AGaplessInfo(priming: 2112, valid: 60_001, total: 62_561)
        #expect(info.playableRange(decodedLength: 60_449) == 0..<60_001)
    }

    @Test func keepsTheWholeFileWhenTheDecoderTrims() {
        let info = M4AGaplessInfo(priming: 1024, valid: 22_051, total: 23_075)
        #expect(info.playableRange(decodedLength: 22_051) == 0..<22_051)
    }

    @Test func keepsAnUnknownLengthWhole() {
        let info = M4AGaplessInfo(priming: 1024, valid: 22_051, total: 23_075)
        #expect(info.playableRange(decodedLength: 23_000) == 0..<23_000)
    }

    @Test(arguments: [("aac-1", 1024, 22_051, 23_075), ("aac-2", 1024, 18_017, 19_041), ("alac-1", 0, 22_051, 22_051)])
    func readsTheFixtureFiles(name: String, priming: Int64, valid: Int64, total: Int64) throws {
        let info = M4AGaplessInfo.parse(fileAt: try FormatFixtures.url(name, "m4a"))
        #expect(info == M4AGaplessInfo(priming: priming, valid: valid, total: total))
    }

    @Test func otherFilesHaveNoInfo() throws {
        #expect(M4AGaplessInfo.parse(fileAt: try FormatFixtures.url("wav-1", "wav")) == nil)
        #expect(M4AGaplessInfo.parse(fileAt: try FormatFixtures.url("mp3-1", "mp3")) == nil)
    }
}
