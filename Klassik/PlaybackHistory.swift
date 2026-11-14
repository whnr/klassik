import Foundation

/// The standard queue has movement IDs, but no recording or album boundaries.
struct ServerPlayQueue: Decodable, Sendable {
    var current: String?
    var position: Int64?
    var entry: [Song]?
}

/// Keeps server writes in order and preserves the item boundaries that the standard queue cannot store.
@MainActor
final class PlaybackHistory {
    struct Restored {
        var items: [QueueItem]
        var movement: Int
        var position: Double
    }

    private struct Listen {
        var item: UUID
        var movement: Int
        var position: Double
        var heard = 0.0
        var submitted = false
        var started = Date.now
    }

    private let server: any ServerPort
    private let defaults: UserDefaults
    private var writes: Task<Void, Never>?
    private var listen: Listen?
    var onError: ((String?) -> Void)?
    private(set) var error: String? {
        didSet { onError?(error) }
    }

    init(server: any ServerPort, defaults: UserDefaults) {
        self.server = server
        self.defaults = defaults
    }

    func save(items: [QueueItem], movement: Int, position: Double) {
        let songs = items.flatMap(\.recording.songs)
        let current =
            items.first?.recording.songs.indices.contains(movement) == true
            ? items.first?.recording.songs[movement].id : nil
        if let data = try? JSONEncoder().encode(items) { defaults.set(data, forKey: server.listeningDataKey) }
        enqueue { [server] in
            try await server.savePlayQueue(
                ids: songs.map(\.id), current: current, position: Int64(max(0, position) * 1000))
        }
    }

    func restore() async throws -> Restored? {
        guard let saved = try await server.getPlayQueue(), let songs = saved.entry, !songs.isEmpty,
            let current = saved.current, let index = songs.firstIndex(where: { $0.id == current })
        else { return nil }
        let local = defaults.data(forKey: server.listeningDataKey)
            .flatMap { try? JSONDecoder().decode([QueueItem].self, from: $0) }
        var items: [QueueItem]
        if let local, local.flatMap(\.recording.songs).map(\.id) == songs.map(\.id) {
            items = local
        } else {
            items = Self.group(songs)
        }
        var movement = index
        while let first = items.first, movement >= first.recording.songs.count {
            movement -= first.recording.songs.count
            items.removeFirst()
        }
        guard let first = items.first else { return nil }
        let duration = Double(first.recording.songs[movement].duration ?? 0)
        let seconds = max(0, Double(saved.position ?? 0) / 1000)
        return Restored(items: items, movement: movement, position: duration > 0 ? min(seconds, duration) : seconds)
    }

    /// Another client can save a flat queue. Adjacent movements of one work and album form one item.
    private static func group(_ songs: [Song]) -> [QueueItem] {
        var groups: [[Song]] = []
        for song in songs {
            if let last = groups.last?.last, last.albumKey == song.albumKey,
                WorkIndex.workKey(last) == WorkIndex.workKey(song)
            {
                groups[groups.count - 1].append(song)
            } else {
                groups.append([song])
            }
        }
        return groups.compactMap { songs in
            guard var work = WorkIndex(songs: songs).composers.first?.works.first,
                var recording = work.recordings.first
            else { return nil }
            recording.songs = songs
            work.recordings = [recording]
            return QueueItem(work: work, recording: recording)
        }
    }

    /// A seek resets the position sample but keeps the time already heard in this movement.
    func begin(item: QueueItem, movement: Int, position: Double) {
        if listen?.item == item.id, listen?.movement == movement {
            listen?.position = position
        } else {
            listen = Listen(item: item.id, movement: movement, position: position)
        }
    }

    func hear(item: QueueItem, movement: Int, position: Double, duration: Double, enabled: Bool) {
        guard item.recording.songs.indices.contains(movement) else { return }
        if listen?.item != item.id || listen?.movement != movement {
            begin(item: item, movement: movement, position: 0)
        }
        guard var sample = listen else { return }
        let delta = max(0, position - sample.position)
        sample.position = position
        if enabled { sample.heard += delta }
        let threshold = min(duration / 2, 240)
        let submit = enabled && !sample.submitted && threshold > 0 && sample.heard >= threshold
        if submit { sample.submitted = true }
        listen = sample
        if submit {
            let id = item.recording.songs[movement].id
            enqueue { [server] in try await server.scrobble(id: id, time: sample.started) }
        }
    }

    func endListening() { listen = nil }

    func flush() async { await writes?.value }

    /// A response can fail after the server accepts it. Retrying a scrobble can count a play twice.
    private func enqueue(_ operation: @escaping @MainActor () async throws -> Void) {
        let previous = writes
        writes = Task { [weak self] in
            await previous?.value
            do {
                try await operation()
                self?.error = nil
            } catch {
                self?.error = "Could not save listening data to the server."
            }
        }
    }
}
