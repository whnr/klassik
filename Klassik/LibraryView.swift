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
                    .itemSeparator(first: row.id == rows.rows.first?.id, last: row.id == rows.rows.last?.id)
                }
                .onMove { rows.move(fromOffsets: $0, toOffset: $1) }
            } footer: {
                VStack(alignment: .leading) {
                    if let status {
                        Text(status)
                            .accessibilityIdentifier("library-synced")
                    }
                    // Server trouble shows here only, never as a notice for each failed sync (ADR 0058).
                    if let trouble = model.serverTrouble {
                        Text(trouble.status)
                            .accessibilityIdentifier("server-status")
                    }
                }
            }
        }
        .pageTitle("Library")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { EditButton() }
            ToolbarItem(placement: .topBarTrailing) {
                ShuffleButton(works: library.index.composers.flatMap(\.works))
            }
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink(value: Page.settings) {
                    Label("Settings", systemImage: "gearshape")
                }
                .accessibilityIdentifier("library-settings")
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
        case .favourites: model.recordingOrder.favouriteCount
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
                .itemSeparator(
                    first: composer.id == library.index.composers.first?.id,
                    last: composer.id == library.index.composers.last?.id)
            }
        }
        .overlay {
            if library.index.composers.isEmpty && !library.isSyncing {
                ContentUnavailableView("No Composers", systemImage: "music.quarternote.3")
            }
        }
        .pageTitle("Composers")
    }
}

/// The recordings that the listener marked.
struct FavouritesView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let works = model.recordingOrder.favouriteWorks
        let favourites = model.recordingOrder.favouriteRecordings
        PageList {
            ForEach(works) { work in
                WorkRow(work: work)
                    .itemSeparator(
                        first: work.id == works.first?.id, last: favourites.isEmpty && work.id == works.last?.id)
            }
            ForEach(favourites) { favourite in
                NavigationLink(value: Page.recording(work: favourite.work.id, recording: favourite.recording.id)) {
                    VStack(alignment: .leading) {
                        Text(favourite.work.title)
                            .ink()
                        Text(favourite.work.composer)
                            .typeStyle(.subheadline)
                            .foregroundStyle(Palette.textSecondary)
                        RoleLines(lines: favourite.recording.principalNames, style: .subheadline)
                            .foregroundStyle(Palette.textSecondary)
                    }
                }
                .itemActions(
                    QueueItem(work: favourite.work, recording: favourite.recording), downloads: true, favourite: true
                )
                .accessibilityIdentifier("favourite")
                .itemSeparator(
                    first: works.isEmpty && favourite.id == favourites.first?.id,
                    last: favourite.id == favourites.last?.id)
            }
        }
        .overlay {
            if favourites.isEmpty && works.isEmpty {
                ContentUnavailableView(
                    "No Favourites", systemImage: "star",
                    description: Text("Swipe a recording and choose Favourite to see it here."))
            }
        }
        .pageTitle("Favourites")
    }
}
