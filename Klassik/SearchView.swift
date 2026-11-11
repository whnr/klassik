import SwiftUI

/// The Search place. The field, the results and the filters come with the Search slices;
/// until then the place holds the list of performers.
struct SearchView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        PageList {
            Section {
                NavigationLink(value: Page.performers) {
                    LabeledContent("Performers", value: model.library.index.performers.count.formatted())
                        .ink()
                }
                .accessibilityIdentifier("performers")
            } footer: {
                Text("Search for works, composers and albums arrives in a later update.")
            }
        }
        .navigationTitle("Search")
    }
}
