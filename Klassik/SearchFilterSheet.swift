import SwiftUI

/// The conditions of a search in a modal sheet at the medium detent.
/// Each scope has a narrowing field; each term shows what a tap does.
struct FilterSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Binding var conditions: [Search.Condition]
    /// The condition that the next term joins with "or".
    @Binding var joining: Int?
    /// The recordings that the text found. The counts use only these.
    let pool: Search.Pool
    /// True when the search has a text, so the heading shows the recordings that remain.
    let hasText: Bool
    /// Done keeps the search as a recent search.
    let done: () -> Void
    let back: () -> Void
    @State private var scope: Search.Scope = .composers
    @State private var narrowing = ""
    @FocusState private var narrowFocused: Bool

    init(
        conditions: Binding<[Search.Condition]>, joining: Binding<Int?>, pool: Search.Pool, hasText: Bool,
        done: @escaping () -> Void, back: @escaping () -> Void
    ) {
        _conditions = conditions
        _joining = joining
        self.pool = pool
        self.hasText = hasText
        self.done = done
        self.back = back
    }

    var body: some View {
        let filters = model.library.searchFilters
        let choices = filters.choices(
            in: scope, conditions: conditions, joining: joining, narrowing: narrowing, pool: pool)
        List {
            ForEach(Array(conditions.enumerated()), id: \.offset) { position, condition in
                Section {
                    ConditionRow(
                        condition: condition, count: filters.count(Array(conditions.prefix(position + 1)), in: pool),
                        isJoining: joining == position,
                        toggle: { joining = joining == position ? nil : position },
                        remove: { remove($0, from: position) })
                } header: {
                    if position > 0 {
                        Text("and")
                            .typeStyle(.footnote)
                            .foregroundStyle(Palette.textSecondary)
                            .textCase(nil)
                    }
                }
            }
            // The note, the kinds and the field start under Back, at the shared inset.
            Section {
                Text(note)
                    .typeStyle(.footnote)
                    .foregroundStyle(Palette.textSecondary)
                    .accessibilityIdentifier("filter-note")
                    .listRowInsets(EdgeInsets())
                PageTabs(tabs: Search.Scope.allCases, title: \.title, selection: $scope, style: .kinds)
                    .accessibilityIdentifier("filter-scopes")
                    .listRowInsets(
                        EdgeInsets(
                            top: Layout.filterKindsTop, leading: 0, bottom: Layout.filterKindsBottom, trailing: 0))
                NarrowField(text: $narrowing, scope: scope, focused: $narrowFocused)
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: Layout.narrowBottom, trailing: 0))
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listSectionSpacing(0)
            // The terms are rows of one plain list on the sheet ground, with hairlines across the list.
            Section {
                if choices.isEmpty {
                    Text("No term of this kind is left.")
                        .typeStyle(.subheadline)
                        .foregroundStyle(Palette.textSecondary)
                        .accessibilityIdentifier("filter-none")
                        .termRow()
                }
                ForEach(choices) { choice in
                    TermRow(choice: choice) { pick(choice) }
                        .termRow()
                }
            }
            .listRowBackground(Color.clear)
        }
        .grounds()
        .contentMargins(.horizontal, Layout.filterHeadInset, for: .scrollContent)
        // The note follows the head directly, with no top padding.
        .contentMargins(.top, 0, for: .scrollContent)
        .environment(\.defaultMinListRowHeight, 0)
        .environment(\.defaultMinListHeaderHeight, 0)
        .safeAreaInset(edge: .top, spacing: 0) {
            head(total: filters.count(conditions, in: pool))
        }
        .onChange(of: scope) { narrowing = "" }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .presentationBackgroundInteraction(.disabled)
        .presentationBackground(Palette.backgroundGrouped)
    }

    /// The title, the recordings that remain, and Done.
    private func head(total: Int) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Layout.filterHeadGap) {
            Button("Back", action: back)
                .typeStyle(.body)
                .accessibilityIdentifier("filter-back")
            Text("Filters")
                .typeStyle(.headline)
                .foregroundStyle(Palette.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityAddTraits(.isHeader)
            if hasText || !conditions.isEmpty {
                Text(WorkIndex.Recording.count(total, "recording"))
                    .typeStyle(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(Palette.textSecondary)
                    .accessibilityIdentifier("filter-total")
            }
            Button("Done") {
                done()
                dismiss()
            }
            .typeStyle(.body)
            .accessibilityIdentifier("filter-done")
        }
        // The system grabber sits above the head, as the specimen `.grabber` does.
        .padding(.top, Layout.sheetGrabberTop + Layout.sheetGrabberHeight + Layout.filterHeadTop)
        .padding(.bottom, Layout.filterHeadBottom)
        .padding(.horizontal, Layout.filterHeadInset)
        .background(Palette.backgroundGrouped)
    }

    private var note: String {
        if conditions.isEmpty { return "Pick a term to start a condition." }
        if joining != nil { return "A tap adds the term with \u{201C}or\u{201D} to the marked condition." }
        return "A tap adds a new condition with \u{201C}and\u{201D}. \u{201C}or +\u{201D} on a condition adds the next"
            + " term to it with \u{201C}or\u{201D}."
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
            guard let open = joining else { return }
            remove(choice.term, from: open)
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

/// One condition: its terms joined with "or", the recordings that remain up to it, and its "or" control.
private struct ConditionRow: View {
    let condition: Search.Condition
    let count: Int
    let isJoining: Bool
    let toggle: () -> Void
    let remove: (Search.Term) -> Void
    @ScaledMetric(relativeTo: .subheadline) private var chipHeight = Layout.chipHeight
    @ScaledMetric(relativeTo: .footnote) private var orHeight = Layout.orButtonHeight

    var body: some View {
        HStack(spacing: Layout.trailGap) {
            Flow(spacing: Layout.conditionTermGap) {
                ForEach(Array(condition.terms.enumerated()), id: \.element) { position, term in
                    if position > 0 {
                        Text("or")
                            .typeStyle(.footnote)
                            .foregroundStyle(Palette.textSecondary)
                            .frame(minHeight: chipHeight)
                    }
                    Button {
                        remove(term)
                    } label: {
                        HStack(spacing: Layout.conditionTermGap) {
                            Text(term.name)
                                .foregroundStyle(Palette.textPrimary)
                            Image(systemName: "xmark")
                                .foregroundStyle(Palette.textTertiary)
                        }
                        .typeStyle(Layout.chipLabel)
                        .lineLimit(1)
                        .padding(.horizontal, Layout.chipPadding)
                        .frame(minHeight: chipHeight)
                        .background(Palette.fillQuiet, in: Capsule())
                        .contentShape(Capsule())
                    }
                    .buttonStyle(FlatPress())
                    .accessibilityLabel("Remove \(term.name)")
                    .accessibilityIdentifier("filter-chip")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(count.formatted())
                .typeStyle(.subheadline)
                .monospacedDigit()
                .foregroundStyle(Palette.textPrimary)
                .accessibilityIdentifier("filter-condition-count")
            Button(action: toggle) {
                Text(isJoining ? "or \u{2713}" : "or +")
                    .typeStyle(.footnote)
                    .lineLimit(1)
                    .foregroundStyle(isJoining ? Palette.onAccent : Palette.tint)
                    .padding(.horizontal, Layout.orButtonPadding)
                    .frame(minHeight: orHeight)
                    .background(isJoining ? Palette.accentFill : Palette.fillQuiet, in: Capsule())
                    .contentShape(Capsule())
            }
            .buttonStyle(FlatPress())
            .accessibilityLabel("Or")
            .accessibilityAddTraits(isJoining ? .isSelected : [])
            .accessibilityIdentifier("filter-or")
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: toggle)
        .listRowBackground(
            ZStack(alignment: .leading) {
                Palette.backgroundRow.color
                if isJoining {
                    Palette.tint.color.opacity(0.08)
                    Palette.tint.color.frame(width: Layout.conditionMark)
                }
            }
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("filter-condition")
    }
}

extension View {
    /// A term row keeps the specimen row inset inside the list, and its hairline spans the list.
    fileprivate func termRow() -> some View {
        listRowInsets(EdgeInsets(top: 0, leading: Layout.termInset, bottom: 0, trailing: Layout.termInset))
            .frame(minHeight: Measure.hitTarget)
            .alignmentGuide(.listRowSeparatorLeading) { _ in -Layout.termInset }
            .alignmentGuide(.listRowSeparatorTrailing) { $0.width + Layout.termInset }
    }
}

/// A term with what a tap does and the recordings that remain: "and n", "or n", or a check.
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
                effect
                    .typeStyle(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(choice.effect == .check ? Palette.textSecondary : Palette.tint)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(FlatPress())
        .accessibilityAddTraits(choice.effect == .check ? .isSelected : [])
        .accessibilityIdentifier("filter-term")
    }

    private var effect: Text {
        let count = choice.count.formatted()
        switch choice.effect {
        case .start: return Text(count)
        case .and: return Text("and \(count)")
        case .or: return Text("or \(count)")
        case .check: return Text("\(Image(systemName: "checkmark")) \(count)")
        }
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
            TextField("Find in \(scope.title.lowercased())", text: $text)
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

/// Lays out views in rows from the leading edge and wraps a view that does not fit, as CSS flex-wrap does.
private struct Flow: SwiftUI.Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let placed = arrange(width: proposal.width ?? .infinity, subviews)
        return placed.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let placed = arrange(width: bounds.width, subviews)
        for (subview, origin) in zip(subviews, placed.origins) {
            subview.place(
                at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y), proposal: .unspecified)
        }
    }

    private func arrange(width: CGFloat, _ subviews: Subviews) -> (origins: [CGPoint], size: CGSize) {
        var origins: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var line: CGFloat = 0
        var widest: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += line + spacing
                line = 0
            }
            origins.append(CGPoint(x: x, y: y))
            widest = max(widest, x + size.width)
            x += size.width + spacing
            line = max(line, size.height)
        }
        return (origins, CGSize(width: widest, height: y + line))
    }
}
