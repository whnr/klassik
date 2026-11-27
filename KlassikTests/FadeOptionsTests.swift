import AVFoundation
import Testing

@testable import KlassikEngine

/// The four curves, the separate lengths and the seek modes of the fade options.
struct FadeOptionsTests {
    private static let steps = 1000

    @Test(arguments: FadeCurve.allCases) func aFadeInStartsAtZeroAndEndsAtOne(curve: FadeCurve) {
        #expect(curve.rise(0) == 0)
        #expect(curve.rise(1) == 1)
    }

    @Test(arguments: FadeCurve.allCases) func aFadeOutStartsAtOneAndEndsAtZero(curve: FadeCurve) {
        #expect(curve.fall(0) == 1)
        #expect(curve.fall(1) == 0)
    }

    @Test(arguments: FadeCurve.allCases) func theCurvesNeverFallOnTheWayUpOrRiseOnTheWayDown(curve: FadeCurve) {
        let levels = (0...Self.steps).map { curve.rise(Double($0) / Double(Self.steps)) }
        #expect(zip(levels, levels.dropFirst()).allSatisfy { $1 >= $0 })
        let falling = (0...Self.steps).map { curve.fall(Double($0) / Double(Self.steps)) }
        #expect(zip(falling, falling.dropFirst()).allSatisfy { $1 <= $0 })
        #expect(levels.allSatisfy { 0...1 ~= $0 })
    }

    @Test func theRaisedCosineIsHalfACosineWave() {
        for step in 0...10 {
            let progress = Double(step) / 10
            #expect(abs(FadeCurve.raisedCosine.rise(progress) - (0.5 - 0.5 * cos(Double.pi * progress))) < 1e-12)
        }
        #expect(abs(FadeCurve.raisedCosine.rise(0.5) - 0.5) < 1e-12)
    }

    @Test func theEqualPowerCurvesAddUpToTheSamePowerAtEveryPoint() {
        for step in 0...Self.steps {
            let progress = Double(step) / Double(Self.steps)
            let rise = FadeCurve.equalPower.rise(progress)
            let fall = FadeCurve.equalPower.fall(progress)
            #expect(abs(rise * rise + fall * fall - 1) < 1e-12)
            #expect(abs(rise - sin(Double.pi / 2 * progress)) < 1e-12)
            #expect(abs(fall - cos(Double.pi / 2 * progress)) < 1e-12)
        }
    }

    @Test func theDecibelCurveFallsEvenlyInDecibelsToTheFloor() {
        let curve = FadeCurve.decibelLinear
        for step in 1..<10 {
            let progress = Double(step) / 10
            let decibels = 20 * log10(curve.fall(progress))
            #expect(abs(decibels - FadeCurve.floorDecibels * progress) < 1e-9)
        }
        // The cut: just before the end the level is the floor, at the end it is silence.
        #expect(abs(20 * log10(curve.fall(0.999_999)) - FadeCurve.floorDecibels) < 1e-3)
        #expect(curve.fall(1) == 0)
        #expect(abs(20 * log10(curve.rise(0.000_001)) - FadeCurve.floorDecibels) < 1e-3)
    }

    @Test func theSpecIsSmootherstepOutAndInForOneHundredMillisecondsWithACrossfade() {
        #expect(FadeOptions.spec.outCurve == .smootherstep)
        #expect(FadeOptions.spec.inCurve == .smootherstep)
        #expect(FadeOptions.spec.outSeconds == 0.1)
        #expect(FadeOptions.spec.inSeconds == 0.1)
        #expect(FadeOptions.spec.seek == .crossfade)
    }

    @Test func theSmootherstepIsTheFifthOrderPolynomialWithFlatEnds() {
        let curve = FadeCurve.smootherstep
        #expect(abs(curve.rise(0.5) - 0.5) < 1e-12)
        #expect(abs(curve.rise(0.25) - (6 * pow(0.25, 5) - 15 * pow(0.25, 4) + 10 * pow(0.25, 3))) < 1e-12)
        #expect(curve.rise(0.001) < 1e-6)
        #expect(curve.fall(0.001) > 1 - 1e-6)
    }

    @Test(arguments: FadeCurve.allCases) func aRampFollowsItsCurveFromEndToEnd(curve: FadeCurve) {
        let length = 480
        var out = FadeRamp()
        out.start(from: 1, to: 0, frames: length, curve: curve)
        var up = FadeRamp()
        up.start(from: 0, to: 1, frames: length, curve: curve)
        var outGains: [Float] = []
        var upGains: [Float] = []
        for _ in 0..<length {
            outGains.append(out.next())
            upGains.append(up.next())
        }
        for index in 0..<(length - 1) {
            let progress = Double(index + 1) / Double(length)
            #expect(abs(Double(outGains[index]) - curve.fall(progress)) < 1e-5)
            #expect(abs(Double(upGains[index]) - curve.rise(progress)) < 1e-5)
        }
        #expect(outGains[length - 1] == 0)
        #expect(upGains[length - 1] == 1)
        #expect(zip(outGains, outGains.dropFirst()).allSatisfy { $1 <= $0 })
        #expect(zip(upGains, upGains.dropFirst()).allSatisfy { $1 >= $0 })
    }

    @MainActor @Test func theDefaultsAreTheSoundOfTheApp() {
        let options = FadeOptions()
        #expect(options.outCurve == .raisedCosine)
        #expect(options.inCurve == .raisedCosine)
        #expect(options.outSeconds == 0.1)
        #expect(options.inSeconds == 0.1)
        #expect(options.seek == .today)
        #expect(GaplessEngine().fadeOptions == options)
    }

    @MainActor @Test func theOutAndInLengthsAreSeparate() {
        let options = FadeOptions(outSeconds: 0.04, inSeconds: 0.25)
        #expect(options.outSeconds == 0.04)
        #expect(options.inSeconds == 0.25)
        #expect(GaplessEngine(fadeSeconds: 0.2).fadeOptions == FadeOptions(outSeconds: 0.2, inSeconds: 0.2))
    }

    @Test func onlyTheSilenceModeWaitsAndItWaitsForTheStopAndTheGap() {
        let stop = 0.13
        #expect(FadeOptions(seek: .today).newSoundDelay(stopWait: stop) == 0)
        #expect(FadeOptions(seek: .crossfade).newSoundDelay(stopWait: stop) == 0)
        let silence = FadeOptions(seek: .silence(seconds: 0.05))
        // The fade-out takes 100 ms and the stop margin 30 ms: only the fade-out and the gap are silence.
        #expect(abs(silence.newSoundDelay(stopWait: stop) - 0.15) < 1e-12)
        #expect(abs(FadeOptions(seek: .silence(seconds: 0)).newSoundDelay(stopWait: stop) - 0.1) < 1e-12)
        #expect(abs(FadeOptions(seek: .silence(seconds: -1)).newSoundDelay(stopWait: stop) - 0.1) < 1e-12)
        // A silent graph has nothing to fade out, so nothing waits.
        #expect(silence.newSoundDelay(stopWait: 0) == 0)
    }

    /// The silence the user hears is the set gap. The fade-out is 150 ms and the stop margin 30 ms.
    @Test func theSilenceModeWaitsForTheFadeOutAndTheSetGapOnly() {
        let options = FadeOptions(outSeconds: 0.15, inSeconds: 0.15, seek: .silence(seconds: 0.1))
        let stopWait = options.outSeconds + FadeOptions.stopMargin
        #expect(abs(options.newSoundDelay(stopWait: stopWait) - 0.25) < 1e-12)
    }
}
