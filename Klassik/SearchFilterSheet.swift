import SwiftUI

/// The conditions of a search in the shared half-height sheet frame: the conditions as one paragraph of chips, the
/// kind picker and the find field pinned under the header, and the terms. Each term shows what a tap does.
struct FilterSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Binding var conditions: [Search.Condition]
    /// The condition that the next term joins with "or".
    @Binding var joining: Int?
    /// The recordings that the text found. The term counts use only these.
    let pool: Search.Pool
    /// The rows of the page, or nil while the page has no search to count.
    let results: Int?
    /// Done keeps the search as a recent search.
    let done: () -> Void
    @State private var scope: Search.Scope = .composers
    @State private var narrowing = ""
    @FocusState private var narrowFocused: Bool

    var body: some View {
        let choices = model.library.searchFilters.choices(
            in: scope, conditions: conditions, joining: joining, narrowing: narrowing, pool: pool)
        SheetFrame(
            title: "Filters", count: count, done: finish, identifier: "filter"
        ) {
            if !conditions.isEmpty {
                ChipParagraph(
                    paragraph: ConditionParagraph(conditions: conditions, joining: joining),
                    remove: { remove($1, from: $0) },
                    toggle: { joining = joining == $0 ? nil : $0 }
                )
                .accessibilityIdentifier("filter-conditions")
            }
            Section {
                if choices.isEmpty && model.library.hasSearchFilters {
                    Text("No term of this kind is left.")
                        .typeStyle(.subheadline)
                        .foregroundStyle(Palette.textSecondary)
                        .frame(minHeight: Measure.hitTarget)
                        .accessibilityIdentifier("filter-none")
                }
                ForEach(choices) { choice in
                    TermRow(choice: choice) { pick(choice) }
                    Divider()
                }
            } header: {
                VStack(spacing: 0) {
                    PageTabs(tabs: Search.Scope.allCases, title: \.title, selection: $scope, style: .kinds)
                        .accessibilityIdentifier("filter-scopes")
                        .padding(.bottom, Layout.filterKindsBottom)
                    NarrowField(text: $narrowing, scope: scope, focused: $narrowFocused)
                }
                .padding(.top, Layout.frameStickTop)
                .padding(.bottom, Layout.frameStickBottom)
                .frame(maxWidth: .infinity)
                .background(Palette.backgroundGrouped)
            }
        }
        .onChange(of: scope) { narrowing = "" }
        .sheetFrame()
        .presentationBackgroundInteraction(.disabled)
    }

    private var count: String {
        guard let results, model.library.hasSearchFilters else { return "" }
        return WorkIndex.Recording.count(results, "result")
    }

    private func finish() {
        done()
        dismiss()
    }

    /// A pick clears the narrowing field, so the next term can be typed at once.
    private func pick(_ choice: Search.Choice) {
        narrowing = ""
        switch choice.effect {
        case .start, .and:
            conditions.append(Search.Condition(terms: [choice.term]))
            joining = nil
        case .or:
            guard let open = joining, conditions.indices.contains(open) else { return }
            conditions[open].terms.append(choice.term)
        case .check:
            guard let position = conditions.firstIndex(where: { $0.terms.contains(choice.term) }) else { return }
            remove(choice.term, from: position)
        }
    }

    private func remove(_ term: Search.Term, from position: Int) {
        guard conditions.indices.contains(position) else { return }
        conditions[position].terms.removeAll { $0 == term }
        guard conditions[position].terms.isEmpty else { return }
        conditions.remove(at: position)
        if joining == position {
            joining = nil
        } else if let open = joining, open > position {
            joining = open - 1
        }
    }
}

/// A term with the recordings that remain after a tap, or a check when the term is in use.
private struct TermRow: View {
    let choice: Search.Choice
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Layout.trailGap) {
                Text(choice.term.name)
                    .typeStyle(.body)
                    .foregroundStyle(Palette.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if choice.effect == .check {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Palette.tint)
                        .accessibilityHidden(true)
                }
                Text(choice.count.localized())
                    .typeStyle(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(Palette.textSecondary)
            }
            .frame(minHeight: Measure.hitTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(FlatPress())
        .accessibilityAddTraits(choice.effect == .check ? .isSelected : [])
        .accessibilityIdentifier("filter-term")
    }
}

/// The field that narrows the terms of one scope.
private struct NarrowField: View {
    @Binding var text: String
    let scope: Search.Scope
    var focused: FocusState<Bool>.Binding
    @ScaledMetric(relativeTo: .body) private var height = Layout.narrowHeight
    @ScaledMetric(relativeTo: .body) private var icon = Layout.narrowIcon

    var body: some View {
        HStack(spacing: Layout.narrowGap) {
            Image(systemName: "magnifyingglass")
                .resizable()
                .scaledToFit()
                .frame(width: icon, height: icon)
                .foregroundStyle(Palette.textSecondary)
                .accessibilityHidden(true)
            TextField(scope.findPrompt, text: $text)
                .typeStyle(.body)
                .foregroundStyle(Palette.textPrimary)
                .focused(focused)
                .submitLabel(.done)
                .onSubmit { focused.wrappedValue = false }
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .accessibilityIdentifier("filter-narrow")
        }
        .padding(.horizontal, Layout.narrowInset)
        .frame(minHeight: height)
        .background(Palette.fillQuiet, in: RoundedRectangle(cornerRadius: Layout.narrowCorner))
    }
}
