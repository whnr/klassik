import Foundation

/// What the playback session needs from the server. Production uses `SubsonicClient`; tests use an in-memory server.
protocol ServerPort: Sendable {
    /// The address of the original file of a track. A transcoded stream loses the MP3 gapless header.
    func streamURL(songID: String) -> URL
}

extension SubsonicClient: ServerPort {}
