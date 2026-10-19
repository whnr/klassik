import SwiftUI

/// The tagged works in the order they were composed, in sections by period.
struct WorkTimelineView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let enrichment = model.enrichment
        let timeline = Timeline(
            index: model.library.index, composed: { enrichment.composed($0)?.span },
            lifetime: { name in enrichment.composer(named: name).map { ($0.born, $0.died) } })
        List {
            ForEach(timeline.sections) { section in
                Section("\(section.period.title) · \(section.period.years)") {
                    ForEach(section.entries) { TimelineRow(entry: $0) }
                }
            }
            if !timeline.undated.isEmpty {
                Section {
                    ForEach(timeline.undated) { work in
                        NavigationLink {
                            WorkView(work: work)
                        } label: {
                            VStack(alignment: .leading) {
                                Text(work.title)
                                Text(work.composer)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: {
                    Text("Undated")
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
        .navigationTitle("Timeline")
        .miniPlayerInset()
    }
}

/// One work on the timeline. A work without a date shows its composer's lifetime and is marked approximate.
private struct TimelineRow: View {
    let entry: Timeline.Entry

    var body: some View {
        NavigationLink {
            WorkView(work: entry.work)
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(entry.isApproximate ? "≈" : String(entry.span.start))
                    .monospacedDigit()
                    .foregroundStyle(entry.isApproximate ? .secondary : .primary)
                    .frame(width: 44, alignment: .leading)
                    .accessibilityLabel(entry.isApproximate ? "Approximate" : String(entry.span.start))
                VStack(alignment: .leading) {
                    Text(entry.work.title)
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
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

/// What the MusicBrainz lookup does now, for the footer of a list.
struct LookupStatus: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let enrichment = model.enrichment
        if enrichment.isRunning, enrichment.remaining > 0 {
            Text("Looking up \(enrichment.remaining) works and composers in MusicBrainz…")
        } else if let error = enrichment.lastError {
            Text("MusicBrainz lookup stopped: \(error) Klassik tries again at the next start.")
        } else {
            Text("Dates come from MusicBrainz and Wikidata. Your own years win.")
        }
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
        Form {
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
                        source == .wikidata ? "Wikidata (published)" : "MusicBrainz", value: composed.text)
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
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder private func link(_ link: Enrichment.Link, facts: WorkFacts?) -> some View {
        let enrichment = model.enrichment
        switch link {
        case .tagged(let id), .found(let id):
            LabeledContent("Work", value: facts?.title ?? (enrichment.isRunning ? "Looking up…" : "Not found"))
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
                .foregroundStyle(.secondary)
            ForEach(found) { candidate in
                Button {
                    Task { await enrichment.confirm(candidate, for: work) }
                } label: {
                    VStack(alignment: .leading) {
                        Text(candidate.title)
                            .foregroundStyle(Color.primary)
                        Text("Match \(candidate.score)%")
                            .font(.subheadline)
                            .foregroundStyle(Color.secondary)
                    }
                }
                .accessibilityIdentifier("candidate")
            }
            Button("None of These", systemImage: "xmark.circle") { enrichment.reject(work) }
        case .unmatched:
            Text("No MusicBrainz work matches.")
                .foregroundStyle(.secondary)
            lookUpAgain
        case .noCatalogue:
            Text("The title has no catalogue number, such as Op. 67 or BWV 1007, so Klassik does not search.")
                .foregroundStyle(.secondary)
        case .pending:
            Text("Not looked up yet.")
                .foregroundStyle(.secondary)
        }
    }

    private var lookUpAgain: some View {
        Button("Look Up Again", systemImage: "arrow.clockwise") {
            Task { await model.enrichment.lookUpAgain(work) }
        }
    }
}
