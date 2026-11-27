import Foundation
import Testing

@testable import Klassik

struct HeardTests {
    private static func recording(plays: [Int?], played: [String?] = []) -> WorkIndex.Recording {
        let songs = plays.enumerated().map { offset, count in
            Song(
                id: "s\(offset)", title: "T\(offset)", track: offset + 1, playCount: count,
                played: offset < played.count ? played[offset] : nil)
        }
        return WorkIndex.Recording(id: "r", album: "A", songs: songs)
    }

    @Test(arguments: [
        ([1, 1, nil], true), ([2, 1, 0, 1], true), ([1, 1, 1, nil, nil], true), ([3], true),
        ([1, nil, nil], false), ([1, 1, nil, nil], false), ([1, 1, nil, nil, nil], false), ([nil, nil], false),
        ([0], false),
    ] as [([Int?], Bool)])
    func heardNeedsMoreThanHalfTheMovements(plays: [Int?], expected: Bool) {
        #expect(Self.recording(plays: plays).isHeard == expected)
    }

    @Test func aRecordingWithoutTracksIsNotHeard() {
        #expect(!WorkIndex.Recording(id: "r", album: "A", songs: []).isHeard)
    }

    @Test func lastHeardIsTheNewestPlayedOfTheTracks() throws {
        let recording = Self.recording(
            plays: [1, 1, 1],
            played: ["2026-03-01T10:00:00Z", "2026-05-02T08:30:00.123456789Z", "2026-04-01T00:00:00Z"])
        let expected = try #require(ISO8601DateFormatter().date(from: "2026-05-02T08:30:00Z"))
        let last = try #require(recording.lastHeard)
        #expect(abs(last.timeIntervalSince(expected)) < 1)
    }

    @Test func lastHeardIsNilWithoutPlayedDates() {
        #expect(Self.recording(plays: [1, 1]).lastHeard == nil)
        #expect(Self.recording(plays: [nil], played: ["not a date"]).lastHeard == nil)
    }

    @Test func songDecodesPlayedFromTheServer() throws {
        let json = Data(
            #"{"id":"a","title":"T","playCount":2,"played":"2026-05-02T08:30:00.5Z"}"#.utf8)
        let song = try JSONDecoder().decode(Song.self, from: json)
        #expect(song.playCount == 2)
        #expect(song.played == "2026-05-02T08:30:00.5Z")
        #expect(song.lastPlayed != nil)
    }

    @Test func songsFromAnOlderCacheStillDecode() throws {
        let song = try JSONDecoder().decode(Song.self, from: Data(#"{"id":"a","title":"T"}"#.utf8))
        #expect(song.played == nil)
        #expect(song.lastPlayed == nil)
    }
}
