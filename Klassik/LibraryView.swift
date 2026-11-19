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
            await model.fullSync()
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
                PersonPageLink(page: .composer(composer.name)) {
                    LabeledContent {
                        Text(composer.works.count.formatted())
                    } label: {
                        MarkedTitle(
                            title: composer.name, isFavourite: model.recordingOrder.isFavourite(person: composer.name))
                    }
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
        let albums = model.recordingOrder.favouriteAlbums
        let composers = model.recordingOrder.favouriteComposers
        let performers = model.recordingOrder.favouritePerformers
        PageList {
            ForEach(composers) { composer in
                PersonPageLink(page: .composer(composer.name)) {
                    MarkedTitle(title: composer.name, isFavourite: true).ink()
                }
                .accessibilityIdentifier("favourite-composer-row")
                .itemSeparator(
                    first: composer.id == composers.first?.id,
                    last: composer.id == composers.last?.id && performers.isEmpty && albums.isEmpty
                        && works.isEmpty && favourites.isEmpty)
            }
            ForEach(performers) { performer in
                PersonPageLink(page: .performer(performer.name)) {
                    MarkedTitle(title: performer.name, isFavourite: true).ink()
                }
                .accessibilityIdentifier("favourite-performer-row")
                .itemSeparator(
                    first: composers.isEmpty && performer.id == performers.first?.id,
                    last: performer.id == performers.last?.id && albums.isEmpty && works.isEmpty && favourites.isEmpty)
            }
            ForEach(albums) { album in
                NavigationLink(value: Page.album(album.id)) {
                    VStack(alignment: .leading) {
                        MarkedTitle(title: album.title, isFavourite: true).ink()
                        Text("Album").typeStyle(.subheadline).foregroundStyle(Palette.textSecondary)
                    }
                }
                .itemActions(album.item, downloads: true, favouriteAlbum: true)
                .accessibilityIdentifier("favourite-album-row")
                .itemSeparator(
                    first: composers.isEmpty && performers.isEmpty && album.id == albums.first?.id,
                    last: album.id == albums.last?.id && works.isEmpty && favourites.isEmpty)
            }
            ForEach(works) { work in
                WorkRow(work: work)
                    .itemSeparator(
                        first: composers.isEmpty && performers.isEmpty && albums.isEmpty && work.id == works.first?.id,
                        last: favourites.isEmpty && work.id == works.last?.id)
            }
            ForEach(favourites) { favourite in
                NavigationLink(value: Page.recording(work: favourite.work.id, recording: favourite.recording.id)) {
                    VStack(alignment: .leading) {
                        MarkedTitle(title: favourite.work.title, isFavourite: true)
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
                    first: composers.isEmpty && performers.isEmpty && albums.isEmpty && works.isEmpty
                        && favourite.id == favourites.first?.id,
                    last: favourite.id == favourites.last?.id)
            }
        }
        .overlay {
            if favourites.isEmpty && works.isEmpty && albums.isEmpty && composers.isEmpty && performers.isEmpty {
                ContentUnavailableView(
                    "No Favourites", systemImage: "star",
                    description: Text("Mark a person, work, recording or album as a favourite to see it here."))
            }
        }
        .pageTitle("Favourites")
    }
}
