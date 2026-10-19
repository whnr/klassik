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
        Form {
            Section {
                if let progress = enrichment.progress {
                    ProgressView(value: Double(progress.done), total: Double(max(progress.total, 1))) {
                        Text(LookupStatus.text(progress))
                    }
                    .accessibilityIdentifier("lookup-progress")
                } else if let error = enrichment.lastError {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                } else {
                    LabeledContent("Status", value: summary.pending > 0 ? "Waiting" : "Up to date")
                }
                LabeledContent("Requests Since Start", value: enrichment.requests.formatted())
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
                LabeledContent("Linked to MusicBrainz", value: summary.linked.formatted())
                    .accessibilityIdentifier("linked-count")
                LabeledContent("With a Year", value: summary.dated.formatted())
                NavigationLink {
                    WorkListView(title: "To Confirm", works: summary.toConfirm)
                } label: {
                    LabeledContent("To Confirm", value: summary.toConfirm.count.formatted())
                }
                .disabled(summary.toConfirm.isEmpty)
                .accessibilityIdentifier("to-confirm")
                NavigationLink {
                    WorkListView(title: "No Match", works: summary.unmatched)
                } label: {
                    LabeledContent("No Match", value: summary.unmatched.count.formatted())
                }
                .disabled(summary.unmatched.isEmpty)
                if summary.pending > 0 {
                    LabeledContent("Not Looked Up Yet", value: summary.pending.formatted())
                }
            }

            Section("Composers") {
                LabeledContent(
                    "With Life Dates", value: "\(summary.composersWithDates) of \(summary.composers)")
            }
        }
        .navigationTitle("MusicBrainz")
        .miniPlayerInset()
    }
}

/// Works that need a look, each opening its dates and sources.
private struct WorkListView: View {
    let title: String
    let works: [WorkIndex.Work]

    var body: some View {
        List(works) { work in
            NavigationLink {
                WorkSourcesView(work: work)
            } label: {
                VStack(alignment: .leading) {
                    Text(work.title)
                    Text(work.composer)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityIdentifier("status-work")
        }
        .navigationTitle(title)
        .miniPlayerInset()
    }
}
