#if DEBUG
    import Foundation
    import KlassikEngine

    /// The UI walk takes a slow connection with `-slowMusic`: each track arrives far below its bitrate, so the
    /// player shows the slow-connection line (ADR 0060).
    enum SlowMusic {
        static let argument = "-slowMusic"
        /// Bytes for each delivery, four times a second: about 40 kbit/s.
        static let chunk = 1_250
        static let interval = Duration.milliseconds(250)

        static var isOn: Bool { ProcessInfo.processInfo.arguments.contains(argument) }

        /// Loads the whole track from the server first, then hands it to the transfer slowly.
        @MainActor static func transport(_ song: Song, _ client: any ServerPort, _ transfer: TrackTransfer) {
            let url = client.streamURL(songID: song.id)
            Task.detached {
                guard let loaded = try? await URLSession.shared.data(from: url),
                    let http = loaded.1 as? HTTPURLResponse, http.statusCode == 200
                else { return transfer.finish(.truncated) }
                let data = loaded.0
                transfer.begin(length: Int64(data.count), validator: TrackTransfer.validator(of: http))
                var offset = 0
                while offset < data.count, !Task.isCancelled {
                    let end = min(offset + Self.chunk, data.count)
                    let bytes = data.subdata(in: offset..<end)
                    // A blocked write waits on its thread, never on the cooperative executor.
                    await withCheckedContinuation { continuation in
                        DispatchQueue.global().async {
                            transfer.append(bytes)
                            continuation.resume()
                        }
                    }
                    offset = end
                    try? await Task.sleep(for: Self.interval)
                }
                transfer.finish(nil)
            }
        }
    }
#endif
