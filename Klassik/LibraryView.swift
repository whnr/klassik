import SwiftUI

/// The Library place: the listener's own collection, as rows in the order the listener sets.
struct LibraryView: View {
    @Environment(AppModel.self) private var model
    @State private var pageCache = PageCache()
    /// Set while the edit sheet is up. The tab then selects a row on a tap and opens nothing.
    @State private var editor: LibraryEditor?

    var body: some View {
        let library = model.library
        let order = model.recordingOrder
        let rows = model.libraryRows.rows
        let favourites = LibraryPage.Favourites(
            composers: order.favouriteComposers, performers: order.favouritePerformers,
            albums: order.favouriteAlbums, works: order.favouriteWorks, recordings: order.favouriteRecordings)
        let page = pageCache.page(
            for: PageKey(
                indexVersion: library.indexVersion, favourites: favourites.signature, rows: rows,
                day: Calendar.current.startOfDay(for: .now))
        ) {
            LibraryPage(index: library.index, favourites: favourites, rows: rows, date: .now)
        }
        ScrollViewReader { proxy in
            PageList {
                ForEach(page.sections) { section in
                    LibrarySectionView(
                        section: section, isSelected: editor?.selected == section.id,
                        select: selection(of: section.id)
                    )
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
                }
            }
            // A change can make rows above the selected one taller or shorter, so it scrolls back to the top.
            .onChange(of: editor?.selected) { scrollToSelected(proxy) }
            .onChange(of: rows) { scrollToSelected(proxy) }
        }
        .pageTitle(L("Library"))
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button("Edit") { editor = LibraryEditor(rows: model.libraryRows) }
                    .opacity(editor == nil ? 1 : 0)
                    .disabled(editor != nil)
                    .accessibilityIdentifier("library-edit")
                NavigationLink(value: Page.settings) {
                    Label("Settings", systemImage: "gearshape")
                }
                .accessibilityIdentifier("library-settings")
            }
        }
        .sheet(
            isPresented: Binding(get: { editor != nil }, set: { if !$0 { editor = nil } })
        ) {
            if let editor { LibraryEditSheet(editor: editor, rows: rows, page: page) }
        }
        .refreshable {
            await model.fullSync()
            // The lookup can take minutes; the pull to refresh ends with the sync.
            Task { await model.enrichment.enrich(library.index) }
        }
    }
}

extension LibraryView {
    /// The tap that selects a row, only while the edit sheet is up.
    fileprivate func selection(of id: String) -> (() -> Void)? {
        guard let editor else { return nil }
        return { editor.select(id) }
    }

    fileprivate func scrollToSelected(_ proxy: ScrollViewProxy) {
        guard let id = editor?.selected else { return }
        proxy.scrollTo(id, anchor: .top)
    }
}

/// What the page depends on. The page is built again only when this changes, not on every body pass.
private struct PageKey: Equatable {
    var indexVersion: Int
    var favourites: [String]
    var rows: [LibraryRowSetup]
    var day: Date
}

/// Holds the last page, so that a body pass without a change does not build it again. It is not observed: a view
/// reads it only while it draws.
private final class PageCache {
    private var key: PageKey?
    private var page: LibraryPage?

    func page(for key: PageKey, build: () -> LibraryPage) -> LibraryPage {
        if let page, self.key == key { return page }
        let built = build()
        self.key = key
        page = built
        return built
    }
}

/// One row of the tab: a title, then a strip, tiles or the link list.
private struct LibrarySectionView: View {
    @Environment(AppNavigator.self) private var navigator
    let section: LibraryPage.Section
    var isSelected = false
    /// Set while the edit sheet is up: a tap selects the row, and no card or title opens a page.
    var select: (() -> Void)?

    private var edges: EdgeInsets { Layout.edges(side: .standard, timeline: false) }

