import SwiftUI

extension WorkIndex {
    /// The albums that name the performer, newest first. Albums without a year come last, then by title.
    func albums(ofPerformer name: String) -> [Album] {
        albums.filter { $0.recording.performerNames.contains(name) }
            .sorted {
                switch ($0.year, $1.year) {
                case (let a?, let b?) where a != b: return a > b
                case (nil, _?): return false
                case (_?, nil): return true
                default: return $0.title.localizedStandardCompare($1.title) == .orderedAscending
                }
            }
    }

    /// The roles that the tags give the performer on their recordings, such as "Conductor", in role order.
    func roles(ofPerformer performer: Performer) -> [String] {
        var found: [(kind: Roles.Kind, label: String)] = []
        for entry in performer.entries {
            for line in entry.recording.principalNames where line.names.contains(performer.name) {
                if !found.contains(where: { $0.label == line.label }) { found.append((line.kind, line.label)) }
            }
        }
        return found.sorted { $0.kind < $1.kind }.map { $0.label.prefix(1).uppercased() + $0.label.dropFirst() }
    }
}

/// A performer as a person, with the layout of the composer page: a picture, the name, a description line, and
/// the tabs Albums and About (ADR 0017, 0019). Wikidata may know nobody: the page then shows the tags only.
struct PerformerPage: View {
    enum Tab: Hashable {
        case albums, about
    }

    @Environment(AppModel.self) private var model
    let performer: WorkIndex.Performer
    @State private var tab = Tab.albums

    var body: some View {
        let people = model.people
        let facts = people.facts(ofPerformer: performer.name)
        let index = model.library.index
        let albums = index.albums(ofPerformer: performer.name)
        let roles = index.roles(ofPerformer: performer)
        PersonPageList { proxy in
            PersonHero(
                name: performer.name, facts: facts, line: Self.line(facts: facts, roles: roles),
                kind: "performer", topInset: proxy.safeAreaInsets.top, width: proxy.size.width
            )
            .listRowInsets(EdgeInsets())
            .listRowSeparator(.hidden)
            BackTipRow()
            PageTabs(tabs: [Tab.albums, .about], title: { $0 == .albums ? "Albums" : "About" }, selection: $tab)
                .pageEdges(top: Layout.segmentedTop)
                .listRowSeparator(.hidden)
                .accessibilityIdentifier("performer-tabs")
            switch tab {
            case .albums: albumsTab(albums)
            case .about: aboutTab(facts)
            }
        }
        .navigationTitle(performer.name)
        .navigationBarTitleDisplayMode(.inline)
        .task { await people.resolve(performer: performer.name) }
        // A person page puts all its covers in front of the cover queue (ADR 0059).
        .onAppear { model.albumCovers.prefer(albums.compactMap(\.tracks.first)) }
    }

    /// The Wikidata description with the years. The tag roles stand in only when Wikidata has no description.
    nonisolated static func line(facts: PersonFacts?, roles: [String]) -> String? {
        guard let facts else { return nil }
        if facts.description?.isEmpty == false { return facts.descriptionLine }
        let line = [roles.formatted(.list(type: .and, width: .narrow)), facts.years].compactMap { $0 }
            .filter { !$0.isEmpty }.joined(separator: ", ")
        return line.isEmpty ? nil : line
    }

    @ViewBuilder private func albumsTab(_ albums: [WorkIndex.Album]) -> some View {
        if albums.isEmpty {
            Text("No albums name this performer.")
                .foregroundStyle(Palette.textSecondary)
                .listRowSeparator(.hidden)
        } else {
            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: Layout.albumColumnGap), GridItem(.flexible())],
                alignment: .leading, spacing: Layout.albumRowGap
            ) {
                ForEach(albums) { AlbumCover(album: $0) }
            }
            // person.html: the grid is a .section, which keeps the section gap above it.
            .pageEdges(top: Layout.sectionTop)
            .listRowSeparator(.hidden)
        }
    }

    private func aboutTab(_ facts: PersonFacts?) -> some View {
        PersonAbout(facts: facts, kind: "performer") {
            LabeledContent("Name in your tags", value: performer.name)
                .ink()
                .itemSeparator(first: true, last: false)
            LabeledContent("Recordings", value: performer.entries.count.formatted())
                .ink()
                .itemSeparator(first: false, last: true)
        }
    }
}

/// A cover with the album title and year. It opens the album page.
/// The grid is one list row, and a row with several links follows all of them on one tap. So each cover is a
/// button that pushes its own page.
private struct AlbumCover: View {
    @Environment(AppNavigator.self) private var navigator
    let album: WorkIndex.Album

    var body: some View {
        Button {
            navigator.open(.album(album.id), in: navigator.selection)
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                CoverImage(song: album.tracks.first, points: 160)
                    .clipShape(RoundedRectangle(cornerRadius: Layout.albumCorner))
                Text(album.title)
                    .typeStyle(.subheadline)
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(2)
                    .padding(.top, Layout.albumTitleGap)
                if let year = album.year {
                    Text(year.formatted(.number.grouping(.never)))
                        .typeStyle(.footnote)
                        .foregroundStyle(Palette.textSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("performer-album")
    }
}
