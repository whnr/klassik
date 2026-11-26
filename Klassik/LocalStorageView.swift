import SwiftUI

/// What Klassik keeps on the device: the music cache, the downloads, the pictures and the album art, in one bar
/// like the iPhone storage page. Only the music cache has a limit; pictures and album art only show their size.
struct LocalStorageView: View {
    @Environment(AppModel.self) private var model
    @State private var available: Int64?

    var body: some View {
        @Bindable var tracks = model.tracks
        let pictures = model.pictures
        let albumArt = model.albumArt
        let parts = [
            StoragePart(id: "music", name: "Music", colour: .tint, bytes: tracks.cacheBytes),
            StoragePart(id: "downloads", name: "Downloads", colour: .swipeDownload, bytes: tracks.downloadBytes),
            StoragePart(id: "pictures", name: "Pictures", colour: .textSecondary, bytes: pictures.bytes),
            StoragePart(id: "album-art", name: "Album Art", colour: .textTertiary, bytes: albumArt.bytes),
        ]
        let total = parts.reduce(0) { $0 + $1.bytes }
        PageForm {
            Section {
                StorageBar(parts: parts, total: total)
                ForEach(parts) { part in
                    LabeledContent {
                        Text(Self.size(part.bytes))
                    } label: {
                        Label {
                            Text(part.name)
                        } icon: {
                            Circle()
                                .fill(part.colour)
                                .frame(width: Layout.storageDot, height: Layout.storageDot)
                        }
                    }
                    .ink()
                    .accessibilityIdentifier("storage-\(part.id)")
                }
            } footer: {
                Text(
                    available.map { "Klassik uses \(Self.size(total)). \(Self.size($0)) free on this iPhone." }
                        ?? "Klassik uses \(Self.size(total))."
                )
            }

            Section {
                Stepper(
                    value: Binding(
                        get: { max(1, Int(tracks.cacheLimit / TrackStore.gigabyte)) },
                        set: { tracks.cacheLimit = Int64($0) * TrackStore.gigabyte }),
                    in: TrackStore.limitRange
                ) {
                    LabeledContent("Limit", value: Self.size(tracks.cacheLimit))
                        .ink()
                }
                .accessibilityIdentifier("cache-limit")
                Button("Clear Music", role: .destructive) { tracks.clearCache() }
                    .disabled(tracks.cacheBytes == 0)
                    .accessibilityIdentifier("clear-cache")
            } header: {
                Text("Music")
            } footer: {
                Text(
                    "Every track that plays stays here. When the cache is full, the tracks played longest ago go first."
                )
            }

            Section {
                if tracks.downloads.isEmpty {
                    Text("No downloads")
                        .foregroundStyle(Palette.textSecondary)
                } else {
                    ForEach(tracks.downloads.sorted { $0.date > $1.date }) { download in
                        VStack(alignment: .leading) {
                            Text(download.title)
                                .ink()
                            if !download.detail.isEmpty {
                                Text(download.detail)
                                    .typeStyle(.subheadline)
                                    .foregroundStyle(Palette.textSecondary)
                            }
                            Text(Self.size(download.bytes))
                                .typeStyle(.subheadline)
                                .foregroundStyle(Palette.textSecondary)
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
                Text("A download stays until you remove it. The music limit does not count it. Signing out removes it.")
            }
        }
        .pageTitle("Local Storage")
        .task { available = await Self.availableBytes() }
    }

    static func size(_ bytes: Int64) -> String {
        bytes.formatted(.byteCount(style: .file))
    }

    /// The free space that the system reports for files that the listener asked for.
    private static func availableBytes() async -> Int64? {
        await Task.detached(priority: .utility) {
            let values = try? URL.homeDirectory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            return values?.volumeAvailableCapacityForImportantUsage
        }.value
    }
}

/// One store of the storage bar.
struct StoragePart: Identifiable {
    var id: String
    var name: String
    var colour: Palette
    var bytes: Int64
}

/// The stores side by side, each as wide as its share of what Klassik keeps. An empty store takes no room.
private struct StorageBar: View {
    let parts: [StoragePart]
    let total: Int64

    var body: some View {
        GeometryReader { geometry in
            let shown = parts.filter { $0.bytes > 0 }
            let width = geometry.size.width - Layout.storageBarGap * CGFloat(max(0, shown.count - 1))
            HStack(spacing: Layout.storageBarGap) {
                ForEach(shown) { part in
                    Rectangle()
                        .fill(part.colour)
                        .frame(width: max(Layout.storageBarMinimum, width * part.share(of: total)))
                }
            }
        }
        .frame(height: Layout.storageBar)
        .background(Palette.fillQuiet)
        .clipShape(RoundedRectangle(cornerRadius: Layout.storageBarCorner))
        .accessibilityElement()
        .accessibilityLabel("Klassik uses \(LocalStorageView.size(total))")
        .accessibilityIdentifier("storage-bar")
    }
}

extension StoragePart {
    /// The share of the total, from 0 to 1. An empty total has no shares.
    func share(of total: Int64) -> CGFloat {
        total > 0 ? CGFloat(bytes) / CGFloat(total) : 0
    }
}
