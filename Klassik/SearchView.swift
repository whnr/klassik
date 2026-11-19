import SwiftUI

/// The Search place (ADR 0025, 0029, 0057): one field at the top under the back arrow, no large title, and the
/// results in sections under it. Only the results scroll.
struct SearchView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppNavigator.self) private var navigator
    @State private var text = ""

    var body: some View {
        let typed = !text.trimmingCharacters(in: .whitespaces).isEmpty
        let results = typed ? model.library.search.results(for: text) : Search.Results()
        PageList {
            if !typed {
                Section {
                    Text("Type a work, a catalogue number such as Op. 67 or K. 626, or a name.")
                        .typeStyle(.subheadline)
                        .foregroundStyle(Palette.textSecondary)
                        .listRowSeparator(.hidden)
                        .pageEdges(top: Layout.searchHintTop, bottom: Layout.rowPadding)
                        .accessibilityIdentifier("search-hint")
                    // The performer list has no other way in. The results find a single performer by name.
                    NavigationLink(value: Page.performers) {
                        LabeledContent("Performers", value: model.library.index.performers.count.formatted())
                            .ink()
                    }
                    .accessibilityIdentifier("performers")
                    .listRowSeparator(.hidden)
                }
            } else if results.isEmpty {
                Text("No work, name or album matches.")
                    .typeStyle(.subheadline)
                    .foregroundStyle(Palette.textSecondary)
                    .listRowSeparator(.hidden)
                    .pageEdges(top: Layout.searchNoMatchTop)
                    .accessibilityIdentifier("search-no-match")
            } else {
                SearchResults(results: results)
            }
        }
        .navigationTitle(Place.search.title)
        .navigationBarTitleDisplayMode(.inline)
        .environment(\.pageHeading, "")
        .searchable(text: $text, placement: .navigationBarDrawer(displayMode: .always), prompt: "Work or name")
        // The back arrow stays above the field while the listener types.
        .searchPresentationToolbarBehavior(.avoidHidingContent)
        .scrollDismissesKeyboard(.immediately)
        .autocorrectionDisabled()
        .textInputAutocapitalization(.never)
        .onChange(of: navigator.searchStarts) { text = "" }
    }
}

/// The sections of the results: works, then composers and performers, then albums (search.html).
private struct SearchResults: View {
    @Environment(AppModel.self) private var model
    let results: Search.Results
    @ScaledMetric(space: .inGroup) private var gap: CGFloat

    var body: some View {
        let playing = model.playback.item
        if !results.works.isEmpty {
            Section {
                CountedHeading("Works", count: results.works.count)
                ForEach(results.works) { work in
                    NavigationLink(value: Page.work(work.id)) {
                        let recordings = WorkIndex.Recording.count(work.recordings.count, "recording")
                        lines(
                            title: work.title, isFavourite: model.recordingOrder.isFavourite(work),
                            detail: "\(work.composer), \(recordings)")
                    }
                    .playingRow(playing?.work.id == work.id)
                    .accessibilityIdentifier("search-work")
                    .itemSeparator(first: work.id == results.works.first?.id, last: work.id == results.works.last?.id)
                }
            }
        }
        if !results.people.isEmpty {
            Section {
                CountedHeading("Composers and performers", count: results.people.count)
                ForEach(results.people) { person in
                    PersonPageLink(page: person.composes ? .composer(person.name) : .performer(person.name)) {
                        lines(
                            title: person.name, isFavourite: model.recordingOrder.isFavourite(person: person.name),
                            detail: person.counts())
                    }
                    .accessibilityIdentifier("search-person")
                    .itemSeparator(
                        first: person.id == results.people.first?.id, last: person.id == results.people.last?.id)
                }
            }
        }
        if !results.albums.isEmpty {
            Section {
                CountedHeading("Albums", count: results.albums.count)
                ForEach(results.albums) { album in
                    NavigationLink(value: Page.album(album.id)) {
                        HStack(spacing: Layout.rowGap) {
                            CoverImage(song: album.tracks.first, points: Layout.rowCover)
                                .frame(width: Layout.rowCover, height: Layout.rowCover)
                                .clipShape(.rect(cornerRadius: Layout.coverCorner))
                                .accessibilityHidden(true)
                            lines(
                                title: album.title, isFavourite: model.recordingOrder.isFavourite(album: album.id),
                                detail: [Search.artist(of: album), album.year.map(String.init)].compactMap { $0 }
                                    .joined(separator: ", "))
                        }
                    }
                    .playingRow(playing?.recording.albumKey.map { album.keys.contains($0) } ?? false)
                    .accessibilityIdentifier("search-album")
                    .itemSeparator(
                        first: album.id == results.albums.first?.id, last: album.id == results.albums.last?.id)
                }
            }
        }
    }

    private func lines(title: String, isFavourite: Bool, detail: String) -> some View {
        VStack(alignment: .leading, spacing: gap) {
            MarkedTitle(title: title, isFavourite: isFavourite)
                .ink()
            if !detail.isEmpty {
                Text(detail)
                    .typeStyle(.subheadline)
                    .foregroundStyle(Palette.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
