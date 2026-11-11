import SwiftUI

/// What a bug report needs: which server, which API, what the app holds, what went wrong last.
struct DiagnosticsView: View {
    @Environment(AppModel.self) private var model
    @AppStorage(TapIndicator.storageKey) private var showTaps = false

    var body: some View {
        PageForm {
            Section("Server") {
                if let credentials = model.credentials {
                    LabeledContent("URL", value: credentials.url.absoluteString)
                        .ink()
                    LabeledContent("User", value: credentials.username)
                        .ink()
                }
                if let info = model.serverInfo {
                    LabeledContent(
                        "Server", value: [info.type, info.serverVersion].compactMap(\.self).joined(separator: " ")
                    )
                    .ink()
                    LabeledContent("API version", value: info.apiVersion)
                        .ink()
                    LabeledContent("OpenSubsonic", value: info.openSubsonic ? "Yes" : "No")
                        .ink()
                        .accessibilityIdentifier("opensubsonic")
                    LabeledContent(
                        "Extensions",
                        value: info.extensions.isEmpty ? "None" : info.extensions.sorted().joined(separator: ", ")
                    )
                    .ink()
                } else {
                    LabeledContent("Status", value: model.isChecking ? "Checking…" : "Not reached")
                        .ink()
                }
                if let lastCheck = model.lastCheck {
                    LabeledContent("Last check", value: lastCheck.formatted(date: .abbreviated, time: .standard))
                        .ink()
                }
            }

            Section("Library") {
                let library = model.library
                if let syncedAt = library.syncedAt {
                    LabeledContent("Tracks", value: library.songs.count.formatted())
                        .ink()
                    LabeledContent("Albums", value: library.albumCount.formatted())
                        .ink()
                    LabeledContent("Classical tracks", value: library.classical.count.formatted())
                        .ink()
                    LabeledContent("Classical albums", value: library.classicalAlbumCount.formatted())
                        .ink()
                    LabeledContent("Last sync", value: syncedAt.formatted(date: .abbreviated, time: .standard))
                        .ink()
                } else {
                    LabeledContent("Tracks", value: library.isSyncing ? "Syncing…" : "Not synced")
                        .ink()
                }
                if let error = library.syncError {
                    LabeledContent("Sync error", value: error)
                        .ink()
                }
            }

            Section("Last Error") {
                if let error = model.lastError {
                    Text(error)
                        .ink()
                    if let date = model.lastErrorDate {
                        Text(date.formatted(date: .abbreviated, time: .standard))
                            .foregroundStyle(Palette.textSecondary)
                    }
                } else {
                    Text("None")
                        .foregroundStyle(Palette.textSecondary)
                }
            }

            Section("Playback") {
                NavigationLink(value: Page.gaplessTest) {
                    Text("Gapless Test")
                        .ink()
                }
                .accessibilityIdentifier("gapless-test")
            }

            Section {
                Toggle("Show Taps", isOn: $showTaps)
                    .accessibilityIdentifier("show-taps")
            } header: {
                Text("Recording")
            } footer: {
                Text("Shows a circle at each touch, so a screen recording shows where you tap.")
            }

            Section("App") {
                LabeledContent("Version", value: Self.appVersion)
                    .ink()
            }

            Section {
                Button("Check Again") {
                    Task { await model.check() }
                }
                .disabled(model.isChecking)
                Button("Sign Out", role: .destructive) {
                    model.signOut()
                }
            }
        }
        .navigationTitle("Diagnostics")
        .refreshable { await model.check() }
    }

    static var appVersion: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "?"
        let build = info["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }
}
