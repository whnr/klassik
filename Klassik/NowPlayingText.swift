import Foundation

/// The system receives three fields. It controls their layout on the lock screen and in Control Center.
struct NowPlayingText {
    let title: String
    let artist: String
    let album: String

    init(song: Song, work: WorkIndex.Work) {
        title = song.movementTitle
        artist = Roles.lockScreenNames(of: song)
        let composer = song.composerName == Song.unknownComposer ? work.composer : song.composerName
        let name = song.works?.first?.name ?? (work.isTagged ? work.title : "")
        album = [composer == Song.unknownComposer ? "" : composer, name].filter { !$0.isEmpty }.joined(separator: ", ")
    }
}
