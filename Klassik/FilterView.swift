import SwiftUI

/// Edits the rules that decide which albums are classical.
struct FilterView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var library = model.library
        Form {
            ForEach($library.filter.rules) { $rule in
                let number = (library.filter.rules.firstIndex { $0.id == rule.id } ?? 0) + 1
                Section {
                    ForEach($rule.conditions) { $condition in
                        ConditionRow(condition: $condition)
                    }
                    .onDelete { rule.conditions.remove(atOffsets: $0) }
                    Menu("Add Condition") {
                        ForEach(ClassicalFilter.Condition.Kind.allCases, id: \.self) { kind in
                            Button(kind.title) { rule.conditions.append(.init(kind: kind)) }
                        }
                    }
                    Button("Delete Rule", role: .destructive) {
                        library.filter.rules.removeAll { $0.id == rule.id }
                    }
                } header: {
                    Text(number == 1 ? "Rule \(number)" : "Or Rule \(number)")
                }
            }

            Section {
                Button("Add Rule") {
                    library.filter.rules.append(.init(conditions: [.init(kind: .genreContains)]))
                }
                .accessibilityIdentifier("add-rule")
            } footer: {
                Text(
                    "A track is classical if one of the rules matches. A rule matches if all of its conditions match. An album is classical if most of its tracks are; then all of its tracks count. Klassik keeps the rules on this iPhone."
                )
            }

            Section("Result") {
                LabeledContent("Classical Albums", value: library.classicalAlbumCount.formatted())
                LabeledContent("Classical Tracks", value: library.classical.count.formatted())
            }

            Section {
                Button("Restore Default Rules") { library.filter = ClassicalFilter() }
                    .disabled(library.filter == ClassicalFilter())
            }
        }
        .navigationTitle("Classical Filter")
        .miniPlayerInset()
    }
}

private struct ConditionRow: View {
    @Binding var condition: ClassicalFilter.Condition

    var body: some View {
        HStack {
            Picker("Condition", selection: $condition.kind) {
                ForEach(ClassicalFilter.Condition.Kind.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .labelsHidden()
            .fixedSize()
            .tint(.primary)
            if condition.kind.takesText {
                TextField("Genre", text: $condition.text)
                    .multilineTextAlignment(.trailing)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("condition-text")
            }
        }
    }
}
