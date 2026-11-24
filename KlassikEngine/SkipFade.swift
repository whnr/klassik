import AVFoundation

/// The short gain ramp that keeps a skip from clicking. Stopping or starting a node inside a waveform jumps the
/// output from the wave's value to zero, or back, in one sample. A raised-cosine ramp over a few milliseconds
/// turns that jump into steps that stay below `maximumStep` of the full level. Gapless joins on one node never
/// use it, because they do not stop the node.
enum SkipFade {
    /// The ramp length. Short enough that a skip stays instant, long enough for the steps to stay small.
    static let seconds = 0.03
    /// The time between two gain steps.
    static let interval = Duration.milliseconds(2)
    static let steps = 15
    /// The largest change of gain between two steps, as a fraction of the full level.
    static let maximumStep: Float = 0.11

    /// The gain of each step, ending at the target: 0 for a fade-out, 1 for a fade-in.
    static func gains(rising: Bool) -> [Float] {
        (1...steps).map { step in
            let progress = Double(step) / Double(steps)
            let rise = Float(0.5 - 0.5 * cos(Double.pi * progress))
            return rising ? rise : 1 - rise
        }
    }

    /// Applies the ramp step by step. It stops early, without a final step, when its task is cancelled.
    @MainActor
    static func run(rising: Bool, apply: (Float) -> Void) async {
        for gain in gains(rising: rising) {
            guard !Task.isCancelled else { return }
            apply(gain)
            try? await Task.sleep(for: interval)
        }
    }
}
