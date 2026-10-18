import SwiftUI

/// What a bug report needs: which server, which API, what the app holds, what went wrong last.
struct DiagnosticsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Form {
            Section("Server") {
                if let credentials = model.credentials {
                    LabeledContent("URL", value: credentials.url.absoluteString)
                    LabeledContent("User", value: credentials.username)
                }
                if let info = model.serverInfo {
                    LabeledContent(
                        "Server", value: [info.type, info.serverVersion].compactMap(\.self).joined(separator: " "))
                    LabeledContent("API version", value: info.apiVersion)
                    LabeledContent("OpenSubsonic", value: info.openSubsonic ? "Yes" : "No")
                        .accessibilityIdentifier("opensubsonic")
                    LabeledContent(
                        "Extensions",
                        value: info.extensions.isEmpty ? "None" : info.extensions.sorted().joined(separator: ", "))
                } else {
                    LabeledContent("Status", value: model.isChecking ? "Checking…" : "Not reached")
                }
                if let lastCheck = model.lastCheck {
                    LabeledContent("Last check", value: lastCheck.formatted(date: .abbreviated, time: .standard))
                }
            }

            Section("Library") {
                let library = model.library
                if let syncedAt = library.syncedAt {
                    LabeledContent("Tracks", value: library.songs.count.formatted())
                    LabeledContent("Albums", value: library.albumCount.formatted())
                    LabeledContent("Classical tracks", value: library.classical.count.formatted())
                    LabeledContent("Classical albums", value: library.classicalAlbumCount.formatted())
                    LabeledContent("Last sync", value: syncedAt.formatted(date: .abbreviated, time: .standard))
                } else {
                    LabeledContent("Tracks", value: library.isSyncing ? "Syncing…" : "Not synced")
                }
                if let error = library.syncError {
                    LabeledContent("Sync error", value: error)
                }
            }

            Section("Last Error") {
                if let error = model.lastError {
                    Text(error)
                    if let date = model.lastErrorDate {
                        Text(date.formatted(date: .abbreviated, time: .standard))
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("None")
                        .foregroundStyle(.secondary)
                }
            }

            Section("Playback") {
                NavigationLink("Gapless Test") { GaplessTestView() }
                    .accessibilityIdentifier("gapless-test")
            }

            Section("App") {
                LabeledContent("Version", value: Self.appVersion)
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
        .miniPlayerInset()
        .refreshable { await model.check() }
    }

    static var appVersion: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "?"
        let build = info["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }
}
