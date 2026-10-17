import SwiftUI

/// Edits the rule that decides which albums are classical.
struct FilterView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var library = model.library
        Form {
            Section {
                LabeledContent("Genre Contains") {
                    TextField("Genre", text: $library.filter.genre, prompt: Text("Off"))
                        .multilineTextAlignment(.trailing)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("filter-genre")
                }
                Toggle("Has a Work", isOn: $library.filter.work)
                Toggle("Has a Composer", isOn: $library.filter.composer)
            } header: {
                Text("A Track Matches If")
            } footer: {
                Text("A track matches if any rule matches. An album is classical if most of its tracks match; then all of its tracks count. Klassik keeps this rule on this iPhone.")
            }

            Section("Result") {
                LabeledContent("Classical Albums", value: library.classicalAlbumCount.formatted())
                LabeledContent("Classical Tracks", value: library.classical.count.formatted())
            }

            Section {
                Button("Restore Default") { library.filter = ClassicalFilter() }
                    .disabled(library.filter == ClassicalFilter())
            }
        }
        .navigationTitle("Classical Filter")
    }
}
