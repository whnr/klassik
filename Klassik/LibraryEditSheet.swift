import SwiftUI

/// The Library edit sheet (the specimen edit sheet), on the shared sheet frame. It raises over the live tab, and
/// every change reaches the tab at once. Done closes it; there is no Save or Cancel.
struct LibraryEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    let editor: LibraryEditor
    let rows: [LibraryRowSetup]
    /// The tab as it draws now: a row that it hides has nothing to show yet.
    let page: LibraryPage

    var body: some View {
        let level = editor.shownLevel
        SheetFrame(
            title: LocalizedStringKey(heading(of: level)), count: count(of: level), back: back(of: level),
            done: { dismiss() }, identifier: "edit"
        ) {
            switch level {
            case .list:
                EditList(editor: editor, rows: rows, page: page)
            case .add:
                AddRow(editor: editor)
            case .row(let id):
                if let row = rows.first(where: { $0.id == id }) { RowSettings(editor: editor, row: row) }
            case .choice(let id, let field):
                if let row = rows.first(where: { $0.id == id }) { Choices(editor: editor, row: row, field: field) }
            }
        }
        .sheetFrame()
        // The tab behind the sheet stays live: a tap on a row selects it.
        .presentationBackgroundInteraction(.enabled)
    }

    private func row(_ id: String) -> LibraryRowSetup? { rows.first { $0.id == id } }

    private func heading(of level: LibraryEditor.Level) -> String {
        switch level {
        case .list: L("Edit Library")
        case .add: L("Add row")
        case .row(let id): row(id).map(LibraryPage.title(of:)) ?? L("Edit Library")
        case .choice(_, let field): field.title
        }
    }

    private func count(of level: LibraryEditor.Level) -> String {
        switch level {
        case .list: L("\(rows.count) rows")
        case .row(let id): row(id).map { page.shows($0.id) ? "" : L("Nothing to show yet") } ?? ""
        case .add, .choice: ""
        }
    }

    private func back(of level: LibraryEditor.Level) -> (() -> Void)? {
        if level == .list { return nil }
        return { editor.back() }
    }
}

/// A grouped list of the sheet: lines on the row ground with rounded corners.
private struct EditCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.backgroundRow, in: RoundedRectangle(cornerRadius: Radius.m))
            .clipShape(RoundedRectangle(cornerRadius: Radius.m))
            .padding(.top, Layout.editSectionTop)
    }
}

/// A hairline between two lines of a card, from the title.
private struct LineSeparator: View {
    var body: some View {
        Divider().padding(.leading, Layout.editLineSeparatorInset)
    }
}

private struct Foot: View {
    let text: String