    var body: some View {
        content
            .accessibilityHidden(select != nil)
            .background {
                if isSelected { Rectangle().fill(Palette.tint.opacity(Layout.editSelectedTint)) }
            }
            .overlay {
                if let select {
                    Color.clear
                        .contentShape(.rect)
                        .onTapGesture(perform: select)
                        .accessibilityElement()
                        .accessibilityLabel(section.title ?? L("Link list"))
                        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : [.isButton])
                        .accessibilityIdentifier("library-row-\(section.kindName)")
                }
            }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let title = section.title {
                head(title)
            }
            if !section.links.isEmpty {
                links
                    .padding(.top, Layout.libraryLinksTop)
            } else if section.isTiles {
                LazyVGrid(
                    columns: Array(
                        repeating: GridItem(.flexible(), spacing: Layout.libraryTileColumnGap, alignment: .top),
                        count: Layout.libraryTileColumns),
                    alignment: .leading, spacing: Layout.libraryTileRowGap
                ) {
                    ForEach(section.cards) { LibraryCardView(card: $0, look: section.look, width: nil) }
                }
                .padding(.leading, edges.leading)
                .padding(.trailing, edges.trailing)
                .padding(.bottom, Layout.libraryStripBottom)
            } else {
                // A strip is as tall as its tallest card: the cards align at the top and the row takes the largest.
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: Layout.libraryStripGap) {
                        ForEach(section.cards) {
                            LibraryCardView(card: $0, look: section.look, width: Self.width(of: section.look))
                        }
                    }
                    .padding(.leading, edges.leading)
                    .padding(.trailing, edges.trailing)
                    .padding(.bottom, Layout.libraryStripBottom)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private static func width(of look: LibraryPage.Look) -> CGFloat {
        switch look {
        case .faces: Layout.libraryFaceCard
        case .covers: Layout.libraryCoverCard
        case .mixed: Layout.libraryMixedCard
        }
    }

