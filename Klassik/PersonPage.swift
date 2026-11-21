import SwiftUI

/// The plain list of a person page. The composer and the performer page share it, so they differ only where their
/// content differs (ADR 0017, 0030). A grouped list adds its own top margin and section gaps, which person.html does
/// not have.
struct PersonPageList<Content: View>: View {
    @ViewBuilder let content: (GeometryProxy) -> Content

    var body: some View {
        GeometryReader { proxy in
            List {
                Group { content(proxy) }
                    .listRowBackground(Color.clear)
                    .listSectionSeparator(.hidden)
                    .pageRow()
            }
            .listStyle(.plain)
            .listSectionSeparator(.hidden)
            .environment(\.defaultMinListRowHeight, 0)
            .environment(\.defaultMinListHeaderHeight, 0)
            .environment(\.isPageList, true)
            .scrollContentBackground(.hidden)
            .pageContentPosition()
            .background(Palette.backgroundPage)
            .ignoresSafeArea(.container, edges: .top)
        }
    }
}

/// The About tab of a person page: the Wikidata biography and credits, then the tags. `tags` gives the rows under
/// "Your tags"; the first row hides its top hairline and the last its bottom one. `kind` names the person in the
/// text and prefixes the accessibility identifiers.
struct PersonAbout<Tags: View>: View {
    let facts: PersonFacts?
    let kind: String
    @ViewBuilder let tags: Tags

    var body: some View {
        if let facts {
            if let bio = facts.bio {
                Section {
                    SectionHeading("Biography")
                    Text(bio)
                        .ink()
                        .accessibilityIdentifier("\(kind)-bio")
                        .listRowSeparator(.hidden)
                }
            }
            if !facts.credits.isEmpty {
                Section {
                    SectionHeading("Credits")
                    ForEach(facts.credits, id: \.self) { credit in
                        CreditRow(credit: credit)
                            .itemSeparator(first: credit == facts.credits.first, last: credit == facts.credits.last)
                    }
                }
            }
        } else {
            Section {
                Text("Wikidata has no facts for this \(kind). Klassik shows your tags.")
                    .foregroundStyle(Palette.textSecondary)
                    .listRowSeparator(.hidden)
            }
        }
        Section {
            SectionHeading("Your tags")
            tags
        }
    }
}
