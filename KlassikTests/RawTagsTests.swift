import Foundation
import Testing

@testable import Klassik

struct RawTagsTests {
    private func rows(_ song: Song) -> [String] { song.tagRows.map { "\($0.name)=\($0.value)" } }

    @Test func aMovementShowsNameNumberAndCountAsOwnRows() {
        var song = Song(id: "s", title: "Allegro")
        song.movements = [Song.Movement(name: "Allegro", number: 3, count: 3)]
        let rows = rows(song)
        #expect(rows.contains("Movement name=Allegro"))
        #expect(rows.contains("Movement number=3"))
        #expect(rows.contains("Movement count=3"))
        #expect(!rows.contains { $0.contains("of 3") })
    }

    @Test func anAbsentMovementValueIsAnEmptyRowNotADash() {
        var song = Song(id: "s", title: "Allegro")
        song.movements = [Song.Movement(name: "Allegro", number: nil, count: nil)]
        let rows = rows(song)
        #expect(rows.contains("Movement number="))
        #expect(rows.contains("Movement count="))
        #expect(!rows.contains { $0.hasSuffix("=-") })
    }

    @Test func aContributorRoleKeepsTheServersCase() {
        var song = Song(id: "s", title: "T")
        song.contributors = [
            Song.Contributor(role: "conductor", subRole: nil, artist: .init(id: "a", name: "Abbado")),
            Song.Contributor(role: "performer", subRole: "violin", artist: .init(id: "b", name: "Mutter")),
        ]
        let rows = rows(song)
        #expect(rows.contains("conductor=Abbado"))
        #expect(rows.contains("performer/violin=Mutter"))
    }

    @Test func replayGainShowsTheNumberWithoutAUnit() {
        var song = Song(id: "s", title: "T")
        song.replayGain = Song.ReplayGain(trackGain: -6.5, albumGain: nil)
        #expect(rows(song).contains("Track gain (dB)=-6.5"))
    }
}
