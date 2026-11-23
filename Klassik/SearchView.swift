import SwiftUI

/// The Search place: one field at the top under the back arrow, no large title, and the
/// results in sections under it. Only the results scroll. Filters beside the field opens the conditions in a sheet;
/// the results stay live above it.
/// The field is drawn here, not by `searchable`: in a `UISearchTab` the system moves that field to the bottom of
/// the screen, onto the keyboard.
struct SearchView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppNavigator.self) private var navigator
    @State private var text = ""
    @State private var conditions: [Search.Condition] = []
    /// The condition that the next term of the sheet joins with "or".
    @State private var joining: Int?
    @State private var showsFilters = false
    @State private var returnsAfterFilters = false
    @FocusState private var focused: Bool
    /// The start that the page last handled.
    @State private var started: Int?
    @State private var live = LiveSearch()

    private var recent: RecentSearches { model.recentSearches }

    /// Keeps what the session searched as its recent search.
    private func commit() {
        recent.commit(text: text, conditions: RecentSearch.terms(of: conditions))
    }

    var body: some View {
        let typed = !text.trimmingCharacters(in: .whitespaces).isEmpty
        let found = typed ? live.results : nil
        let filtered =
            conditions.isEmpty
            ? Search.Filtered(results: found ?? Search.Results())
            : model.library.searchFilters.narrow(found, by: conditions)
        // While a search runs, the page keeps the last results; an empty result is no match only when it is current.
        let settled = !typed || live.isShowing(text)
        PageList {
            // A search of conditions only shows results; the recent list belongs to an empty search.
            if !typed && conditions.isEmpty {
                // Klassik shows no suggestions: it knows no content that the listener does not.
                if !recent.entries.isEmpty {
                    RecentList(recent: recent) { entry in
                        text = entry.text
                        conditions = entry.searchConditions
                        joining = nil
                        focused = false
                        recent.restore(entry)
                    }
                }
                Section {
                    if recent.entries.isEmpty {
                        Text("Type a work, a catalogue number such as Op. 67 or K. 626, or a name.")
                            .typeStyle(.subheadline)
                            .foregroundStyle(Palette.textSecondary)
                            .listRowSeparator(.hidden)
                            .pageEdges(top: Layout.searchHintTop, bottom: Layout.rowPadding)
                            .accessibilityIdentifier("search-hint")
                    }
                }
            } else if filtered.results.isEmpty && settled {
                Text("No work, name or album matches.")
                    .typeStyle(.subheadline)
                    .foregroundStyle(Palette.textSecondary)
                    .listRowSeparator(.hidden)
                    .pageEdges(top: Layout.searchNoMatchTop)
                    .accessibilityIdentifier("search-no-match")
            } else if !filtered.results.isEmpty {
                SearchResults(results: filtered.results, matching: filtered.matching)
            }
        }
        .navigationTitle(Place.search.title)
        .navigationBarTitleDisplayMode(.inline)
        .environment(\.pageHeading, "")
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack(spacing: Layout.searchRowGap) {
                SearchField(text: $text, focused: $focused, submit: commit)
                FiltersButton(conditions: showsFilters ? 0 : conditions.count, isOpen: showsFilters) {
                    // The keyboard goes down as the sheet rises; the sheet never rides on the search keyboard.
                    focused = false
                    showsFilters.toggle()
                }
                RoundButton(
                    symbol: "xmark", icon: Layout.searchResetIcon, label: "Clear search and filters",
                    identifier: "search-reset", isEnabled: !text.isEmpty || !conditions.isEmpty
                ) {
                    // The x pill ends the session: the next search is a new entry.
                    commit()
                    recent.endSession()
                    text = ""
                    conditions = []
                    joining = nil
                }
            }
            .pagePadding()
            .padding(.bottom, Layout.searchRowBottom)
            .background(Palette.backgroundPage)
        }
        .scrollDismissesKeyboard(.immediately)
        .sheet(
            isPresented: $showsFilters,
            onDismiss: {
                if returnsAfterFilters {
                    returnsAfterFilters = false
                    navigator.back()
                }
            }
        ) {
            FilterSheet(
                conditions: $conditions, joining: $joining, pool: pool(of: found), hasText: typed, done: commit,
                back: {
                    commit()
                    returnsAfterFilters = true
                    showsFilters = false
                })
        }
        .onAppear(perform: start)
        .onChange(of: navigator.searchStarts, start)
        // Opening a result and leaving the page commit the search of the session.
        .onChange(of: navigator.pages(in: .search).count) { before, after in
            showsFilters = false
            if after > before { commit() }
        }
        .onChange(of: navigator.selection) { before, _ in
            if before == .search {
                commit()
                showsFilters = false
            }
        }
        .onDisappear { showsFilters = false }
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

    /// The recordings that the text found. The sheet counts only these.
    private func pool(of found: Search.Results?) -> Search.Pool {
        model.library.searchFilters.pool(of: found)
    }

    /// A tab or a link opens Search empty, with the keyboard up, as the system Search tab does. The root appears
    /// again after Back from a result; that arrival is no new start, so the search stays.
    private func start() {
        guard navigator.searchStarts != started else { return }
        started = navigator.searchStarts
        commit()
        recent.endSession()
        text = ""
        conditions = []
        joining = nil
        showsFilters = false
        focused = navigator.selection == .search
    }
}

