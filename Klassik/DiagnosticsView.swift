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
                    LabeledContent("OpenSubsonic", value: info.openSubsonic ? L("Yes") : L("No"))
                        .ink()
                        .accessibilityIdentifier("opensubsonic")
                    LabeledContent(
                        "Extensions",
                        value: info.extensions.isEmpty ? L("None") : info.extensions.sorted().joined(separator: ", ")
                    )
                    .ink()
                } else {
                    LabeledContent("Status", value: model.isChecking ? L("Checking…") : L("Not reached"))
                        .ink()
                }
                if let lastCheck = model.lastCheck {
                    LabeledContent("Last check", value: lastCheck.localized(date: .abbreviated, time: .standard))
                        .ink()
                }
            }

            Section("Library") {
                let library = model.library
                if let syncedAt = library.syncedAt {
                    LabeledContent("Tracks", value: library.songs.count.localized())
                        .ink()
                    LabeledContent("Albums", value: library.albumCount.localized())
                        .ink()
                    LabeledContent("Classical tracks", value: library.classical.count.localized())
                        .ink()
                    LabeledContent("Classical albums", value: library.classicalAlbumCount.localized())
                        .ink()
                    LabeledContent("Last sync", value: syncedAt.localized(date: .abbreviated, time: .standard))
                        .ink()
                    if let row = library.unchangedCheckRow {
                        LabeledContent("Last change check", value: row)
                            .ink()
                    }
                } else {
                    LabeledContent("Tracks", value: library.isSyncing ? L("Syncing…") : L("Not synced"))
                        .ink()
                }
                if let error = library.syncError {
                    LabeledContent("Sync error", value: error)
                        .ink()
                }
                if let error = model.recordingOrder.refreshError {
                    LabeledContent("Favourite refresh error", value: error).ink()
                }
                if let error = model.recordingOrder.loadError {
                    LabeledContent("Favourite file error", value: error).ink()
                }
            }

            Section("Favourite changes waiting") {
                let order = model.recordingOrder
                if order.pendingChanges.isEmpty {
                    Text("None").ink()
                }
                ForEach(order.pendingChanges) { change in
                    LabeledContent(
                        order.title(of: change), value: change.isSet ? L("Favourite") : L("Not a favourite")
                    )
                    .ink()
                    .accessibilityIdentifier("pending-favourite")
                }
            }

            Section("Last Error") {
                if let error = model.lastError {
                    Text(error)
                        .ink()
                    if let date = model.lastErrorDate {
                        Text(date.localized(date: .abbreviated, time: .standard))
                            .foregroundStyle(Palette.textSecondary)
                    }
                } else {
                    Text("None")
                        .foregroundStyle(Palette.textSecondary)
                }
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
                    Task { await model.refreshDiagnostics() }
                }
                .disabled(model.isChecking)
                Button("Sign Out", role: .destructive) {
                    model.signOut()
                }
            }
        }
        .pageTitle(L("Diagnostics"))
        .refreshable { await model.refreshDiagnostics() }
    }

    static var appVersion: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "?"
        let build = info["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }
}
