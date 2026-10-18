import SwiftUI

/// A quiet icon for tracks that play without the server. Downloaded is solid, cached is an outline.
struct OfflineHint: View {
    @Environment(AppModel.self) private var model
    let groups: [[Song]]

    init(songs: [Song]) {
        groups = [songs]
    }

    init(recordings: [WorkIndex.Recording]) {
        groups = recordings.map(\.songs)
    }

    var body: some View {
        let status = groups.map {
            OfflineStatus(songIDs: $0.map(\.id), downloaded: model.downloads.downloaded, cached: model.cache.ids)
        }.max()
        if let status, status != .none {
            Image(systemName: status == .downloaded ? "arrow.down.circle.fill" : "arrow.down.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityLabel(status == .downloaded ? "Downloaded" : "Ready offline")
        }
    }
}

/// What Klassik keeps on the device: the cache of played tracks and the downloads.
struct LocalStorageView: View {
    @Environment(AppModel.self) private var model
    @State private var confirmClearCache = false
    @State private var confirmRemoveAll = false

    private struct Row: Identifiable {
        var id: String
        var title: String
        var performers: String
        var songs: [Song]
        var size: Int64
    }

    /// Recordings of the library with at least one downloaded track.
    private var rows: [Row] {
        let downloaded = model.downloads.downloaded
        var seen: Set<String> = []
        var rows: [Row] = []
        for work in model.library.index.composers.flatMap(\.works) {
            for recording in work.recordings where seen.insert(recording.id).inserted {
                let songs = recording.songs.filter { downloaded.contains($0.id) }
                guard !songs.isEmpty else { continue }
                rows.append(
                    Row(
                        id: recording.id, title: work.title,
                        performers: recording.performers.isEmpty ? recording.album : recording.performers,
                        songs: recording.songs, size: model.downloads.size(of: songs)))
            }
        }
        return rows
    }

    private func bytes(_ size: Int64) -> String {
        size.formatted(.byteCount(style: .file))
    }

    var body: some View {
        @Bindable var cache = model.cache
        let downloads = model.downloads
        List {
            Section {
                LabeledContent("Cache Size", value: bytes(cache.size))
                    .accessibilityIdentifier("cache-size")
                Picker("Maximum Cache Size", selection: $cache.limit) {
                    ForEach(TrackCache.limits, id: \.self) { Text(bytes($0)).tag($0) }
                }
                .accessibilityIdentifier("cache-limit")
                Button("Clear Cache", role: .destructive) { confirmClearCache = true }
                    .disabled(cache.size == 0)
                    .accessibilityIdentifier("clear-cache")
            } header: {
                Text("Cache")
            } footer: {
                Text("Klassik keeps the tracks you play. It removes the least recently played tracks above the limit.")
            }

            Section {
                ForEach(rows) { row in
                    VStack(alignment: .leading) {
                        Text(row.title)
                        Text([row.performers, bytes(row.size)].filter { !$0.isEmpty }.joined(separator: " · "))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .swipeActions {
                        Button("Delete", systemImage: "trash", role: .destructive) { downloads.remove(row.songs) }
                    }
                    .accessibilityIdentifier("download-row")
                }
                Button("Remove All Downloads", role: .destructive) { confirmRemoveAll = true }
                    .disabled(downloads.downloaded.isEmpty)
                    .accessibilityIdentifier("remove-downloads")
            } header: {
                Text("Downloads")
            } footer: {
                Text("\(bytes(downloads.totalSize)) in downloads. The cache limit does not count them.")
            }
        }
        .navigationTitle("Local Storage")
        .miniPlayerInset()
        .onChange(of: cache.limit) { cache.enforce(protecting: downloads.downloaded) }
        .confirmationDialog("Clear the cache?", isPresented: $confirmClearCache, titleVisibility: .visible) {
            Button("Clear Cache", role: .destructive) { cache.clear() }
        } message: {
            Text("Downloads stay on the device.")
        }
        .confirmationDialog("Remove all downloads?", isPresented: $confirmRemoveAll, titleVisibility: .visible) {
            Button("Remove All Downloads", role: .destructive) { downloads.removeAll() }
        } message: {
            Text("You need the server to play these tracks again.")
        }
    }
}