    @ViewBuilder
    private func head(_ title: String) -> some View {
        let label = HStack {
            Text(verbatim: title)
                .typeStyle(Layout.sectionHeading)
                .foregroundStyle(Palette.textPrimary)
                .multilineTextAlignment(.leading)
            Spacer(minLength: 0)
            if section.titlePage != nil {
                Image(systemName: "chevron.right")
                    .typeStyle(.footnote)
                    .fontWeight(.semibold)
                    .foregroundStyle(Palette.textTertiary)
                    .accessibilityHidden(true)
            }
        }
        .padding(.top, Layout.libraryHeadTop)
        .padding(.bottom, Layout.libraryHeadBottom)
        .padding(.leading, edges.leading)
        .padding(.trailing, edges.trailing)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(.rect)
        if let page = section.titlePage {
            Button {
                navigator.open(page, in: navigator.selection)
            } label: {
                label
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("library-\(section.kindName)")
        } else {
            label.accessibilityAddTraits(.isHeader)
        }
    }

    private var links: some View {
        LazyVGrid(
            columns: Array(
                repeating: GridItem(.flexible(), spacing: Layout.libraryLinksGap, alignment: .top), count: 3),
            spacing: Layout.libraryLinksGap
        ) {
            ForEach(section.links) { link in
                let tile = VStack(alignment: .leading, spacing: 0) {
                    Text(link.count.localized())
                        .typeStyle(Layout.libraryLinkCount)
                        .foregroundStyle(Palette.textPrimary)
                    Text(verbatim: link.title)
                        .typeStyle(.footnote)
                        .foregroundStyle(Palette.textSecondary)
                }
                .padding(Layout.libraryLinkPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Palette.fillQuiet, in: RoundedRectangle(cornerRadius: Layout.libraryLinkCorner))
                .contentShape(.rect)
                if let page = link.page {
                    Button {
                        navigator.open(page, in: navigator.selection)
                    } label: {
                        tile
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("library-link-\(link.id)")
                } else {
                    tile
                }
            }
        }
        .padding(.leading, edges.leading)
        .padding(.trailing, edges.trailing)
    }
}

/// A card: a face or a cover, the full name in up to three lines, then one fact line.
private struct LibraryCardView: View {
    @Environment(AppNavigator.self) private var navigator
    let card: LibraryPage.Card
    let look: LibraryPage.Look
    /// Nil in a grid of tiles, where the column sets the width.
    let width: CGFloat?

    private var isFace: Bool {
        switch card.picture {
        case .composer, .performer: true
        case .cover: false
        }
    }

    var body: some View {
        switch card.page {
        case .composer, .performer:
            PersonPageLink(page: card.page, disclosure: false) { content }
                .frame(width: width)
        default:
            Button {
                navigator.open(card.page, in: navigator.selection)
            } label: {
                content.contentShape(.rect)
            }
            .buttonStyle(.plain)
            .frame(width: width)
        }
    }

    private var content: some View {
        VStack(alignment: isFace && look == .faces ? .center : .leading, spacing: 0) {
            picture
                .aspectRatio(1, contentMode: .fit)
            VStack(alignment: isFace && look == .faces ? .center : .leading, spacing: 0) {
                Text(verbatim: Hyphenation.soften(card.name, locale: Localization.shared.locale))
                    .typeStyle(Layout.libraryName)
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(Layout.libraryNameLines)
                Text(verbatim: card.fact)
                    .typeStyle(Layout.libraryFact)
                    .foregroundStyle(Palette.textSecondary)
                    .lineLimit(1)
            }
            .multilineTextAlignment(isFace && look == .faces ? .center : .leading)
            .padding(.top, Layout.libraryCaptionTop)
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("library-card")
    }

    @ViewBuilder
    private var picture: some View {
        switch card.picture {
        case .composer(let name): FaceImage(name: name, isPerformer: false)
        case .performer(let name): FaceImage(name: name, isPerformer: true)
        case .cover(let song):
            CoverImage(song: song, points: width ?? Layout.libraryCoverCard)
                .clipShape(RoundedRectangle(cornerRadius: Layout.albumCorner))
        }
    }
}

/// A round picture of a person. It shows the kept picture at once, else the initials, and never waits for the
/// network (ADR 0059).
private struct FaceImage: View {
    @Environment(AppModel.self) private var model
    let name: String
    let isPerformer: Bool
    @State private var loaded: UIImage?

    private var portrait: PersonPortrait? {
        isPerformer ? model.people.facts(ofPerformer: name)?.portrait : model.people.facts(ofComposer: name)?.portrait
    }

    var body: some View {
        let portrait = portrait
        let image = loaded ?? portrait.flatMap { PortraitLoader.ready($0)?.image }
        Circle()
            .fill(Palette.fillQuiet)
            .overlay(alignment: .top) {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Text(verbatim: Self.initials(of: name))
                        .typeStyle(.footnote)
                        .foregroundStyle(Palette.textSecondary)
                        .frame(maxHeight: .infinity)
                }
            }
            .clipShape(Circle())
            .accessibilityHidden(true)
            .task(id: portrait?.url) {
                guard let portrait, PortraitLoader.ready(portrait) == nil else { return }
                let local = PortraitLoader.stored({ _ in throw URLError(.notConnectedToInternet) }, in: { .pictures })
                loaded = await PortraitLoader.load(portrait, screen: PortraitLoader.deviceScreen, fetch: local)?.image
            }
    }

    /// The capital letters that start the words of a name, at most two.
    static func initials(of name: String) -> String {
        String(name.split(separator: " ").compactMap { $0.first.flatMap { $0.isUppercase ? $0 : nil } }.prefix(2))
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
                        Text(composer.works.count.localized())
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
        .pageTitle(L("Composers"))
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
        .pageTitle(L("Favourites"))
    }
}

extension LibraryPage.Favourites {
    /// The ids of every favourite, in order: the page changes when one of them does.
    fileprivate var signature: [String] {
        composers.map(\.id) + performers.map(\.id) + albums.map(\.id) + works.map(\.id) + recordings.map(\.id)
    }
}
