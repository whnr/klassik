import SwiftUI

/// Everyone who plays on a recording, from the performer and conductor tags. A row opens the performer page.
struct PerformersView: View {
    @Environment(AppModel.self) private var model
    @State private var query = ""

    var body: some View {
        let performers = model.library.index.performers.filter {
            query.isEmpty || $0.name.localizedStandardContains(query)
        }
        PageList {
            ForEach(performers) { performer in
                NavigationLink(value: Page.performer(performer.name)) {
                    LabeledContent(performer.name, value: performer.entries.count.formatted())
                        .ink()
                }
                .accessibilityIdentifier("performer")
            }
        }
        .overlay {
            if performers.isEmpty {
                ContentUnavailableView("No Performers", systemImage: "person.2")
            }
        }
        .searchable(text: $query)
        .pageTitle("Performers")
    }
}
