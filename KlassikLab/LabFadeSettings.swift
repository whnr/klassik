import KlassikEngine

/// The fade controls of the Lab. The defaults give the engine options of the app.
struct LabFadeSettings: Equatable {
    /// The seek modes as the Lab picker offers them. The silence length is a separate slider.
    enum Seek: String, CaseIterable, Identifiable {
        case today
        case silence
        case crossfade

        var id: String { rawValue }

        var title: String {
            switch self {
            case .today: "Today"
            case .silence: "Silence"
            case .crossfade: "Crossfade"
            }
        }
    }

    static let durationRange: ClosedRange<Double> = 0...300
    static let silenceRange: ClosedRange<Double> = 0...100
    static let defaultDuration = 100.0
    static let defaultSilence = 50.0

    var outCurve = FadeCurve.raisedCosine
    var inCurve = FadeCurve.raisedCosine
    var outMilliseconds = defaultDuration
    var inMilliseconds = defaultDuration
    var seek = Seek.today
    var silenceMilliseconds = defaultSilence

    /// The engine options. Each slider value is clamped to its range.
    var options: FadeOptions {
        FadeOptions(
            outCurve: outCurve, inCurve: inCurve, outSeconds: Self.seconds(outMilliseconds, in: Self.durationRange),
            inSeconds: Self.seconds(inMilliseconds, in: Self.durationRange), seek: seekMode)
    }

    private var seekMode: SeekMode {
        switch seek {
        case .today: .today
        case .silence: .silence(seconds: Self.seconds(silenceMilliseconds, in: Self.silenceRange))
        case .crossfade: .crossfade
        }
    }

    static func seconds(_ milliseconds: Double, in range: ClosedRange<Double>) -> Double {
        min(max(milliseconds, range.lowerBound), range.upperBound) / 1000
    }
}

extension FadeCurve {
    /// The name in the picker.
    var title: String {
        switch self {
        case .raisedCosine: "Raised cosine (today)"
        case .equalPower: "Equal power (sin/cos)"
        case .decibelLinear: "dB-linear to -60 dB"
        case .smootherstep: "Smootherstep"
        }
    }
}
