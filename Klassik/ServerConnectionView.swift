import SwiftUI

/// Which server Klassik talks to, what it holds from it, and Sign Out. Every value is known on the device, so the
/// page shows at once; the check of the server runs beside it and changes only the connection line.
struct ServerConnectionView: View {
    @Environment(AppModel.self) private var model
    @State private var confirmsSignOut = false

    var body: some View {
        let library = model.library
        let server = model.credentials.map { Self.address($0.url) } ?? ""
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
                // Server trouble shows here only, never as a notice for each failed sync.
                VStack(alignment: .leading) {
                    if model.serverReached == false {
                        Text(
                            "Klassik keeps playing from the library on this iPhone. Changes wait until the server answers."
                        )
                    }
                    if let error = library.syncError {
                        Text(verbatim: error)
                            .accessibilityIdentifier("library-synced")
                    }
                    if let trouble = model.serverTrouble {
                        Text(trouble.status)
                            .accessibilityIdentifier("server-status")
                    }
                }
            }

            Section {
                LabeledContent("Server", value: Self.name(of: model.serverInfo))
                    .ink()
                    .accessibilityIdentifier("server-name")
                LabeledContent(
                    "Classical Tracks",
                    value: Self.countText(library.classical.count, syncedAt: library.syncedAt)
                )
                .ink()
                .accessibilityIdentifier("server-classical-tracks")
                LabeledContent(
                    "Classical Albums",
                    value: Self.countText(library.classicalAlbumCount, syncedAt: library.syncedAt)
                )
                .ink()
                .accessibilityIdentifier("server-classical-albums")
                LabeledContent(
                    "Tracks Outside Filter",
                    value: Self.countText(library.otherTrackCount, syncedAt: library.syncedAt)
                )
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
                    .confirmationDialog("Sign Out", isPresented: $confirmsSignOut, titleVisibility: .visible) {
                        Button("Sign Out of \(server)", role: .destructive) { model.signOut() }
                    } message: {
                        Text(
                            "Downloads and the music cache leave this iPhone. Favourite works, listening notes and the changes that wait stay for this server and user."
                        )
                    }
            }
        }
        .pageTitle(L("Server Connection"))
        // The check updates the connection line and the server version. The page does not wait for it.
        .task { await model.check() }
    }

    private var lastSync: String {
        let library = model.library
        guard let syncedAt = library.syncedAt else { return library.isSyncing ? L("Syncing…") : L("Not synced") }
        return syncedAt.localized(date: .abbreviated, time: .shortened)
    }

    /// A track or album count. Before the first sync no count is known, so the row shows no number, not zero.
    static func countText(_ count: Int, syncedAt: Date?) -> String {
        syncedAt == nil ? "—" : count.localized()
    }

    /// The server as the specimen names it: "Navidrome 0.64.2". The build number in brackets stays out of the row.
    static func name(of info: ServerInfo?) -> String {
        guard let info else { return L("Unknown") }
        let type = info.type.map { String($0.prefix(1)).uppercased() + String($0.dropFirst()) }
        let version = info.serverVersion?.components(separatedBy: " (").first
        let name = [type, version].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
        return name.isEmpty ? L("Unknown") : name
    }

    /// The address without its scheme, as the listener typed it.
    static func address(_ url: URL) -> String {
        let text = url.absoluteString
        guard let scheme = ["https://", "http://"].first(where: { text.hasPrefix($0) }) else { return text }
        return String(text.dropFirst(scheme.count))
    }
}
