import AVFoundation
import Observation

/// Plays tracks back to back with one of two players, so that a listener can compare the joins.
@MainActor @Observable
final class GaplessTestPlayer {
    enum Kind: String, CaseIterable, Identifiable {
        case queuePlayer = "AVQueuePlayer"
        case audioEngine = "AVAudioEngine"
        var id: Self { self }
    }

    /// What the engine found in a downloaded track.
    struct Analysis: Equatable {
        var header: MP3GaplessInfo?
        var decodedFrames: Int64
        var playable: Range<Int64>

        var summary: String {
            guard let header else { return "No gapless header · \(decodedFrames) frames" }
            let trimmedByIOS = decodedFrames == Int64(header.validSamples)
            return "Delay \(header.encoderDelay), padding \(header.padding) · iOS decodes \(decodedFrames) frames, "
                + (trimmedByIOS ? "trimmed by iOS" : "Klassik plays \(playable.lowerBound)..<\(playable.upperBound)")
        }
    }

    private(set) var status = "Stopped"
    private(set) var analysis: [Song.ID: Analysis] = [:]

    private var queuePlayer: AVQueuePlayer?
    private var engine: AVAudioEngine?
    private var task: Task<Void, Never>?

    /// Plays `songs` from `index` to the end. `lastSeconds` starts the first track that long before its end.
    func play(_ songs: [Song], from index: Int, with kind: Kind, client: SubsonicClient, lastSeconds: Double?) {
        stop()
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            status = error.localizedDescription
            return
        }
        let songs = Array(songs[index...])
        switch kind {
        case .queuePlayer: playQueue(songs, client: client, lastSeconds: lastSeconds)
        case .audioEngine: task = Task { await playEngine(songs, client: client, lastSeconds: lastSeconds) }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        queuePlayer?.pause()
        queuePlayer = nil
        engine?.stop()
        engine = nil
        status = "Stopped"
    }

    private func playQueue(_ songs: [Song], client: SubsonicClient, lastSeconds: Double?) {
        let player = AVQueuePlayer(items: songs.map { AVPlayerItem(url: client.streamURL(songID: $0.id)) })
        if let lastSeconds, let duration = songs.first?.duration {
            player.seek(to: CMTime(seconds: max(0, Double(duration) - lastSeconds), preferredTimescale: 600))
        }
        player.play()
        queuePlayer = player
        status = "Streaming \(songs.count) tracks"
    }

    /// Downloads each track, then schedules only its playable frames. The next download runs while a track plays.
    private func playEngine(_ songs: [Song], client: SubsonicClient, lastSeconds: Double?) async {
        let engine = AVAudioEngine()
        let node = AVAudioPlayerNode()
        engine.attach(node)
        self.engine = engine
        var format: AVAudioFormat?
        do {
            for (number, song) in songs.enumerated() {
                status = "Downloading track \(number + 1) of \(songs.count)"
                let (temporary, _) = try await URLSession.shared.download(from: client.streamURL(songID: song.id))
                try Task.checkCancellation()
                let local = URL.cachesDirectory.appending(path: "gapless-\(number).\(song.suffix ?? "mp3")")
                try? FileManager.default.removeItem(at: local)
                try FileManager.default.moveItem(at: temporary, to: local)

                let file = try AVAudioFile(forReading: local)
                let header = try MP3GaplessInfo.parse(Data(contentsOf: local, options: .mappedIfSafe))
                var range = header?.playableRange(decodedLength: file.length) ?? 0..<file.length
                analysis[song.id] = Analysis(header: header, decodedFrames: file.length, playable: range)
                if number == 0, let lastSeconds {
                    let tail = Int64(lastSeconds * file.processingFormat.sampleRate)
                    range = max(range.lowerBound, range.upperBound - tail)..<range.upperBound
                }

                if format == nil {
                    format = file.processingFormat
                    engine.connect(node, to: engine.mainMixerNode, format: file.processingFormat)
                    try engine.start()
                    node.play()
                } else if file.processingFormat != format {
                    status = "Track \(number + 1) has a different audio format. Stopped scheduling."
                    return
                }
                // Without a completion handler, Swift picks the async variant, which waits for the end of playback.
                node.scheduleSegment(
                    file, startingFrame: range.lowerBound, frameCount: AVAudioFrameCount(range.count), at: nil,
                    completionHandler: nil)
                status = "Playing · \(number + 1) of \(songs.count) tracks scheduled"
            }
        } catch {
            if !Task.isCancelled { status = error.localizedDescription }
        }
    }
}
