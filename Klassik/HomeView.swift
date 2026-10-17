import SwiftUI

struct HomeView: View {
    var body: some View {
        NavigationStack {
            List {
                Section {
                    ContentUnavailableView(
                        "No Music Yet", systemImage: "music.note.list",
                        description: Text("Klassik does not sync your library yet."))
                }
                Section {
                    NavigationLink {
                        DiagnosticsView()
                    } label: {
                        Label("Diagnostics", systemImage: "stethoscope")
                    }
                    .accessibilityIdentifier("diagnostics")
                }
            }
            .navigationTitle("Klassik")
        }
    }
}