/// A round button beside the field, as search.html .fieldrow .roundglass draws it.
private struct RoundButton: View {
    let symbol: String
    let icon: CGFloat
    let label: String
    let identifier: String
    var isEnabled = true
    var isOn = false
    let action: () -> Void
    @ScaledMetric(relativeTo: .body) private var size = Layout.searchButton

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .resizable()
                .scaledToFit()
                .fontWeight(.semibold)
                .frame(width: icon * size / Layout.searchButton, height: icon * size / Layout.searchButton)
                .foregroundStyle(isEnabled ? (isOn ? Palette.tint : Palette.textPrimary) : Palette.textTertiary)
                .frame(width: size, height: size)
                .background(Palette.fillQuiet, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(FlatPress())
        // The x pill stays in place when there is nothing to clear, so the field never changes width.
        .disabled(!isEnabled)
        .accessibilityLabel(label)
        .accessibilityIdentifier(identifier)
    }
}

/// Filters, with a badge that counts the conditions while the sheet is closed.
private struct FiltersButton: View {
    let conditions: Int
    let isOpen: Bool
    let action: () -> Void
    @ScaledMetric(relativeTo: .caption) private var badge = Layout.badgeSize

    var body: some View {
        RoundButton(
            symbol: "line.3.horizontal.decrease", icon: Layout.searchButtonIcon, label: "Filters",
            identifier: "search-filters", isOn: isOpen, action: action
        )
        .overlay(alignment: .topTrailing) {
            if conditions > 0 {
                Text(conditions.formatted())
                    .typeStyle(.caption1)
                    .fontWeight(.semibold)
                    .monospacedDigit()
                    .foregroundStyle(Palette.onAccent)
                    .padding(.horizontal, Layout.badgePadding)
                    .frame(minWidth: badge, minHeight: badge)
                    .background(Palette.accentFill, in: Capsule())
                    .offset(x: -Layout.badgeOffset, y: Layout.badgeOffset)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityValue(conditions > 0 ? WorkIndex.Recording.count(conditions, "condition") : "")
    }
}

/// The field row of search.html: a magnifier, the text and a clear button that clears the text only.
/// Search pages need a field under the title. The Search tab moves `searchable` to the bottom.
struct SearchField: View {
    @Binding var text: String
    var focused: FocusState<Bool>.Binding
    var submit: () -> Void = {}
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
                .onSubmit {
                    focused.wrappedValue = false
                    submit()
                }
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
    }
}

/// The recent searches of the empty page, newest first, each with its text and its conditions, and Clear
///. A tap restores the search.
private struct RecentList: View {
    let recent: RecentSearches
    let restore: (RecentSearch) -> Void
    @ScaledMetric(space: .inGroup) private var gap: CGFloat
    @ScaledMetric(relativeTo: .body) private var icon = Layout.searchRecentIcon

