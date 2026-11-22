import SwiftUI

/// Edits the classical rules that decide which albums are classical.
struct ClassicalRulesView: View {
    @Environment(AppModel.self) private var model
    @FocusState private var focusedCheck: UUID?

    var body: some View {
        @Bindable var library = model.library
        PageForm {
            ResultSection(library: library)

            ForEach($library.filter.rules) { $rule in
                let number = (library.filter.rules.firstIndex { $0.id == rule.id } ?? 0) + 1
                Section {
                    ForEach($rule.checks) { $check in
                        CheckRow(check: $check, focusedCheck: $focusedCheck)
                    }
                    .onDelete { rule.checks.remove(atOffsets: $0) }
                    Menu("Add Check") {
                        ForEach(ClassicalFilter.Check.Kind.allCases, id: \.self) { kind in
                            Button(kind.title) { rule.checks.append(.init(kind: kind)) }
                        }
                    }
                    .accessibilityIdentifier("add-check")
                    Button("Delete Rule", role: .destructive) {
                        library.filter.rules.removeAll { $0.id == rule.id }
                    }
                } header: {
                    Text(number == 1 ? "Rule \(number)" : "Or Rule \(number)")
                }
            }

            Section {
                Button("Add Rule") {
                    library.filter.rules.append(.init(checks: [.init(kind: .genreContains)]))
                }
                .accessibilityIdentifier("add-rule")
            } footer: {
                Text(
                    "A track is classical if one of the classical rules matches. A rule matches if all of its checks match. An album is classical if most of its tracks are; then all of its tracks count. Klassik keeps the rules on this iPhone."
                )
            }

            Section {
                Button("Restore Default Rules") { library.filter = ClassicalFilter() }
                    .disabled(library.filter == ClassicalFilter())
            }
        }
        .pageTitle("Classical Rules")
    }

    /// A result row value: "412 of 550 on server".
    static func share(_ part: Int, of whole: Int) -> String {
        "\(part.formatted()) of \(whole.formatted()) on server"
    }
}

/// What the rules let through. It comes first, so a rule change shows its effect at the top.
private struct ResultSection: View {
    let library: Library

    private var albums: String { ClassicalRulesView.share(library.classicalAlbumCount, of: library.albumCount) }
    private var tracks: String { ClassicalRulesView.share(library.classical.count, of: library.songs.count) }

    var body: some View {
        Section("Result") {
            if library.syncedAt == nil {
                if library.isSyncing {
                    LabeledContent("Syncing") {
                        Text("\(library.received) tracks")
                    }
                    .ink()
                } else {
                    Text("Not synced")
                        .foregroundStyle(Palette.textSecondary)
                }
            } else {
                NavigationLink(value: Page.albums(classical: true)) {
                    LabeledContent("Albums", value: albums)
                        .ink()
                }
                .accessibilityIdentifier("classical-albums")
                LabeledContent("Tracks", value: tracks)
                    .ink()
                    .accessibilityIdentifier("classical-tracks")
                NavigationLink(value: Page.albums(classical: false)) {
                    LabeledContent(
                        "Other Albums", value: (library.albumCount - library.classicalAlbumCount).formatted()
                    )
                    .ink()
                }
                .accessibilityIdentifier("other-albums")
            }
        }
    }
}

private struct CheckRow: View {
    @Binding var check: ClassicalFilter.Check
    @FocusState.Binding var focusedCheck: UUID?

    var body: some View {
        HStack {
            Picker("Check", selection: $check.kind) {
                ForEach(ClassicalFilter.Check.Kind.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .labelsHidden()
            .fixedSize()
            .tint(Palette.textPrimary)
            if check.kind.takesText {
                TextField("Genre", text: $check.text)
                    .multilineTextAlignment(.trailing)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focusedCheck, equals: check.id)
                    .submitLabel(.done)
                    .onSubmit { focusedCheck = nil }
                    .accessibilityIdentifier("check-text")
            }
        }
    }
}
