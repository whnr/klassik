import AVFoundation
import os

/// A gain ramp that runs on the samples. Stopping or starting a node inside a waveform jumps the output between
/// the wave's value and zero in one sample. A ramp over the set length turns that jump into small steps; its
/// curve is a `FadeCurve`, the raised cosine by default. The ramp changes the gain once for each frame, so its shape
/// does not depend on the render block size or on the main thread. Gapless joins on one node never use it, because
/// they do not stop the node.
struct FadeRamp: Sendable {
    private(set) var gain: Float = 1
    private var origin: Float = 1
    private var target: Float = 1
    private var length = 0
    private var done = 0
    private var curve = FadeCurve.raisedCosine
    /// True from the start of a ramp that waits for the first sound until `release`.
    private(set) var isWaiting = false

    /// True while the gain still moves, or sits off unity.
    var isIdle: Bool { !isWaiting && done >= length && gain == 1 }

    /// Starts a ramp over `frames` frames, from `from` or else from the gain that the ramp has now.
    /// A length of 0 jumps to the target. A ramp that falls follows the fall of the curve, a ramp that rises its rise.
    /// A ramp with `waiting` holds its first gain until `release`, so that a node which plays later than the ramp
    /// starts still fades in from its first sample.
    mutating func start(
        from: Float? = nil, to target: Float, frames: Int, curve: FadeCurve = .raisedCosine, waiting: Bool = false
    ) {
        isWaiting = waiting
        origin = from ?? gain
        self.target = target
        self.curve = curve
        length = max(frames, 0)
        done = 0
        gain = length == 0 ? target : origin
    }

    /// Lets a waiting ramp run, from the next frame on.
    mutating func release() { isWaiting = false }

    /// The gain of the next frame.
    mutating func next() -> Float {
        guard !isWaiting, done < length else { return gain }
        done += 1
        if done == length {
            gain = target
        } else {
            let progress = Double(done) / Double(length)
            let shape = target >= origin ? curve.rise(progress) : 1 - curve.fall(progress)
            gain = origin + (target - origin) * Float(shape)
        }
        return gain
    }

    /// Scales the samples in place, one gain for each frame.
    mutating func apply(to samples: UnsafeMutableBufferPointer<Float>) {
        guard !isIdle else { return }
        for index in samples.indices { samples[index] *= next() }
    }
}

/// A flag that one fade stage sets when its ramp starts, and that another stage waits for. A crossfade joins the two
/// graphs of the old and the new position with it, so that both ramps start at the first sounding frame of the new
/// position. Neither side waits on the lock: a busy lock only delays the flag by one frame.
final class FadeTrigger: @unchecked Sendable, Equatable {
    private let flag = OSAllocatedUnfairLock(initialState: false)

    static func == (lhs: FadeTrigger, rhs: FadeTrigger) -> Bool { lhs === rhs }

    /// True once the flag is set. A busy lock reads as not set yet.
    var isFired: Bool { flag.withLockIfAvailable { $0 } ?? false }

    /// Sets the flag. Returns false when the lock was busy, so the caller tries again.
    func fire() -> Bool { flag.withLockIfAvailable { $0 = true } != nil }

    /// Sets the flag and waits for a busy lock. Only for the main thread: the render thread never waits.
    func force() { flag.withLock { $0 = true } }
}

/// The hand-over between the main thread, which asks for a ramp, and the render thread, which runs it.
/// The render thread never waits: when the lock is busy, it keeps the gain it has and asks again next block.
final class FadeControl: @unchecked Sendable {
    struct Command: Equatable, Sendable {
        var from: Float?
        var target: Float
        var frames: Int
        var curve = FadeCurve.raisedCosine
        /// The ramp waits for the first frame with sound before it runs.
        var onSignal = false
        /// Set when the waiting ramp starts, for a ramp on another stage that waits with `after`.
        var fires: FadeTrigger?
        /// The ramp waits for this flag instead of a sound on its own stage.
        var after: FadeTrigger?
    }

    private struct State {
        var pending: Command?
        var last: Command?
    }

    private let state = OSAllocatedUnfairLock(initialState: State())
    /// Only the render thread touches the ramp.
    private var ramp = FadeRamp()
    private var fires: FadeTrigger?
    private var after: FadeTrigger?

    /// The newest request, for tests and for the engine's own checks.
    var last: Command? { state.withLock { $0.last } }

