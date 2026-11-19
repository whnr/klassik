import SwiftUI

/// When a work was composed, where Klassik found it, and its MusicBrainz match.
struct WorkSourcesView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL
    let work: WorkIndex.Work

    var body: some View {
        let enrichment = model.enrichment
        let facts = enrichment.facts(of: work)
        PageForm {
            Section {
                if let composed = facts?.composed, let source = facts?.source {
                    LabeledContent(
                        source == .wikidata ? "Wikidata (published)" : "MusicBrainz", value: composed.text
                    )
                    .ink()
                } else {
                    Text("No source gives a year.")
                        .foregroundStyle(Palette.textSecondary)
                }
            } header: {
                Text("Composed")
            }

            Section {
                link(enrichment.link(of: work), facts: facts)
                Button("Search on MusicBrainz", systemImage: "magnifyingglass") {
                    openURL(MusicBrainz.searchURL("\(work.composer) \(work.title)"))
                }
            } header: {
                Text("MusicBrainz")
            } footer: {
                Text("Missing or wrong data? Fix it in MusicBrainz, then look up again.")
            }
        }
        .pageTitle("Dates and Sources")
    }

    @ViewBuilder private func link(_ link: Enrichment.Link, facts: WorkFacts?) -> some View {
        let enrichment = model.enrichment
        switch link {
        case .tagged(let id), .found(let id):
            LabeledContent("Work", value: facts?.title ?? (enrichment.isRunning ? "Looking up…" : "Not found"))
                .ink()
                .accessibilityIdentifier("musicbrainz-work")
            Button("Open in MusicBrainz", systemImage: "arrow.up.forward.square") {
                openURL(MusicBrainz.workURL(id: facts?.id ?? id))
            }
            if case .found = link {
                Button("Not This Work", systemImage: "xmark.circle", role: .destructive) { enrichment.reject(work) }
            }
            lookUpAgain
        case .candidates(let found):
            Text("Which MusicBrainz work is this?")
                .foregroundStyle(Palette.textSecondary)
            ForEach(found) { candidate in
                Button {
                    Task { await enrichment.confirm(candidate, for: work) }
                } label: {
                    Text(candidate.title)
                        .ink()
                }
                .accessibilityIdentifier("candidate")
            }
            Button("None of These", systemImage: "xmark.circle") { enrichment.reject(work) }
        case .unmatched:
            Text(
                CatalogueNumber.find(in: work.title) == nil
                    ? "No MusicBrainz work matches. A catalogue number in the title, such as Op. 67, helps."
                    : "No MusicBrainz work matches."
            )
            .foregroundStyle(Palette.textSecondary)
            lookUpAgain
        case .pending:
            Text("Not looked up yet.")
                .foregroundStyle(Palette.textSecondary)
        }
    }

    private var lookUpAgain: some View {
        Button("Look Up Again", systemImage: "arrow.clockwise") {
            Task { await model.enrichment.lookUpAgain(work) }
        }
    }
}
