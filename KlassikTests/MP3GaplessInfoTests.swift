import Foundation
import Testing
@testable import Klassik

struct MP3GaplessInfoTests {
    /// The start of a mono 64 kbit/s file as ffmpeg writes it: ID3v2 tag, then the Info frame.
    static func header(frames: UInt32, delay: Int, padding: Int, id3Size: Int = 20) -> Data {
        var bytes: [UInt8] = [0x49, 0x44, 0x33, 4, 0, 0, 0, 0, 0, UInt8(id3Size)] + Array(repeating: 0, count: id3Size)
        bytes += [0xFF, 0xFB, 0x50, 0xC0] + Array(repeating: 0, count: 17)
        bytes += Array("Info".utf8) + [0, 0, 0, 0x0F]
        bytes += withUnsafeBytes(of: frames.bigEndian, Array.init)
        bytes += Array(repeating: 0, count: 4 + 100 + 4)
        bytes += Array("Lavc60.31".utf8) + Array(repeating: 0, count: 12)
        bytes += [UInt8(delay >> 4), UInt8((delay & 0x0F) << 4 | padding >> 8), UInt8(padding & 0xFF)]
        return Data(bytes + Array(repeating: 0, count: 64))
    }

    @Test func readsFFmpegHeader() {
        let info = MP3GaplessInfo.parse(Self.header(frames: 116, delay: 576, padding: 755))
        #expect(info == MP3GaplessInfo(frameCount: 116, samplesPerFrame: 1152, encoderDelay: 576, padding: 755))
        #expect(info?.validSamples == 132_301)
    }

    @Test func ignoresFileWithoutInfoFrame() {
        var data = Self.header(frames: 116, delay: 576, padding: 755)
        let info = data.range(of: Data("Info".utf8))!
        data.replaceSubrange(info, with: Data("Nope".utf8))
        #expect(MP3GaplessInfo.parse(data) == nil)
    }

    @Test func keepsWholeFileWhenDecoderTrims() {
        let info = MP3GaplessInfo(frameCount: 116, samplesPerFrame: 1152, encoderDelay: 576, padding: 755)
        #expect(info.playableRange(decodedLength: 132_301) == 0..<132_301)
    }

    @Test func cutsDelayAndPaddingWhenDecoderDoesNot() {
        let info = MP3GaplessInfo(frameCount: 116, samplesPerFrame: 1152, encoderDelay: 576, padding: 755)
        #expect(info.playableRange(decodedLength: 116 * 1152) == 576..<(576 + 132_301))
    }

    @Test func decodesAlbumWithSongsInOrder() throws {
        let json = #"""
        {"subsonic-response":{"status":"ok","version":"1.16.1","album":{"id":"a1","name":"Mendelssohn: Violin Concerto",
        "artist":"Eva Bogen","year":2008,"song":[
        {"id":"s2","title":"II. Andante","track":2,"discNumber":1,"duration":2,"suffix":"mp3"},
        {"id":"s1","title":"I. Allegro molto appassionato","track":1,"discNumber":1,"duration":3,"suffix":"mp3"}]}}}
        """#
        let album = try #require(SubsonicClient.decode(Data(json.utf8)).album)
        #expect(album.songs.map(\.id) == ["s1", "s2"])
    }

    @Test func streamAsksForOriginalFile() throws {
        let client = SubsonicClient(credentials: ServerCredentials(
            url: URL(string: "https://music.example.org")!, username: "joe", password: "sesame"))
        let components = try #require(URLComponents(url: client.streamURL(songID: "s1"), resolvingAgainstBaseURL: false))
        #expect(components.path == "/rest/stream")
        #expect(components.queryItems?.contains(URLQueryItem(name: "format", value: "raw")) == true)
        #expect(components.queryItems?.contains(URLQueryItem(name: "id", value: "s1")) == true)
    }
}
