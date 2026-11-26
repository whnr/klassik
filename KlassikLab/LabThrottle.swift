import Foundation

/// A network fault for the bytes of one transfer. It is a pure schedule: the feeder asks how long to wait.
struct LabThrottle: Equatable, Sendable {
    enum Mode: String, CaseIterable, Identifiable, Sendable {
        case off
        case slow
        case dropouts

        var id: Self { self }

        var title: String {
            switch self {
            case .off: "Off"
            case .slow: "Slow link"
            case .dropouts: "Dropouts"
            }
        }
    }

    /// Below the bitrate of FLAC 24/96, above that of FLAC 16/44.1: only the hi-res cases starve.
    static let slowBytesPerSecond = 250_000.0
    /// Seconds of full speed, then seconds of silence. The stall exceeds the two seconds that the engine buffers.
    static let dropoutRun = 10.0
    static let dropoutStall = 4.0

    var mode: Mode = .off

    /// Seconds to wait before passing `bytes` on.
    /// - Parameters:
    ///   - elapsed: seconds since the transfer started.
    ///   - passed: bytes that the transfer passed on already.
    func delay(bytes: Int, elapsed: Double, passed: Int) -> Double {
        switch mode {
        case .off:
            return 0
        case .slow:
            return max(0, Double(passed + bytes) / Self.slowBytesPerSecond - elapsed)
        case .dropouts:
            let cycle = Self.dropoutRun + Self.dropoutStall
            let phase = elapsed.truncatingRemainder(dividingBy: cycle)
            return phase >= Self.dropoutRun ? cycle - phase : 0
        }
    }
}
