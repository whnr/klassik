import Foundation
import Testing

@testable import Klassik

@MainActor
struct PageMenuTests {
    private func titles(_ menu: PageMenu) -> [[String]] { menu.sections.map { $0.map(\.title) } }

    private func item(_ menu: PageMenu, _ action: PageMenu.Action) throws -> PageMenu.Item {
        try #require(menu.sections.joined().first { $0.action == action })
    }

    private func recording(sizes: [Int64?], id: String = "r1") -> WorkIndex.Recording {
        let songs = sizes.enumerated().map { Song(id: "\(id)-\($0.offset)", title: "Track", size: $0.element) }
        return WorkIndex.Recording(id: id, album: "Album", songs: songs)
    }

    private func stored(_ id: String, bytes: Int64 = 250_000_000) -> TrackStore.Download {
        TrackStore.Download(id: id, title: "Work", detail: "", songIDs: [], bytes: bytes, date: .now)
    }

    @Test func recordingAndAlbumKeepTheOneOrder() {
        for kind in [PageMenu.Kind.recording, .album] {
            let menu = PageMenu(kind: kind, download: .notDownloaded(bytes: nil), needsServer: false)
            #expect(titles(menu) == [["Play Next", "Add to Queue"], ["Download"], ["Tags and Grouping"]])
        }
    }

    @Test func workQueuesOnlyAndNamesNoRecording() {
        let menu = PageMenu(kind: .work, download: .downloaded(bytes: 1), needsServer: false)
        #expect(titles(menu) == [["Play Next", "Add to Queue"]])
        #expect(menu.sections.joined().allSatisfy { $0.subtitle == nil })
    }

    @Test func rowMenuHasPlayOnTopThenThePageOrder() {
        let play = PageMenu.play(isPlaying: false, isPaused: false)
        let menu = PageMenu(kind: .recording, download: .notDownloaded(bytes: nil), needsServer: false, play: play)
        #expect(titles(menu) == [["Play", "Play Next", "Add to Queue"], ["Download"], ["Tags and Grouping"]])
        let work = PageMenu(kind: .work, download: .notDownloaded(bytes: nil), needsServer: false, play: play)
        #expect(titles(work) == [["Play", "Play Next", "Add to Queue"]])
    }

    @Test func playOfThePlayingRecordingPausesAndResumes() {
        #expect(PageMenu.play(isPlaying: true, isPaused: false).title == "Pause")
        #expect(PageMenu.play(isPlaying: true, isPaused: true).title == "Resume")
        #expect(PageMenu.play(isPlaying: false, isPaused: true).title == "Play")
    }

    @Test func eachDownloadStateShowsBelowItsItemInTheSamePlace() throws {
        let size = PageMenu.size(250_000_000)
        let none = PageMenu(kind: .recording, download: .notDownloaded(bytes: 250_000_000), needsServer: false)
        let start = try item(none, .download)
        #expect(start.subtitle == size)
        #expect(!start.isDisabled)

        let running = PageMenu(kind: .recording, download: .downloading(share: 0.427), needsServer: false)
        #expect(try item(running, .cancelDownload).subtitle == "Downloading, 42\u{00A0}%")

        let done = PageMenu(kind: .recording, download: .downloaded(bytes: 250_000_000), needsServer: false)
        let remove = try item(done, .removeDownload)
        #expect(remove.subtitle == "Downloaded, \(size)")
        #expect(remove.isDestructive)

        for menu in [none, running, done] { #expect(menu.sections.map(\.count) == [2, 1, 1]) }
    }

    @Test func withoutTheServerDownloadIsDimmedAndSaysWhy() throws {
        let menu = PageMenu(kind: .album, download: .notDownloaded(bytes: 10), needsServer: true)
        let download = try item(menu, .download)
        #expect(download.isDisabled)
        #expect(download.subtitle == "Needs the server")
        let running = PageMenu(kind: .album, download: .downloading(share: 0.5), needsServer: true)
        #expect(try item(running, .cancelDownload).subtitle == "Downloading, waits for the server")
        // Only Download needs the server: the queue and the tags still work.
        #expect(menu.sections.joined().filter(\.isDisabled).map(\.action) == [.download])
    }

    @Test func partlyDownloadedAlbumCountsItsRecordings() throws {
        let menu = PageMenu(kind: .album, download: .partly(downloaded: 2, of: 5), needsServer: false)
        #expect(try item(menu, .download).subtitle == "2 of 5 recordings downloaded")
    }

    @Test func downloadStateComesFromTheStore() {
        let one = recording(sizes: [100, 150])
        #expect(PageMenu.download(of: one, parts: [], downloads: [], progress: [:]) == .notDownloaded(bytes: 250))
        #expect(
            PageMenu.download(of: recording(sizes: [100, nil]), parts: [], downloads: [], progress: [:])
                == .notDownloaded(bytes: nil))
        #expect(PageMenu.download(of: one, parts: [], downloads: [], progress: ["r1": 0.3]) == .downloading(share: 0.3))
        #expect(
            PageMenu.download(of: one, parts: [], downloads: [stored("r1", bytes: 9)], progress: [:])
                == .downloaded(bytes: 9))
    }

    @Test func albumIsPartlyDownloadedOnlyWithSomeOfSeveralRecordings() {
        let album = recording(sizes: [1], id: "album|a")
        let parts = ["p1", "p2", "p3"]
        #expect(
            PageMenu.download(of: album, parts: parts, downloads: [stored("p2")], progress: [:])
                == .partly(downloaded: 1, of: 3))
        #expect(
            PageMenu.download(of: album, parts: ["p1"], downloads: [stored("p1")], progress: [:])
                == .notDownloaded(bytes: 1))
        #expect(
            PageMenu.download(of: album, parts: parts, downloads: [stored("p2"), stored("album|a")], progress: [:])
                == .downloaded(bytes: 250_000_000))
    }

    @Test func itemsKeepTheIdentifiersOfTheUITests() {
        #expect(PageMenu.Action.download.identifier == "download")
        #expect(PageMenu.Action.removeDownload.identifier == "remove-download")
        #expect(PageMenu.Action.tags.identifier == "raw-tags")
    }
}
