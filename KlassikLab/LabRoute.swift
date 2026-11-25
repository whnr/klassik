import AVFoundation
import KlassikEngine

/// What iOS reports about the output route at one moment. The Lab shows all of it, so a tester can tell a speaker
/// from a Bluetooth headset and see where the system converts.
struct LabRoute: Equatable, Sendable {
    struct Port: Equatable, Sendable {
        var type: String
        var name: String
        var uid: String
        /// The channel names, or "1", "2" for a port that names none.
        var channels: [String]
        var dataSource: String?
        var dataSources: [String]
    }

    var ports: [Port] = []
    var sampleRate = 0.0
    var preferredSampleRate = 0.0
    var ioBufferDuration = 0.0
    var preferredIOBufferDuration = 0.0
    var outputLatency = 0.0
    var outputChannels = 0
    var maximumOutputChannels = 0

    /// The port types of a Bluetooth output. iOS names no codec for any of them.
    private static let bluetooth: Set<String> = [
        AVAudioSession.Port.bluetoothA2DP.rawValue, AVAudioSession.Port.bluetoothLE.rawValue,
        AVAudioSession.Port.bluetoothHFP.rawValue,
    ]

    var hasBluetooth: Bool { ports.contains { Self.bluetooth.contains($0.type) } }

    /// The first output in a short form for the quality line, such as "AirPods Pro (BluetoothA2DPOutput)".
    var outputName: String {
        guard let port = ports.first else { return "no output" }
        return "\(port.name) (\(port.type))"
    }

    static func read(_ session: AVAudioSession = .sharedInstance()) -> LabRoute {
        let ports = session.currentRoute.outputs.map { port in
            let channels = (port.channels ?? []).map { channel in
                channel.channelName.isEmpty ? String(channel.channelNumber) : channel.channelName
            }
            return Port(
                type: port.portType.rawValue, name: port.portName, uid: port.uid, channels: channels,
                dataSource: port.selectedDataSource?.dataSourceName,
                dataSources: (port.dataSources ?? []).map(\.dataSourceName))
        }
        return LabRoute(
            ports: ports, sampleRate: session.sampleRate, preferredSampleRate: session.preferredSampleRate,
            ioBufferDuration: session.ioBufferDuration, preferredIOBufferDuration: session.preferredIOBufferDuration,
            outputLatency: session.outputLatency, outputChannels: session.outputNumberOfChannels,
            maximumOutputChannels: session.maximumOutputNumberOfChannels)
    }

    /// The reason of a route change notification, in words.
    nonisolated static func reason(_ raw: UInt?) -> String {
        guard let raw, let reason = AVAudioSession.RouteChangeReason(rawValue: raw) else { return "unknown reason" }
        switch reason {
        case .newDeviceAvailable: return "new device available"
        case .oldDeviceUnavailable: return "old device unavailable"
        case .categoryChange: return "category change"
        case .override: return "override"
        case .wakeFromSleep: return "wake from sleep"
        case .noSuitableRouteForCategory: return "no suitable route for the category"
        case .routeConfigurationChange: return "route configuration change"
        case .unknown: return "unknown reason"
        @unknown default: return "unknown reason"
        }
    }

    /// The engine side of the picture: the file, the mixer's output and the hardware.
    struct Graph: Equatable, Sendable {
        var sourceRate: Double
        var sourceChannels: Int
        var outputs: PlaybackOutputFormats?
    }

    /// Where a conversion happens, from the formats alone. The app converts nothing. Every line names the system
    /// stage that does.
    nonisolated static func conversions(graph: Graph, sessionRate: Double) -> [String] {
        guard graph.sourceRate > 0 else { return ["no track loaded"] }
        var lines: [String] = []
        if let outputs = graph.outputs {
            if outputs.mixerRate != graph.sourceRate {
                lines.append(
                    "the mixer converts \(kilohertz(graph.sourceRate)) kHz to \(kilohertz(outputs.mixerRate)) kHz")
            }
            if outputs.mixerChannels != graph.sourceChannels {
                lines.append("the mixer changes \(graph.sourceChannels) channels to \(outputs.mixerChannels)")
            }
            if outputs.hardwareRate != outputs.mixerRate {
                let from = kilohertz(outputs.mixerRate)
                lines.append("the output node converts \(from) kHz to \(kilohertz(outputs.hardwareRate)) kHz")
            }
            if outputs.hardwareChannels != outputs.mixerChannels {
                lines.append(
                    "the output node changes \(outputs.mixerChannels) channels to \(outputs.hardwareChannels)")
            }
            if sessionRate > 0, outputs.hardwareRate != sessionRate {
                let node = kilohertz(outputs.hardwareRate)
                lines.append("the session reports \(kilohertz(sessionRate)) kHz, the output node \(node) kHz")
            }
        } else if sessionRate > 0, sessionRate != graph.sourceRate {
            lines.append("iOS converts \(kilohertz(graph.sourceRate)) kHz to \(kilohertz(sessionRate)) kHz")
        }
        return lines.isEmpty ? ["none: the file rate and channels reach the output"] : lines
    }

    /// The lines of the routing section, one fact each.
    nonisolated static func lines(route: LabRoute, graph: Graph, change: String?) -> [String] {
        var lines: [String] = []
        if route.ports.isEmpty { lines.append("Output: none") }
        for (index, port) in route.ports.enumerated() {
            let channels = port.channels.isEmpty ? "channels not listed" : port.channels.joined(separator: " ")
            let source = port.dataSource ?? "no data source"
            let others = port.dataSources.isEmpty ? "" : ", data sources \(port.dataSources.joined(separator: " "))"
            lines.append(
                "Output \(index + 1): \(port.type), \(port.name), uid \(port.uid), \(port.channels.count) channels"
                    + " (\(channels)), data source \(source)\(others)")
        }
        lines.append(
            "Session rate \(kilohertz(route.sampleRate)) kHz, preferred \(kilohertz(route.preferredSampleRate)) kHz")
        let buffer = milliseconds(route.ioBufferDuration)
        lines.append("IO buffer \(buffer), preferred \(milliseconds(route.preferredIOBufferDuration))")
        lines.append(
            "Output latency \(milliseconds(route.outputLatency)), output channels \(route.outputChannels)"
                + " of \(route.maximumOutputChannels)")
        if graph.sourceRate > 0 {
            let source = "\(kilohertz(graph.sourceRate)) kHz \(graph.sourceChannels) channels"
            lines.append("Source \(source)")
        }
        if let outputs = graph.outputs {
            lines.append(
                "Mixer to output node \(kilohertz(outputs.mixerRate)) kHz \(outputs.mixerChannels) channels,"
                    + " hardware \(kilohertz(outputs.hardwareRate)) kHz \(outputs.hardwareChannels) channels")
        }
        lines.append("Conversion: " + conversions(graph: graph, sessionRate: route.sampleRate).joined(separator: ", "))
        if route.hasBluetooth {
            lines.append(
                "Bluetooth codec not exposed by iOS. Known: port \(route.ports.first?.type ?? "?"),"
                    + " rate \(kilohertz(route.sampleRate)) kHz, latency \(milliseconds(route.outputLatency))")
        }
        if let change { lines.append("Last route change: \(change)") }
        return lines
    }

    nonisolated static func kilohertz(_ hertz: Double) -> String {
        hertz > 0 ? LabCase.kilohertz(Int(hertz.rounded())) : "unknown"
    }

    nonisolated static func milliseconds(_ seconds: Double) -> String {
        String(format: "%.1f ms", seconds * 1000)
    }
}
