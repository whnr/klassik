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
        guard let composer = progress.composer else {
            return L("Looking up \(progress.done) of \(progress.total) works in Wikidata.")
        }
        return L("Looking up \(progress.done) of \(progress.total) works, now \(composer).")
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
                    LabeledContent("Status", value: summary.pending > 0 ? L("Waiting") : L("Up to date"))
                        .ink()
                }
                LabeledContent("Requests Since Start", value: enrichment.requests.localized())
                    .ink()
                Button("Look Up Missing Again", systemImage: "arrow.clockwise") {
                    Task { await enrichment.lookUpMissingAgain(index) }
                }
                .disabled(enrichment.progress != nil)
            } header: {
                Text("Lookup")
            } footer: {
                Text(
                    "Klassik lists each composer's works in MusicBrainz and matches them on this iPhone. MusicBrainz allows one request a second. Look up missing again after a fix in MusicBrainz."
                )
            }

            Section("Works with a WORK Tag") {
                LabeledContent("Works", value: summary.works.localized())
                    .ink()
                LabeledContent("Linked to MusicBrainz", value: summary.linked.localized())
                    .ink()
                    .accessibilityIdentifier("linked-count")
                LabeledContent("With a Year", value: summary.dated.localized())
                    .ink()
                NavigationLink(value: Page.worksToConfirm) {
                    LabeledContent("To Confirm", value: summary.toConfirm.count.localized())
                        .ink()
                }
                .disabled(summary.toConfirm.isEmpty)
                .accessibilityIdentifier("to-confirm")
                NavigationLink(value: Page.worksWithoutMatch) {
                    LabeledContent("No Match", value: summary.unmatched.count.localized())
                        .ink()
                }
                .disabled(summary.unmatched.isEmpty)
                if summary.pending > 0 {
                    LabeledContent("Not Looked Up Yet", value: summary.pending.localized())
                        .ink()
                }
            }

            Section("Composers") {
                LabeledContent(
                    "With Life Dates", value: L("\(summary.composersWithDates) of \(summary.composers)")
                )
                .ink()
            }

            PeopleSection(sweep: model.sweep, checked: model.people.cache.checked.count)
        }
        .pageTitle(L("MusicBrainz"))
    }
}

/// How far the Wikidata pass over the persons of the library got (ADR 0042).
struct PeopleSection: View {
    let sweep: PersonSweep
    let checked: Int

    var body: some View {
        Section {
            switch sweep.state {
            case .running(let done, let total):
                ProgressView(value: Double(done), total: Double(max(total, 1))) {
                    Text("Looking up \(done) of \(total) people")
                }
                .accessibilityIdentifier("people-progress")
            case .paused(.connection):
                Label("Paused: no suitable connection", systemImage: "pause.circle")
                    .foregroundStyle(Palette.textPrimary)
                    .accessibilityIdentifier("people-paused")
            case .paused(.slowDown(let until)):
                let retry = until.localizedRelative()
                Label(
                    "Paused: Wikidata asked for a pause. Klassik tries again \(retry).", systemImage: "pause.circle"
                )
                .foregroundStyle(Palette.textPrimary)
                .accessibilityIdentifier("people-paused")
            case .upToDate:
                LabeledContent("Status", value: L("Up to date"))
                    .ink()
                    .accessibilityIdentifier("people-status")
            case .idle:
                LabeledContent("Status", value: L("Waiting"))
                    .ink()
                    .accessibilityIdentifier("people-status")
            }
            LabeledContent("People Checked", value: checked.localized())
                .ink()
            if sweep.newCount > 0 {
                LabeledContent("New", value: sweep.newCount.localized())
                    .ink()
            }
            if sweep.dueCount > 0 {
                LabeledContent("Due for a New Check", value: sweep.dueCount.localized())
                    .ink()
            }
        } header: {
            Text("People from Wikidata")
        } footer: {
            Text(
                "Klassik looks up every composer and performer of your library, new people first, one at a time at the pace that Wikidata asks for. It asks again for living people after about \(PersonSweep.livingDays) days and for others after about a year, or after about 3 months when Wikidata does not know them. It waits for a connection that is not metered and not in Low Data Mode."
            )
        }
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
                .itemSeparator(first: work.id == works.first?.id, last: work.id == works.last?.id)
            }
        }
        .pageTitle(title)
    }
}