    func ramp(
        from: Float? = nil, to target: Float, frames: Int, curve: FadeCurve = .raisedCosine, onSignal: Bool = false,
        fires: FadeTrigger? = nil, after: FadeTrigger? = nil
    ) {
        let command = Command(
            from: from, target: target, frames: frames, curve: curve, onSignal: onSignal || after != nil,
            fires: fires, after: after)
        state.withLock {
            $0.pending = command
            $0.last = command
        }
    }

    /// True when any channel of the frame holds a sample other than 0.
    private static func hasSound(_ buffers: UnsafeMutableAudioBufferListPointer, at frame: Int) -> Bool {
        for buffer in buffers {
            guard let data = buffer.mData?.assumingMemoryBound(to: Float.self) else { continue }
            let channels = Int(buffer.mNumberChannels)
            for channel in 0..<channels where data[frame * channels + channel] != 0 { return true }
        }
        return false
    }

    /// Runs on the render thread. Reads a new request first, then scales the samples.
    func process(_ list: UnsafeMutablePointer<AudioBufferList>, frames: Int) {
        if let command = state.withLockIfAvailable({ state -> Command? in
            defer { state.pending = nil }
            return state.pending
        }) ?? nil {
            ramp.start(
                from: command.from, to: command.target, frames: command.frames, curve: command.curve,
                waiting: command.onSignal)
            fires = command.fires
            after = command.after
        }
        guard !ramp.isIdle else { return }
        let buffers = UnsafeMutableAudioBufferListPointer(list)
        for frame in 0..<frames {
            if ramp.isWaiting {
                if let after {
                    if after.isFired { ramp.release() }
                } else if Self.hasSound(buffers, at: frame), fires?.fire() ?? true {
                    ramp.release()
                }
            }
            let gain = ramp.next()
            for buffer in buffers {
                guard let data = buffer.mData?.assumingMemoryBound(to: Float.self) else { continue }
                let channels = Int(buffer.mNumberChannels)
                for channel in 0..<channels { data[frame * channels + channel] *= gain }
            }
        }
    }
}

/// An effect unit that applies a `FadeControl` to the audio that passes through it.
final class FadeAudioUnit: AUAudioUnit {
    let control = FadeControl()
    private var inputBus: AUAudioUnitBus!
    private var outputBus: AUAudioUnitBus!
    private var inputList: AUAudioUnitBusArray!
    private var outputList: AUAudioUnitBusArray!

    static let description = AudioComponentDescription(
        componentType: kAudioUnitType_Effect, componentSubType: 0x6b6c_6664,
        componentManufacturer: 0x6b6c_6173, componentFlags: 0, componentFlagsMask: 0)

    /// Registers the unit once for this process.
    static let registered: Void = {
        AUAudioUnit.registerSubclass(
            FadeAudioUnit.self, as: description, name: "Klassik: Fade", version: 1)
    }()

    override init(componentDescription: AudioComponentDescription, options: AudioComponentInstantiationOptions = [])
        throws
    {
        try super.init(componentDescription: componentDescription, options: options)
        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2)
        inputBus = try AUAudioUnitBus(format: format!)
        outputBus = try AUAudioUnitBus(format: format!)
        inputList = AUAudioUnitBusArray(audioUnit: self, busType: .input, busses: [inputBus])
        outputList = AUAudioUnitBusArray(audioUnit: self, busType: .output, busses: [outputBus])
    }

    override var inputBusses: AUAudioUnitBusArray { inputList }
    override var outputBusses: AUAudioUnitBusArray { outputList }
    override var canProcessInPlace: Bool { true }

    override var internalRenderBlock: AUInternalRenderBlock {
        let control = control
        return { flags, timestamp, frames, _, output, _, pull in
            guard let pull else { return kAudioUnitErr_NoConnection }
            let status = pull(flags, timestamp, frames, 0, output)
            guard status == noErr else { return status }
            control.process(output, frames: Int(frames))
            return noErr
        }
    }

    /// A new fade stage for a signal path, and the control that drives it. Nil when the system refuses the unit.
    static func make() -> (stage: AVAudioUnitEffect, control: FadeControl)? {
        _ = registered
        let stage = AVAudioUnitEffect(audioComponentDescription: description)
        guard let control = stage.withAUAudioUnit({ ($0 as? FadeAudioUnit)?.control }) else { return nil }
        return (stage, control)
    }
}
