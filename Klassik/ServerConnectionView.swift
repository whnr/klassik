import SwiftUI

/// Which server Klassik talks to, what it holds from it, and Sign Out. Every value is known on the device, so the
/// page shows at once; the check of the server runs beside it and changes only the connection line.
struct ServerConnectionView: View {
    @Environment(AppModel.self) private var model
    @State private var confirmsSignOut = false

    var body: some View {
        let library = model.library
        PageForm {
            if let credentials = model.credentials {
                Section("Account") {
                    LabeledContent("Server Address", value: Self.address(credentials.url))
                        .ink()
                        .accessibilityIdentifier("server-address")
                    LabeledContent("Username", value: credentials.username)
                        .ink()
                        .accessibilityIdentifier("server-username")
                }
            }

            Section {
                LabeledContent("Connection", value: model.connectionState)
                    .ink()
                    .accessibilityIdentifier("server-state")
            } footer: {
                if model.serverReached == false {
                    Text(
                        "Klassik keeps playing from the library on this iPhone. Changes wait until the server answers.")
                }
            }

            Section {
                LabeledContent("Server", value: serverName)
                    .ink()
                    .accessibilityIdentifier("server-name")
                LabeledContent("Classical Tracks", value: library.classical.count.formatted())
                    .ink()
                    .accessibilityIdentifier("server-classical-tracks")
                LabeledContent("Classical Albums", value: library.classicalAlbumCount.formatted())
                    .ink()
                    .accessibilityIdentifier("server-classical-albums")
                LabeledContent("Tracks Outside Filter", value: library.otherTrackCount.formatted())
                    .ink()
                    .accessibilityIdentifier("server-other-tracks")
                LabeledContent("Last Sync", value: lastSync)
                    .ink()
                    .accessibilityIdentifier("server-last-sync")
            } header: {
                Text("Library")
            } footer: {
                Text(
                    "Classical counts follow the classical rules. Tracks Outside Filter are on the server but fail the rules."
                )
            }

            Section {
                Button("Sign Out", role: .destructive) { confirmsSignOut = true }
                    .accessibilityIdentifier("sign-out")
                    .confirmationDialog("Sign Out?", isPresented: $confirmsSignOut, titleVisibility: .visible) {
                        Button("Sign Out", role: .destructive) { model.signOut() }
                    } message: {
                        Text(
                            "Downloads and the music cache leave this iPhone. Favourite works, listening notes and the changes that wait stay for this server and user."
                        )
                    }
            }
        }
        .pageTitle("Server Connection")
        // The check updates the connection line and the server version. The page does not wait for it.
        .task { await model.check() }
    }

    private var serverName: String {
        guard let info = model.serverInfo else { return "Unknown" }
        let name = [info.type, info.serverVersion].compactMap(\.self).joined(separator: " ")
        return name.isEmpty ? "Unknown" : name
    }

    private var lastSync: String {
        let library = model.library
        guard let syncedAt = library.syncedAt else { return library.isSyncing ? "Syncing…" : "Not synced" }
        return syncedAt.formatted(date: .abbreviated, time: .shortened)
    }

    /// The address without its scheme, as the listener typed it.
    static func address(_ url: URL) -> String {
        let text = url.absoluteString
        guard let scheme = ["https://", "http://"].first { text.hasPrefix($0) } else { return text }
        return String(text.dropFirst(scheme.count))
    }
}
