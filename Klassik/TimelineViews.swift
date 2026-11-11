import SwiftUI

/// The tagged works in the order they were composed, in sections by period.
struct WorkTimelineView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let enrichment = model.enrichment
        let timeline = Timeline(
            index: model.library.index, composed: { enrichment.composed($0)?.span },
            lifetime: { name in enrichment.composer(named: name).map { ($0.born, $0.died) } })
        PageList {
            ForEach(timeline.sections) { section in
                Section {
                    ForEach(section.entries) { TimelineRow(entry: $0) }
                } header: {
                    SectionHeading("\(section.period.title) · \(section.period.years)")
                }
            }
            if !timeline.undated.isEmpty {
                Section {
                    ForEach(timeline.undated) { work in
                        NavigationLink(value: Page.work(work.id)) {
                            VStack(alignment: .leading) {
                                Text(work.title)
                                    .ink()
                                Text(work.composer)
                                    .typeStyle(.subheadline)
                                    .foregroundStyle(Palette.textSecondary)
                            }
                        }
                    }
                } header: {
                    SectionHeading("Undated")
                } footer: {
                    Text("MusicBrainz has no dates for these works or their composers.")
                }
            }
            Section {
            } footer: {
                LookupStatus()
            }
        }
        .overlay {
            if timeline.sections.isEmpty && timeline.undated.isEmpty {
                ContentUnavailableView(
                    "No Works", systemImage: "calendar", description: Text("Works with a WORK tag appear here."))
            }
        }
        .navigationTitle("Chronology")
    }
}

/// One work on the timeline. A work without a date shows its composer's lifetime and is marked approximate.
private struct TimelineRow: View {
    let entry: Timeline.Entry
    @ScaledMetric(space: .m) private var gap: CGFloat
    /// Four figures of a year must fit at every text size.
    @ScaledMetric private var yearWidth = Measure.hitTarget

    var body: some View {
        NavigationLink(value: Page.work(entry.work.id)) {
            HStack(alignment: .firstTextBaseline, spacing: gap) {
                Text(entry.isApproximate ? "≈" : String(entry.span.start))
                    .foregroundStyle(entry.isApproximate ? Palette.textSecondary : Palette.textPrimary)
                    .frame(width: yearWidth, alignment: .leading)
                    .accessibilityLabel(entry.isApproximate ? "Approximate" : String(entry.span.start))
                VStack(alignment: .leading) {
                    Text(entry.work.title)
                        .ink()
                    Text(subtitle)
                        .typeStyle(.subheadline)
                        .foregroundStyle(Palette.textSecondary)
                }
            }
        }
        .accessibilityIdentifier("timeline-work")
    }

    private var subtitle: String {
        if entry.isApproximate { return "\(entry.work.composer) · undated, lived \(entry.span.text)" }
        let years = entry.span.start == entry.span.end ? nil : entry.span.text
        return [entry.work.composer, years].compactMap(\.self).joined(separator: " · ")
    }
}

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
                TextField(
                    "Your year",
                    value: Binding(
                        get: { enrichment.cache.years[work.id] },
                        set: { enrichment.setYear($0, for: work) }),
                    format: .number.grouping(.never)
                )
                .keyboardType(.numberPad)
                .accessibilityIdentifier("year")
                if let composed = facts?.composed, let source = facts?.source {
                    LabeledContent(
                        source == .wikidata ? "Wikidata (published)" : "MusicBrainz", value: composed.text
                    )
                    .ink()
                }
            } header: {
                Text("Composed")
            } footer: {
                Text("Your year stays on this device and wins over MusicBrainz and Wikidata.")
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
        .navigationTitle("Dates and Sources")
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
