import KlassikEngine
import SwiftUI

/// The whole Lab screen: case, quality line, transport, ReplayGain, network.
struct LabPlayerView: View {
    let model: LabModel
    @Bindable var player: LabPlayer
    let cases: [LabCase]

    @State private var scrubbing: Double?

    var body: some View {
        NavigationStack {
            Form {
                Section("Test case") {
                    Picker("Case", selection: $player.selected) {
                        ForEach(cases) { item in
                            Text(item.title).tag(Optional(item))
                        }
                    }
                    .pickerStyle(.menu)
                }
                // Always visible: this line is what the tester reads against the headphones.
                Section("Quality") {
                    Text(player.qualityLine)
                        .font(.footnote.monospaced())
                        .textSelection(.enabled)
                    if let reason = player.selected?.unsupportedReason {
                        Text(reason).foregroundStyle(.orange)
                    }
                    if let note = player.selected?.gapNote {
                        Text(note).font(.footnote).foregroundStyle(.secondary)
                    }
                    if let note = player.selected?.listenNote {
                        Text(note).font(.footnote).foregroundStyle(.secondary)
                    }
                }
                // Everything iOS reports about the output, updated on each route change.
                Section("Routing and output") {
                    Text(player.routeLines.joined(separator: "\n"))
                        .font(.footnote.monospaced())
                        .textSelection(.enabled)
                }
                Section("Playback") {
                    HStack {
                        Button {
                            player.togglePlay()
                        } label: {
                            Label(
                                player.isPlaying ? "Pause" : "Play",
                                systemImage: player.isPlaying ? "pause.fill" : "play.fill")
                        }
                        .disabled(!player.canPlay)
                        Spacer()
                        Text("Movement \(player.movement + 1)")
                            .foregroundStyle(.secondary)
                    }
                    Slider(
                        value: Binding(get: { scrubbing ?? fraction }, set: { scrubbing = $0 }),
                        in: 0...1
                    ) { editing in
                        guard !editing, let value = scrubbing else { return }
                        scrubbing = nil
                        player.seek(to: value)
                    }
                    .disabled(!player.canPlay || player.movementLength == 0)
                    HStack {
                        Text(Self.clock(player.elapsed))
                        Spacer()
                        Text(Self.clock(player.movementLength))
                    }
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(.secondary)
                    Text(player.status)
                    if let note = player.note { Text(note).font(.footnote).foregroundStyle(.secondary) }
                }
                Section {
                    Toggle("ReplayGain", isOn: $player.replayGain)
                } footer: {
                    Text("Off builds the engine without its gain stage.")
                }
                Section {
                    Picker("Curve", selection: $player.fade.outCurve) {
                        ForEach(FadeCurve.allCases) { Text($0.title).tag($0) }
                    }
                    Slider(value: $player.fade.outMilliseconds, in: LabFadeSettings.durationRange, step: 10)
                    Text("Length \(Int(player.fade.outMilliseconds)) ms")
                        .font(.footnote.monospacedDigit())
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Fade out")
                } footer: {
                    Text("At pause, a stall, a seek and a skip. 0 turns it off.")
                }
                Section {
                    Picker("Curve", selection: $player.fade.inCurve) {
                        ForEach(FadeCurve.allCases) { Text($0.title).tag($0) }
                    }
                    Slider(value: $player.fade.inMilliseconds, in: LabFadeSettings.durationRange, step: 10)
                    Text("Length \(Int(player.fade.inMilliseconds)) ms")
                        .font(.footnote.monospacedDigit())
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Fade in")
                } footer: {
                    Text("At the first sound, resume and the end of a stall. 0 turns it off.")
                }
                Section {
                    Picker("Mode", selection: $player.fade.seek) {
                        ForEach(LabFadeSettings.Seek.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    if player.fade.seek == .silence {
                        Slider(value: $player.fade.silenceMilliseconds, in: LabFadeSettings.silenceRange, step: 10)
                        Text("Silence \(Int(player.fade.silenceMilliseconds)) ms")
                            .font(.footnote.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Seek and skip")
                } footer: {
                    Text(
                        "Today: fade out and load at the same time; the two can overlap. "
                            + "Silence: fade out, wait, then fade in; never overlapping. "
                            + "Crossfade: the old place plays until the new one is ready, then both cross over: "
                            + "the old one with the fade-out curve and length, "
                            + "the new one with the fade-in curve and length.")
                }
                Section("Network") {
                    Picker("Throttle", selection: $player.throttle.mode) {
                        ForEach(LabThrottle.Mode.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
            }
            .navigationTitle("Playback Lab")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Disconnect") { model.disconnect() }
                }
            }
        }
    }

    private var fraction: Double {
        player.movementLength > 0 ? min(player.elapsed / player.movementLength, 1) : 0
    }

    private static func clock(_ seconds: Double) -> String {
        let whole = Int(max(seconds, 0))
        return String(format: "%d:%02d", whole / 60, whole % 60)
    }
}
