import AVFoundation
import os

/// A gain ramp that runs on the samples. Stopping or starting a node inside a waveform jumps the output between
/// the wave's value and zero in one sample. A raised-cosine ramp over the set length turns that jump into small
/// steps. The ramp changes the gain once for each frame, so its shape does not depend on the render block size or
/// on the main thread. Gapless joins on one node never use it, because they do not stop the node.
struct FadeRamp: Sendable {
    private(set) var gain: Float = 1
    private var origin: Float = 1
    private var target: Float = 1
    private var length = 0
    private var done = 0

    /// True while the gain still moves, or sits off unity.
    var isIdle: Bool { done >= length && gain == 1 }

    /// Starts a ramp over `frames` frames, from `from` or else from the gain that the ramp has now.
    /// A length of 0 jumps to the target.
    mutating func start(from: Float? = nil, to target: Float, frames: Int) {
        origin = from ?? gain
        self.target = target
        length = max(frames, 0)
        done = 0
        gain = length == 0 ? target : origin
    }

    /// The gain of the next frame.
    mutating func next() -> Float {
        guard done < length else { return gain }
        done += 1
        if done == length {
            gain = target
        } else {
            let progress = Double(done) / Double(length)
            gain = origin + (target - origin) * Float(0.5 - 0.5 * cos(Double.pi * progress))
        }
        return gain
    }

    /// Scales the samples in place, one gain for each frame.
    mutating func apply(to samples: UnsafeMutableBufferPointer<Float>) {
        guard !isIdle else { return }
        for index in samples.indices { samples[index] *= next() }
    }
}

/// The hand-over between the main thread, which asks for a ramp, and the render thread, which runs it.
/// The render thread never waits: when the lock is busy, it keeps the gain it has and asks again next block.
final class FadeControl: @unchecked Sendable {
    struct Command: Equatable, Sendable {
        var from: Float?
        var target: Float
        var frames: Int
    }

    private struct State {
        var pending: Command?
        var last: Command?
    }

    private let state = OSAllocatedUnfairLock(initialState: State())
    /// Only the render thread touches the ramp.
    private var ramp = FadeRamp()

    /// The newest request, for tests and for the engine's own checks.
    var last: Command? { state.withLock { $0.last } }

    func ramp(from: Float? = nil, to target: Float, frames: Int) {
        let command = Command(from: from, target: target, frames: frames)
        state.withLock {
            $0.pending = command
            $0.last = command
        }
    }

    /// Runs on the render thread. Reads a new request first, then scales the samples.
    func process(_ list: UnsafeMutablePointer<AudioBufferList>, frames: Int) {
        if let command = state.withLockIfAvailable({ state -> Command? in
            defer { state.pending = nil }
            return state.pending
        }) ?? nil {
            ramp.start(from: command.from, to: command.target, frames: command.frames)
        }
        guard !ramp.isIdle else { return }
        let buffers = UnsafeMutableAudioBufferListPointer(list)
        for frame in 0..<frames {
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
        guard let unit = stage.auAudioUnit as? FadeAudioUnit else { return nil }
        return (stage, unit.control)
    }
}