    var body: some View {
        let entries = recent.entries
        Section {
            HStack(alignment: .firstTextBaseline) {
                Text("Recent")
                    .typeStyle(Layout.sectionHeading)
                    .foregroundStyle(Palette.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                Button("Clear") { recent.clear() }
                    .typeStyle(Layout.sectionHeading)
                    .foregroundStyle(Palette.tint)
                    // A row of a list sends a tap anywhere on it to a bordered button.
                    .buttonStyle(.borderless)
                    .accessibilityIdentifier("search-recent-clear")
            }
            .pageSectionHeader(true)
            ForEach(entries) { entry in
                Button {
                    restore(entry)
                } label: {
                    HStack(spacing: Layout.rowGap) {
                        // A search of conditions only shows the filter symbol, as its line names no text.
                        Image(systemName: entry.text.isEmpty ? "line.3.horizontal.decrease" : "magnifyingglass")
                            .resizable()
                            .scaledToFit()
                            .frame(width: icon, height: icon)
                            .foregroundStyle(Palette.textSecondary)
                            .accessibilityHidden(true)
                        lines(entry)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("search-recent")
                .itemSeparator(first: entry.id == entries.first?.id, last: entry.id == entries.last?.id)
            }
        }
    }

    private func lines(_ entry: RecentSearch) -> some View {
        VStack(alignment: .leading, spacing: gap) {
            if !entry.text.isEmpty {
                Text(entry.text).typeStyle(.body)
            }
            if !entry.conditions.isEmpty {
                Text(entry.conditionLine)
                    .typeStyle(entry.text.isEmpty ? .body : .subheadline)
                    .foregroundStyle(entry.text.isEmpty ? Palette.textPrimary : Palette.textSecondary)
            }
        }
        .ink()
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Composers, performers, works, then albums, each in its own section. A recording shows only inside its
/// work, so Albums holds only albums.
private struct SearchResults: View {
    @Environment(AppModel.self) private var model
    let results: Search.Results
    /// The recordings of each work that pass the conditions. Empty without conditions.
    let matching: [String: Int]
    @ScaledMetric(space: .inGroup) private var gap: CGFloat

    var body: some View {
        let playing = model.playback.item
        people(results.composers, title: "Composers")
        people(results.performers, title: "Performers")
        if !results.works.isEmpty {
            Section {
                CountedHeading("Works", count: results.works.count)
                ForEach(results.works) { work in
                    NavigationLink(value: Page.work(work.id)) {
                        let total = WorkIndex.Recording.count(work.recordings.count, "recording")
                        let recordings = matching[work.id].map { "\($0) of \(total) match" } ?? total
                        lines(
                            title: work.title, isFavourite: model.recordingOrder.isFavourite(work),
                            detail: "\(work.composer), \(recordings)", track: results.workTracks[work.id],
                            nickname: results.workNicknames[work.id])
                    }
                    .playingRow(playing?.work.id == work.id)
                    .accessibilityIdentifier("search-work")
                    .itemSeparator(first: work.id == results.works.first?.id, last: work.id == results.works.last?.id)
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
                                    .joined(separator: ", "),
                                track: results.albumTracks[album.id])
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

    @ViewBuilder
    private func people(_ people: [Search.Person], title: String) -> some View {
        if !people.isEmpty {
            Section {
                CountedHeading(title, count: people.count)
                ForEach(people) { person in
                    PersonPageLink(page: person.composes ? .composer(person.name) : .performer(person.name)) {
                        lines(
                            title: person.name, isFavourite: model.recordingOrder.isFavourite(person: person.name),
                            detail: person.counts())
                    }
                    .accessibilityIdentifier("search-person")
                    .itemSeparator(first: person.id == people.first?.id, last: person.id == people.last?.id)
                }
            }
        }
    }

    /// `track` is the track title that found the result when its own words do not match (search.html `.why`).
    /// `nickname` is the nickname that found a work whose title does not match.
    private func lines(
        title: String, isFavourite: Bool, detail: String, track: String? = nil, nickname: String? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: gap) {
            MarkedTitle(title: title, isFavourite: isFavourite)
                .ink()
            if !detail.isEmpty {
                Text(detail)
                    .typeStyle(.subheadline)
                    .foregroundStyle(Palette.textSecondary)
            }
            if let track {
                Text("Track: \(track)")
                    .typeStyle(.subheadline)
                    .foregroundStyle(Palette.textSecondary)
            }
            if let nickname {
                Text("Nickname: \(nickname)")
                    .typeStyle(.subheadline)
                    .foregroundStyle(Palette.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
