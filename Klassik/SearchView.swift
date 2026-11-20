import SwiftUI

/// The Search place (ADR 0025, 0029, 0057): one field at the top under the back arrow, no large title, and the
/// results in sections under it. Only the results scroll.
/// The field is drawn here, not by `searchable`: in a `UISearchTab` the system moves that field to the bottom of
/// the screen, onto the keyboard.
struct SearchView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppNavigator.self) private var navigator
    @State private var text = ""
    @FocusState private var focused: Bool
    /// The start that the page last handled.
    @State private var started: Int?
    @State private var live = LiveSearch()

    var body: some View {
        let typed = !text.trimmingCharacters(in: .whitespaces).isEmpty
        let results = typed ? live.results : Search.Results()
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
            } else if results.isEmpty && live.isShowing(text) {
                Text("No work, name or album matches.")
                    .typeStyle(.subheadline)
                    .foregroundStyle(Palette.textSecondary)
                    .listRowSeparator(.hidden)
                    .pageEdges(top: Layout.searchNoMatchTop)
                    .accessibilityIdentifier("search-no-match")
            } else if !results.isEmpty {
                SearchResults(results: results)
            }
        }
        .navigationTitle(Place.search.title)
        .navigationBarTitleDisplayMode(.inline)
        .environment(\.pageHeading, "")
        .safeAreaInset(edge: .top, spacing: 0) {
            SearchField(text: $text, focused: $focused)
        }
        .scrollDismissesKeyboard(.immediately)
        .onAppear(perform: start)
        .onChange(of: navigator.searchStarts, start)
        .task(id: Query(text: text, version: model.library.indexVersion)) {
            let library = model.library
            await live.show(text, version: library.indexVersion) { await library.results(for: $0) }
        }
    }

    /// A search runs again when the text or the index changes.
    private struct Query: Equatable {
        var text: String
        var version: Int
    }

    /// A tab or a link opens Search empty, with the keyboard up, as the system Search tab does. The root appears
    /// again after Back from a result; that arrival is no new start, so the search stays (ADR 0029).
    private func start() {
        guard navigator.searchStarts != started else { return }
        started = navigator.searchStarts
        text = ""
        focused = navigator.selection == .search
    }
}

/// The field row of search.html: a magnifier, the text and a clear button that clears the text only.
/// A page sets it as its top safe-area inset; `searchable` would put a second field into the Search tab.
struct SearchField: View {
    @Binding var text: String
    var focused: FocusState<Bool>.Binding
    var prompt = "Work or name"
    var identifier = "search-field"
    @ScaledMetric(relativeTo: .body) private var height = Layout.searchFieldHeight
    @ScaledMetric(relativeTo: .body) private var icon = Layout.searchFieldIcon

    var body: some View {
        HStack(spacing: Layout.searchFieldGap) {
            Image(systemName: "magnifyingglass")
                .resizable()
                .scaledToFit()
                .frame(width: icon, height: icon)
                .foregroundStyle(Palette.textSecondary)
                .accessibilityHidden(true)
            TextField(prompt, text: $text)
                .typeStyle(.body)
                .foregroundStyle(Palette.textPrimary)
                .focused(focused)
                .submitLabel(.search)
                .onSubmit { focused.wrappedValue = false }
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .accessibilityIdentifier(identifier)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Palette.textSecondary)
                }
                .buttonStyle(FlatPress())
                .accessibilityLabel("Clear")
                .accessibilityIdentifier("search-clear")
            }
        }
        .padding(.leading, Layout.searchFieldLeading)
        .padding(.trailing, Layout.searchFieldTrailing)
        .frame(minHeight: height)
        .background(Palette.fillQuiet, in: RoundedRectangle(cornerRadius: Layout.searchFieldCorner))
        .pagePadding()
        .padding(.bottom, Layout.searchRowBottom)
        .background(Palette.backgroundPage)
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
