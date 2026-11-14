import Foundation

/// One thing in the queue: a recording of a work, or a whole album.
struct QueueItem: Codable, Identifiable, Sendable {
    var id = UUID()
    var work: WorkIndex.Work
    var recording: WorkIndex.Recording
}
