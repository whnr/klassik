import KlassikEngine

extension GaplessEngine {
    /// The engine of the app. It plays with `FadeOptions.spec`, the same fade code and values as the Playback Lab.
    /// A crossfade seek waits for bytes, so it counts only tracks on the device (music cache or download) as ready.
    @MainActor static func forApp(tracks: TrackStore) -> GaplessEngine {
        let engine = GaplessEngine(failureMapper: AppFailureMapper())
        engine.fadeOptions = .spec
        engine.isOnDisk = { [weak tracks] track in tracks?.offline.contains(track.id) ?? false }
        return engine
    }
}