    var body: some View {
        Text(verbatim: text)
            .typeStyle(.footnote)
            .foregroundStyle(Palette.textSecondary)
            .padding(.horizontal, Layout.editLineInset)
            .padding(.top, Layout.editSectionTop)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: Level 1: the rows

private struct EditList: View {
    let editor: LibraryEditor
    let rows: [LibraryRowSetup]
    let page: LibraryPage
    @State private var heights: [String: CGFloat] = [:]
    @State private var dragging: String?
    @State private var translation: CGFloat = 0
    /// How far the layout moved the dragged line since the drag began.
    @State private var shift: CGFloat = 0

    var body: some View {
        EditCard {
            Button {
                editor.level = .add
            } label: {
                Text("Add row")
                    .typeStyle(.body)
                    .foregroundStyle(Palette.tint)
                    .padding(.horizontal, Layout.editLineInset)
                    .frame(maxWidth: .infinity, minHeight: Layout.editLineHeight, alignment: .leading)
                    .contentShape(.rect)
            }
            .buttonStyle(FlatPress())
            .accessibilityIdentifier("edit-add")
        }
        EditCard {
            ForEach(Array(rows.enumerated()), id: \.element.id) { position, row in
                EditLine(
                    row: row, isSelected: editor.selected == row.id, isEmpty: !page.shows(row.id),
                    isFirst: position == 0, select: { editor.select(row.id) }, delete: { editor.delete(row.id) },
                    move: { by in move(row.id, by: by) },
                    drag: { drag(row.id, $0) }, drop: end
                )
                .onGeometryChange(for: CGFloat.self) {
                    $0.size.height
                } action: {
                    heights[row.id] = $0
                }
                .offset(y: dragging == row.id ? translation - shift : 0)
                .zIndex(dragging == row.id ? 1 : 0)
            }
        }
    }

    private var lineHeights: [CGFloat] { rows.map { heights[$0.id] ?? Layout.editLineHeight } }

    /// The line follows the finger; the rows, and so the tab, move when it passes a neighbour.
    private func drag(_ id: String, _ value: CGFloat) {
        guard let index = rows.firstIndex(where: { $0.id == id }) else { return }
        dragging = id
        translation = value
        let target = LibraryReorder.destination(of: index, translation: value - shift, heights: lineHeights)
        guard target != index else { return }
        shift += LibraryReorder.shift(from: index, to: target, heights: lineHeights)
        editor.move(fromOffsets: [index], toOffset: LibraryReorder.offset(from: index, to: target))
    }

    private func end() {
        dragging = nil
        translation = 0
        shift = 0
    }

    /// The same move for VoiceOver, one place up or down.
    private func move(_ id: String, by step: Int) {
        guard let index = rows.firstIndex(where: { $0.id == id }), rows.indices.contains(index + step) else { return }
        editor.move(fromOffsets: [index], toOffset: LibraryReorder.offset(from: index, to: index + step))
    }
}

/// A line: title, subtitle and drag handle. A swipe to the left shows Delete.
private struct EditLine: View {
    let row: LibraryRowSetup
    let isSelected: Bool
    let isEmpty: Bool
    let isFirst: Bool
    let select: () -> Void
    let delete: () -> Void
    let move: (Int) -> Void
    let drag: (CGFloat) -> Void
    let drop: () -> Void
    @State private var offset: CGFloat = 0
    @State private var isOpen = false
    private static let swipeStart: CGFloat = 12

    var body: some View {
        front
            .offset(x: offset)
            .background(alignment: .trailing) {
                Button(action: delete) {
                    Text("Delete")
                        .typeStyle(.body)
                        .fontWeight(.semibold)
                        .foregroundStyle(Palette.onAccent)
                        .frame(width: Layout.editSwipeAction)
                        .frame(maxHeight: .infinity)
                        .background(Color.red)
                }
                .buttonStyle(.plain)
                .accessibilityHidden(offset == 0)
                .accessibilityIdentifier("edit-delete")
            }
            .overlay(alignment: .top) { if !isFirst { LineSeparator() } }
            .clipped()
    }

    private var front: some View {
        HStack(spacing: Layout.editLineGap) {
            Button {
                if isOpen { close() } else { select() }
            } label: {
                VStack(alignment: .leading, spacing: 0) {
                    Text(verbatim: LibraryPage.title(of: row))
                        .typeStyle(Layout.editLineTitle)
                        .foregroundStyle(Palette.textPrimary)
                    Text(verbatim: isEmpty ? L("Nothing to show yet") : row.subtitle)
                        .typeStyle(Layout.editLineSubtitle)
                        .foregroundStyle(Palette.textSecondary)
                }
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
            .accessibilityAction(named: Text("Delete"), delete)
            .accessibilityAction(named: Text("Move up")) { move(-1) }
            .accessibilityAction(named: Text("Move down")) { move(1) }
            .accessibilityIdentifier("edit-line")
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(Palette.textTertiary)
                .frame(width: Layout.editHandleWidth)
                .frame(maxHeight: .infinity)
                .contentShape(.rect)
                .gesture(
                    DragGesture(minimumDistance: 0, coordinateSpace: .global)
                        .onChanged { drag($0.translation.height) }
                        .onEnded { _ in drop() }
                )
                .accessibilityHidden(true)
        }
        .padding(.leading, Layout.editLineInset)
        .padding(.trailing, Layout.editLineTrailing)
        .frame(minHeight: Layout.editLineHeight)
        .background {
            ZStack {
                Rectangle().fill(Palette.backgroundRow)
                Rectangle().fill(Palette.tint.opacity(isSelected ? Layout.editSelectedTint : 0))
            }
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: Self.swipeStart)
                .onChanged { value in
                    guard abs(value.translation.width) > abs(value.translation.height) else { return }
                    let base = isOpen ? -Layout.editSwipeAction : 0
                    offset = max(-Layout.editSwipeAction, min(0, base + value.translation.width))
                }
                .onEnded { _ in
                    isOpen = offset < -Layout.editSwipeAction / 2
                    withAnimation { offset = isOpen ? -Layout.editSwipeAction : 0 }
                }
        )
    }

    private func close() {
        isOpen = false
        withAnimation { offset = 0 }
    }
}

// MARK: Add row

private struct AddRow: View {
    let editor: LibraryEditor

    var body: some View {
        EditCard {
            ForEach(Array(LibraryRowSetup.addable.enumerated()), id: \.element) { position, kind in
                let allowed = editor.canAdd(kind)
                Button {
                    editor.add(kind)
                } label: {
                    HStack(spacing: Layout.editKindGap) {
                        KindPreview(shape: Self.shape(of: kind))
                        VStack(alignment: .leading, spacing: 0) {
                            Text(verbatim: LibraryPage.title(of: LibraryRowSetup(kind: kind)))
                                .typeStyle(.body)
                                .foregroundStyle(Palette.textPrimary)
                            Text(verbatim: allowed ? Self.line(of: kind) : L("Already on the tab"))
                                .typeStyle(.footnote)
                                .foregroundStyle(Palette.textSecondary)
                        }
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.leading, Layout.editLineInset)
                    .padding(.trailing, Layout.editLineTrailing)
                    .frame(minHeight: Layout.editLineHeight)
                    .contentShape(.rect)
                }
                .buttonStyle(FlatPress())
                .disabled(!allowed)
                .opacity(allowed ? 1 : Layout.editKindOff)
                .overlay(alignment: .top) { if position > 0 { LineSeparator() } }
                .accessibilityIdentifier("edit-kind-\(kind.rawValue)")
            }
        }
    }

    static func shape(of kind: LibraryRowKind) -> KindPreview.Shape {
        switch kind {
        case .pick: .pick
        case .composers, .performers: .faces
        case .favourites: .mixed
        case .links: .links
        default: .covers
        }
    }

    static func line(of kind: LibraryRowKind) -> String {
        switch kind {
        case .pick: L("One recording a day, as a sentence")
        case .composers: L("Faces, with their number of works")
        case .performers: L("Faces, with their number of recordings")
        case .works: L("Covers, with their composer")
        case .recordings: L("Covers, with their lead performer")
        case .albums: L("Covers, newest first")
        case .favourites: L("Faces and covers, mixed")
        case .added: L("Covers of what you added last")
        case .heard: L("Covers of what you played last")
        // A saved search is not offered yet.
        case .saved: ""
        case .links: L("Tiles with counts, a way into each page")
        }
    }
}

/// The small preview of a row kind. It draws the shape of a row, never real content.
struct KindPreview: View {
    enum Shape { case pick, faces, covers, mixed, links }
    let shape: Shape

    var body: some View {
        Canvas { context, size in
            let ink = Palette.textSecondary
            let unit = size.height / 6
            func bar(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ opacity: Double) {
                context.fill(
                    Path(roundedRect: CGRect(x: x, y: y, width: width, height: unit * 0.5), cornerRadius: Radius.xs),
                    with: .style(ink.opacity(opacity)))
            }
            func dot(_ x: CGFloat, _ y: CGFloat, _ radius: CGFloat, _ opacity: Double) {
                context.fill(
                    Path(ellipseIn: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)),
                    with: .style(ink.opacity(opacity)))
            }
            func box(_ x: CGFloat, _ y: CGFloat, _ side: CGFloat, _ opacity: Double) {
                context.fill(
                    Path(roundedRect: CGRect(x: x, y: y, width: side, height: side), cornerRadius: Radius.xs),
                    with: .style(ink.opacity(opacity)))
            }
            let step = size.width / 4
            switch shape {
            case .pick:
                bar(size.width / 6, unit * 1.6, size.width * 0.66, 1)
                bar(size.width / 6, unit * 2.8, size.width * 0.5, 0.6)
                bar(size.width / 6, unit * 4, size.width * 0.6, 0.4)
            case .faces:
                for index in 0..<4 {
                    let x = step * (CGFloat(index) + 0.5)
                    dot(x, unit * 2.5, unit, 0.7)
                    bar(x - unit, unit * 4.2, unit * 2, 0.4)
                }
            case .covers:
                for index in 0..<3 {
                    let x = size.width * 0.07 + size.width * 0.3 * CGFloat(index)
                    box(x, unit * 0.7, unit * 2.7, 0.7)
                    bar(x, unit * 4, unit * 2, 0.4)
                }
            case .mixed:
                dot(size.width * 0.18, unit * 2, unit * 1.2, 0.7)
                box(size.width * 0.38, unit * 0.8, unit * 2.3, 0.7)
                box(size.width * 0.68, unit * 0.8, unit * 2.3, 0.7)
                bar(size.width * 0.08, unit * 4, unit * 2, 0.4)
                bar(size.width * 0.38, unit * 4, unit * 2, 0.4)
            case .links:
                for index in 0..<3 {
                    let x = size.width * 0.07 + size.width * 0.3 * CGFloat(index)
                    context.fill(
                        Path(
                            roundedRect: CGRect(x: x, y: unit, width: unit * 2.7, height: unit * 3.4),
                            cornerRadius: Radius.xs),
                        with: .style(ink.opacity(0.18)))
                    bar(x + unit * 0.5, unit * 1.8, unit * 1.4, 0.7)
                    bar(x + unit * 0.5, unit * 3.1, unit * 1.7, 0.4)
                }
            }
        }
        .frame(width: Layout.editPreviewWidth, height: Layout.editPreviewHeight)
        .background(Palette.fillQuiet, in: RoundedRectangle(cornerRadius: Layout.editPreviewCorner))
        .accessibilityHidden(true)
    }
}

// MARK: Level 2: the settings of one row

private struct RowSettings: View {
    let editor: LibraryEditor
    let row: LibraryRowSetup

