import SwiftUI

/// The Library place: the listener's own collection, in the order the listener sets.
struct LibraryView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let library = model.library
        let rows = model.libraryRows
        PageList {
            Section {
                ForEach(rows.rows) { row in
                    NavigationLink(value: row.page) {
                        LabeledContent(row.title, value: count(of: row).formatted())
                            .ink()
                    }
                    .accessibilityIdentifier("library-\(row.rawValue)")
                }
                .onMove { rows.move(fromOffsets: $0, toOffset: $1) }
            } footer: {
                if let status {
                    Text(status)
                        .accessibilityIdentifier("library-synced")
                }
            }
        }
        .navigationTitle("Library")
        .miniPlayerInset()
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { EditButton() }
            ToolbarItem(placement: .topBarTrailing) {
                ShuffleButton(works: library.index.composers.flatMap(\.works))
            }
        }
        .refreshable {
            guard let client = model.client else { return }
            await library.sync(with: client)
            // The lookup can take minutes; the pull to refresh ends with the sync.
            Task { await model.enrichment.enrich(library.index) }
        }
    }

    private func count(of row: LibraryRow) -> Int {
        switch row {
        case .composers: model.library.index.composers.count
        case .favourites: model.library.index.favourites.count
        }
    }

    private var status: String? {
        let library = model.library
        if let error = library.syncError { return error }
        guard let syncedAt = library.syncedAt else {
            return library.isSyncing ? "Syncing… \(library.received) tracks" : "Not synced."
        }
        return library.isSyncing
            ? "Syncing… \(library.received) tracks"
            : "Synced \(syncedAt.formatted(.relative(presentation: .named)))."
    }
}

extension WorkIndex {
    /// One recording that the listener marked. Today the mark is the star on all its tracks.
    struct Favourite: Identifiable {
        var work: Work
        var recording: Recording
        var id: String { recording.id }
    }

    var favourites: [Favourite] {
        composers.flatMap(\.works).flatMap { work in
            work.recordings.filter(\.isReference).map { Favourite(work: work, recording: $0) }
        }
    }
}

/// Every composer of the library.
struct ComposersView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let library = model.library
        PageList {
            ForEach(library.index.composers) { composer in
                NavigationLink(value: Page.composer(composer.name)) {
                    LabeledContent(composer.name, value: composer.works.count.formatted())
                        .ink()
                }
                .accessibilityIdentifier("composer")
            }
        }
        .overlay {
            if library.index.composers.isEmpty && !library.isSyncing {
                ContentUnavailableView("No Composers", systemImage: "music.quarternote.3")
            }
        }
        .navigationTitle("Composers")
        .miniPlayerInset()
    }
}

/// The recordings that the listener marked.
struct FavouritesView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let favourites = model.library.index.favourites
        PageList {
            ForEach(favourites) { favourite in
                NavigationLink(value: Page.recording(work: favourite.work.id, recording: favourite.recording.id)) {
                    VStack(alignment: .leading) {
                        Text(favourite.work.title)
                            .ink()
                        Text(
                            [favourite.work.composer, favourite.recording.performers]
                                .filter { !$0.isEmpty }.joined(separator: " · ")
                        )
                        .typeStyle(.subheadline)
                        .foregroundStyle(Palette.textSecondary)
                    }
                }
                .itemActions(
                    QueueItem(work: favourite.work, recording: favourite.recording), downloads: true, reference: true
                )
                .accessibilityIdentifier("favourite")
            }
        }
        .overlay {
            if favourites.isEmpty {
                ContentUnavailableView(
                    "No Favourites", systemImage: "star",
                    description: Text("Swipe a recording and choose Reference to see it here."))
            }
        }
        .navigationTitle("Favourites")
        .miniPlayerInset()
    }
}
