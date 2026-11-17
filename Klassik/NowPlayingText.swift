import Foundation

/// The system receives three fields. It controls their layout on the lock screen and in Control Center.
/// The lock screen can leave out the album field, so the artist field repeats composer and work before the
/// performers.
struct NowPlayingText {
    let title: String
    let artist: String
    let album: String

    init(song: Song, work: WorkIndex.Work) {
        let workName = song.works?.first?.name ?? (work.isTagged ? work.title : "")
        // A movement name alone does not name the work, so an untagged work keeps the full track title.
        title = workName.isEmpty ? song.title : song.movementTitle
        let composer = song.composerName == Song.unknownComposer ? work.composer : song.composerName
        let composerName = composer == Song.unknownComposer ? "" : composer
        album = [composerName, workName].filter { !$0.isEmpty }.joined(separator: ", ")
        artist = [album, Roles.lockScreenNames(of: song)].filter { !$0.isEmpty }.joined(separator: ", ")
    }
}