    var body: some View {
        if row.fields.isEmpty {
            Foot(text: L("Nothing to set up yet."))
        } else {
            EditCard {
                ForEach(Array(row.fields.enumerated()), id: \.element) { position, field in
                    line(field)
                        .overlay(alignment: .top) { if position > 0 { LineSeparator() } }
                }
            }
            Foot(text: note)
        }
    }

    private var note: String {
        if row.kind == .pick {
            return L("One complete recording or album a day. Nothing starts playback.")
        }
        return L("The title follows these settings: \(LibraryPage.title(of: row)).")
    }

    @ViewBuilder
    private func line(_ field: LibraryEditField) -> some View {
        let choices = row.choices(for: field)
        let only = choices.count < 2
        let label = HStack(spacing: Layout.editLineGap) {
            Text(verbatim: field.title)
                .typeStyle(.body)
                .foregroundStyle(Palette.textPrimary)
            Spacer(minLength: 0)
            Text(verbatim: choices.first(where: \.isCurrent)?.title ?? "")
                .typeStyle(.body)
                .foregroundStyle(Palette.textSecondary)
                .multilineTextAlignment(.trailing)
            if !only {
                Image(systemName: "chevron.right")
                    .typeStyle(.footnote)
                    .fontWeight(.semibold)
                    .foregroundStyle(Palette.textTertiary)
                    .accessibilityHidden(true)
            }
        }
        .padding(.leading, Layout.editLineInset)
        .padding(.trailing, Layout.editLineInset)
        .frame(minHeight: Layout.editLineHeight)
        .contentShape(.rect)
        if only {
            label.accessibilityElement(children: .combine)
                .accessibilityIdentifier("edit-field-\(field.rawValue)")
        } else {
            Button {
                editor.level = .choice(row.id, field)
            } label: {
                label
            }
            .buttonStyle(FlatPress())
            .accessibilityIdentifier("edit-field-\(field.rawValue)")
        }
    }
}

/// Level 3: the values of one setting. A tap sets the value and goes back to the row.
private struct Choices: View {
    let editor: LibraryEditor
    let row: LibraryRowSetup
    let field: LibraryEditField

    var body: some View {
        EditCard {
            ForEach(Array(row.choices(for: field).enumerated()), id: \.element.id) { position, choice in
                Button {
                    editor.choose(choice.id, for: field, ofRow: row.id)
                    editor.level = .row(row.id)
                } label: {
                    HStack(spacing: Layout.editLineGap) {
                        Image(systemName: "checkmark")
                            .fontWeight(.semibold)
                            .foregroundStyle(Palette.tint)
                            .frame(width: Layout.editCheckWidth)
                            .opacity(choice.isCurrent ? 1 : 0)
                            .accessibilityHidden(true)
                        Text(verbatim: choice.title)
                            .typeStyle(.body)
                            .foregroundStyle(Palette.textPrimary)
                        Spacer(minLength: 0)
                    }
                    .padding(.leading, Layout.editLineInset)
                    .padding(.trailing, Layout.editLineInset)
                    .frame(minHeight: Layout.editLineHeight)
                    .contentShape(.rect)
                }
                .buttonStyle(FlatPress())
                .overlay(alignment: .top) { if position > 0 { LineSeparator() } }
                .accessibilityAddTraits(choice.isCurrent ? .isSelected : [])
                .accessibilityIdentifier("edit-choice-\(choice.id)")
            }
        }
    }
}
