import Foundation
import Testing

@testable import KlassikEngine
@testable import KlassikLab

struct LabRouteTests {
    private func formats(
        mixer: Double, hardware: Double, mixerChannels: Int = 2, hardwareChannels: Int = 2
    ) -> PlaybackOutputFormats {
        PlaybackOutputFormats(
            mixerRate: mixer, mixerChannels: mixerChannels, hardwareRate: hardware, hardwareChannels: hardwareChannels)
    }

    private func port(_ type: String, name: String) -> LabRoute.Port {
        LabRoute.Port(
            type: type, name: name, uid: "uid-1", channels: ["Left", "Right"], dataSource: nil, dataSources: [])
    }

    @Test func aMatchingGraphReportsNoConversion() {
        let outputs = formats(mixer: 96_000, hardware: 96_000)
        let graph = LabRoute.Graph(sourceRate: 96_000, sourceChannels: 2, outputs: outputs)
        let lines = LabRoute.conversions(graph: graph, sessionRate: 96_000)
        #expect(lines == ["none: the file rate and channels reach the output"])
    }

    @Test func aHardwareRateBelowTheFileNamesTheOutputNode() {
        let outputs = formats(mixer: 96_000, hardware: 48_000)
        let graph = LabRoute.Graph(sourceRate: 96_000, sourceChannels: 2, outputs: outputs)
        let lines = LabRoute.conversions(graph: graph, sessionRate: 48_000)
        #expect(lines == ["the output node converts 96 kHz to 48 kHz"])
    }

    @Test func aMixerRateChangeAndAChannelChangeNameTheMixer() {
        let graph = LabRoute.Graph(
            sourceRate: 44_100, sourceChannels: 1, outputs: formats(mixer: 48_000, hardware: 48_000))
        let lines = LabRoute.conversions(graph: graph, sessionRate: 48_000)
        #expect(lines == ["the mixer converts 44.1 kHz to 48 kHz", "the mixer changes 1 channels to 2"])
    }

    @Test func aSessionRateThatDiffersFromTheHardwareIsShown() {
        let outputs = formats(mixer: 48_000, hardware: 48_000)
        let graph = LabRoute.Graph(sourceRate: 48_000, sourceChannels: 2, outputs: outputs)
        let lines = LabRoute.conversions(graph: graph, sessionRate: 44_100)
        #expect(lines == ["the session reports 44.1 kHz, the output node 48 kHz"])
    }

    @Test func withoutAnEngineTheSessionRateAloneDecides() {
        let graph = LabRoute.Graph(sourceRate: 96_000, sourceChannels: 2, outputs: nil)
        #expect(LabRoute.conversions(graph: graph, sessionRate: 48_000) == ["iOS converts 96 kHz to 48 kHz"])
        let none = LabRoute.Graph(sourceRate: 0, sourceChannels: 0, outputs: nil)
        #expect(LabRoute.conversions(graph: none, sessionRate: 48_000) == ["no track loaded"])
    }

    /// A seek drops the graph lines for a moment. The box keeps the tallest height that it had, wrapped lines
    /// included.
    @Test func theRoutingBoxKeepsItsTallestHeight() {
        #expect(LabRoute.heldHeight(current: 0, measured: 180) == 180)
        #expect(LabRoute.heldHeight(current: 180, measured: 120) == 180)
        #expect(LabRoute.heldHeight(current: 180, measured: 220) == 220)
    }

    @Test func aBluetoothOutputSaysThatIOSExposesNoCodec() {
        var route = LabRoute()
        route.ports = [port("BluetoothA2DPOutput", name: "Headphones")]
        route.sampleRate = 48_000
        route.outputLatency = 0.12
        let graph = LabRoute.Graph(sourceRate: 0, sourceChannels: 0, outputs: nil)
        let text = LabRoute.lines(route: route, graph: graph, change: nil).joined(separator: "\n")
        #expect(route.hasBluetooth)
        #expect(text.contains("Bluetooth codec not exposed by iOS"))
        #expect(text.contains("Output 1: BluetoothA2DPOutput, Headphones, uid uid-1, 2 channels (Left Right)"))
        #expect(text.contains("Output latency 120.0 ms"))
    }

    @Test func aSpeakerOutputShowsNoBluetoothLine() {
        var route = LabRoute()
        route.ports = [port("Speaker", name: "Speaker")]
        let graph = LabRoute.Graph(sourceRate: 0, sourceChannels: 0, outputs: nil)
        let text = LabRoute.lines(route: route, graph: graph, change: "new device available").joined(separator: "\n")
        #expect(!route.hasBluetooth)
        #expect(!text.contains("Bluetooth"))
        #expect(text.contains("Last route change: new device available"))
    }

    @Test func theQualityLineNamesTheOutputPort() {
        let line = LabPlayer.qualityLine(
            source: "FLAC 24-bit 96 kHz", engineRate: 96_000, engineChannels: 2, outputRate: 48_000,
            output: "Headphones (BluetoothA2DPOutput)", join: "gapless")
        let expected =
            "Source FLAC 24-bit 96 kHz, engine 96 kHz stereo, "
            + "iOS output 48 kHz on Headphones (BluetoothA2DPOutput), iOS converts, join gapless"
        #expect(line == expected)
    }

    @Test func theRouteChangeReasonsHaveWords() {
        #expect(LabRoute.reason(1) == "new device available")
        #expect(LabRoute.reason(2) == "old device unavailable")
        #expect(LabRoute.reason(nil) == "unknown reason")
    }
}
