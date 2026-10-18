import SwiftUI

/// What Klassik keeps on the device: the cache of played tracks and the downloads.
struct LocalStorageView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var tracks = model.tracks
        Form {
            Section {
                LabeledContent("Used", value: Self.size(tracks.cacheBytes))
                Picker("Limit", selection: $tracks.cacheLimit) {
                    ForEach(TrackStore.limits, id: \.self) { Text(Self.size($0)).tag($0) }
                }
                Button("Clear Cache", role: .destructive) { tracks.clearCache() }
                    .disabled(tracks.cacheBytes == 0)
                    .accessibilityIdentifier("clear-cache")
            } header: {
                Text("Cache")
            } footer: {
                Text(
                    "Every track that plays stays here. When the cache is full, the tracks played longest ago go first."
                )
            }

            Section {
                if tracks.downloads.isEmpty {
                    Text("No downloads")
                        .foregroundStyle(.secondary)
                } else {
                    LabeledContent("Used", value: Self.size(tracks.downloadBytes))
                    ForEach(tracks.downloads.sorted { $0.date > $1.date }) { download in
                        VStack(alignment: .leading) {
                            Text(download.title)
                            Text(
                                [download.detail, Self.size(download.bytes)]
                                    .filter { !$0.isEmpty }.joined(separator: " · ")
                            )
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        }
                        .swipeActions {
                            Button("Remove", systemImage: "trash", role: .destructive) { tracks.remove(download) }
                        }
                        .accessibilityIdentifier("download")
                    }
                }
            } header: {
                Text("Downloads")
            } footer: {
                Text("A download stays until you remove it. The cache limit does not count it. Signing out removes it.")
            }
        }
        .navigationTitle("Local Storage")
        .miniPlayerInset()
    }

    private static func size(_ bytes: Int64) -> String {
        bytes.formatted(.byteCount(style: .file))
    }
}
