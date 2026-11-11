import SwiftUI

/// What the MusicBrainz lookup does now, for the footer of a list.
struct LookupStatus: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let enrichment = model.enrichment
        if let progress = enrichment.progress {
            Text(Self.text(progress))
        } else if let error = enrichment.lastError {
            Text("MusicBrainz lookup stopped: \(error) Klassik tries again at the next start.")
        } else {
            Text("Dates come from MusicBrainz and Wikidata. Your own years win.")
        }
    }

    static func text(_ progress: Enrichment.Progress) -> String {
        let place = progress.composer.map { " · \($0)" } ?? " · Wikidata"
        return "Looking up \(progress.done) of \(progress.total) works\(place)"
    }
}

/// How far the MusicBrainz lookup got, and the works that need the listener.
struct EnrichmentStatusView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let enrichment = model.enrichment
        let index = model.library.index
        let summary = enrichment.summary(of: index)
        PageForm {
            Section {
                if let progress = enrichment.progress {
                    ProgressView(value: Double(progress.done), total: Double(max(progress.total, 1))) {
                        Text(LookupStatus.text(progress))
                    }
                    .accessibilityIdentifier("lookup-progress")
                } else if let error = enrichment.lastError {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(Palette.textPrimary)
                } else {
                    LabeledContent("Status", value: summary.pending > 0 ? "Waiting" : "Up to date")
                        .ink()
                }
                LabeledContent("Requests Since Start", value: enrichment.requests.formatted())
                    .ink()
                Button("Look Up Missing Again", systemImage: "arrow.clockwise") {
                    Task { await enrichment.lookUpMissingAgain(index) }
                }
                .disabled(enrichment.progress != nil)
            } header: {
                Text("Lookup")
            } footer: {
                Text(
                    "Klassik lists each composer's works in MusicBrainz and matches them on this iPhone. "
                        + "MusicBrainz allows one request a second. Look up missing again after a fix in MusicBrainz.")
            }

            Section("Works with a WORK Tag") {
                LabeledContent("Works", value: summary.works.formatted())
                    .ink()
                LabeledContent("Linked to MusicBrainz", value: summary.linked.formatted())
                    .ink()
                    .accessibilityIdentifier("linked-count")
                LabeledContent("With a Year", value: summary.dated.formatted())
                    .ink()
                NavigationLink(value: Page.worksToConfirm) {
                    LabeledContent("To Confirm", value: summary.toConfirm.count.formatted())
                        .ink()
                }
                .disabled(summary.toConfirm.isEmpty)
                .accessibilityIdentifier("to-confirm")
                NavigationLink(value: Page.worksWithoutMatch) {
                    LabeledContent("No Match", value: summary.unmatched.count.formatted())
                        .ink()
                }
                .disabled(summary.unmatched.isEmpty)
                if summary.pending > 0 {
                    LabeledContent("Not Looked Up Yet", value: summary.pending.formatted())
                        .ink()
                }
            }

            Section("Composers") {
                LabeledContent(
                    "With Life Dates", value: "\(summary.composersWithDates) of \(summary.composers)"
                )
                .ink()
            }
        }
        .navigationTitle("MusicBrainz")
        .miniPlayerInset()
    }
}

/// Works that need a look, each opening its dates and sources.
struct WorkListView: View {
    let title: String
    let works: [WorkIndex.Work]

    var body: some View {
        PageList {
            ForEach(works) { work in
                NavigationLink(value: Page.sources(work: work.id)) {
                    VStack(alignment: .leading) {
                        Text(work.title)
                        Text(work.composer)
                            .typeStyle(.subheadline)
                            .foregroundStyle(Palette.textSecondary)
                    }
                    .ink()
                }
                .accessibilityIdentifier("status-work")
            }
        }
        .navigationTitle(title)
        .miniPlayerInset()
    }
}
