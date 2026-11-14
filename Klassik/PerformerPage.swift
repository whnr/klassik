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
        GeometryReader { proxy in
            List {
                PersonHero(
                    name: performer.name, facts: facts, line: Self.line(facts: facts, roles: roles),
                    kind: "performer", topInset: proxy.safeAreaInsets.top, width: proxy.size.width
                )
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                BackTipRow()
                Section {
                    Picker("Show", selection: $tab) {
                        Text("Albums").tag(Tab.albums)
                        Text("About").tag(Tab.about)
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("performer-tabs")
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                switch tab {
                case .albums: albumsTab(albums)
                case .about: aboutTab(facts)
                }
            }
            .grounds()
            .ignoresSafeArea(.container, edges: .top)
        }
        .navigationTitle(performer.name)
        .navigationBarTitleDisplayMode(.inline)
        .task { await people.resolve(performer: performer.name) }
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
                .listRowBackground(Color.clear)
        } else {
            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: Space.m.points), GridItem(.flexible())],
                alignment: .leading, spacing: Space.l.points
            ) {
                ForEach(albums) { AlbumCover(album: $0) }
            }
            .listRowInsets(EdgeInsets(top: 0, leading: Space.l.points, bottom: 0, trailing: Space.l.points))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
        }
    }

    @ViewBuilder private func aboutTab(_ facts: PersonFacts?) -> some View {
        if let facts {
            if let bio = facts.bio {
                Section {
                    Text(bio)
                        .ink()
                        .accessibilityIdentifier("performer-bio")
                } header: {
                    SectionHeading("Biography")
                }
                .listRowBackground(Palette.backgroundRow.color)
            }
            if !facts.credits.isEmpty {
                Section {
                    ForEach(facts.credits, id: \.self) { CreditRow(credit: $0) }
                } header: {
                    SectionHeading("Credits")
                }
                .listRowBackground(Palette.backgroundRow.color)
            }
        } else {
            Section {
                Text("Wikidata has no facts for this performer. Klassik shows your tags.")
                    .foregroundStyle(Palette.textSecondary)
            }
            .listRowBackground(Palette.backgroundRow.color)
        }
        Section {
            LabeledContent("Name in your tags", value: performer.name)
                .ink()
            LabeledContent("Recordings", value: performer.entries.count.formatted())
                .ink()
        } header: {
            SectionHeading("Your tags")
        }
        .listRowBackground(Palette.backgroundRow.color)
    }
}

/// A cover with the album title and year. It opens the album page.
private struct AlbumCover: View {
    let album: WorkIndex.Album

    var body: some View {
        NavigationLink(value: Page.album(album.id)) {
            VStack(alignment: .leading, spacing: Space.xs.points) {
                CoverImage(id: album.tracks.first?.coverArt, points: 160)
                    .aspectRatio(1, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.m))
                Text(album.title)
                    .typeStyle(.subheadline)
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(2)
                if let year = album.year {
                    Text(year.formatted(.number.grouping(.never)))
                        .typeStyle(.footnote)
                        .foregroundStyle(Palette.textSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        // A link in a list row adds a chevron; the cover is the whole row.
        .navigationLinkIndicatorVisibility(.hidden)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("performer-album")
    }
}
