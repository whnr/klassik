import SwiftUI

/// The Chronology place: the overview of all composers, or one composer among the contemporaries
/// (ADR 0016, 0022, 0026). It draws what `Chronology` gives and owns only the gestures.
struct ChronologyView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppNavigator.self) private var navigator
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(TimelineSide.storageKey) private var side = TimelineSide.standard
    @State private var position = Chronology.Position(level: .overview, composer: nil)
    @State private var listed: ListedWorks?

    var body: some View {
        let enrichment = model.enrichment
        let people = model.people
        let chronology = Chronology(
            index: model.library.index, facts: { people.facts(ofComposer: $0) },
            year: { enrichment.composed($0)?.span.start })
        let focus = position.level == .composer ? chronology.composer(named: position.composer) : nil
        let insets = Layout.sideInsets(timelineOnLeft: model.showsTimeline ? side == .left : nil)
        VStack(alignment: .leading, spacing: 0) {
            ChronologyHead(chronology: chronology, focus: focus)
                .padding(.top, Layout.chronologyHeadTop)
                .padding(.leading, insets.left)
                .padding(.trailing, insets.right)
                .frame(minHeight: Layout.chronologyHeadHeight, alignment: .topLeading)
            GeometryReader { proxy in
                ChronologyChart(
                    chronology: chronology, focus: focus, playing: model.playback.work,
                    lastOpened: model.chronology.lastOpened, size: proxy.size, move: move, list: list
                )
            }
            .padding(.top, Layout.headBottom)
            .padding(.bottom, Layout.headBottom)
            .padding(.leading, side == .left ? Layout.chartTimelineGap : 0)
            .padding(.trailing, side == .right ? Layout.chartTimelineGap : 0)
        }
        .background(Palette.backgroundPage)
        .overlay {
            if chronology.composers.isEmpty {
                ContentUnavailableView(
                    "No Composers", systemImage: "calendar",
                    description: Text("Composers appear here when Wikidata gives their life dates."))
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(focus == nil ? "Composer" : "All") {
                    if focus == nil {
                        let name =
                            chronology.composer(named: position.composer)?.name ?? chronology.composers.first?.name
                        move(to: Chronology.Position(level: .composer, composer: name))
                    } else {
                        move(to: Chronology.Position(level: .overview, composer: focus?.name))
                    }
                }
                .disabled(chronology.composers.isEmpty)
                .accessibilityIdentifier("chronology-level")
            }
        }
        .pageTitle("Chronology")
        .sheet(item: $listed) { listed in
            ListedWorksSheet(listed: listed) { work in
                self.listed = nil
                navigator.open(.work(work.id), in: .chronology)
            }
        }
        .onChange(of: navigator.selection, initial: true) { _, place in
            guard place == .chronology else { return }
            position = model.chronology.open(chronology, playing: model.playback.work)
        }
        .onChange(of: chronology.composers.map(\.name)) {
            if navigator.selection == .chronology {
                position = model.chronology.open(chronology, playing: model.playback.work)
                return
            }
            // A sync or a lookup can take the composer off the chart.
            if position.level == .composer, chronology.composer(named: position.composer) == nil {
                position = chronology.opening(playing: nil, left: position)
            }
        }
    }

    private func move(to next: Chronology.Position) {
        withAnimation(Motion.glide.animation(reduceMotion: reduceMotion)) { position = next }
        model.chronology.keep(next)
    }

    private func list(_ row: Chronology.Row) {
        listed = ListedWorks(title: "\(row.years), \(row.title)", works: row.works)
    }
}

/// The name of the composer in focus, which opens the composer page, and the facts line (ADR 0022). The name is
/// a page title: `h1[class]` in specimen.css sets it over the `t-title2` class of chronology.html.
private struct ChronologyHead: View {
    let chronology: Chronology
    let focus: Chronology.Composer?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let focus {
                NavigationLink(value: Page.composer(focus.name)) {
                    Text(focus.name)
                        .typeStyle(Layout.pageTitle)
                        .foregroundStyle(Palette.textPrimary)
                        .lineLimit(1)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("chronology-name")
            } else {
                Text("All composers")
                    .typeStyle(Layout.pageTitle)
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(1)
                    .accessibilityAddTraits(.isHeader)
            }
            Text(line)
                .typeStyle(Layout.chronologyLine)
                .foregroundStyle(Palette.textSecondary)
        }
    }

    private var line: String {
        guard let focus else {
            guard let years = chronology.overviewYears else { return "" }
            let count = WorkIndex.Recording.count(chronology.composers.count, "composer")
            return "\(count), \(years.lowerBound + 10)–\(years.upperBound - 5)"
        }
        let life = focus.died.map { "\(focus.born)–\($0)" } ?? "born \(focus.born)"
        let active = focus.activeFrom.map { "active from \($0)" }
        return [life, WorkIndex.Recording.count(focus.works.count, "work"), active].compactMap(\.self)
            .joined(separator: ", ")
    }
}

/// The works behind one row that stands for several.
struct ListedWorks: Identifiable {
    var title: String
    var works: [WorkIndex.Work]
    var id: String { title }
}

private struct ListedWorksSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let listed: ListedWorks
    let open: (WorkIndex.Work) -> Void

    var body: some View {
        NavigationStack {
            // This drawer holds works, so it follows the plain page list at every detent (ADR 0063).
            PageList {
                ForEach(listed.works) { work in
                    Button {
                        open(work)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: Layout.rowLineGap) {
                                MarkedTitle(title: work.title, isFavourite: model.recordingOrder.isFavourite(work))
                                    .ink()
                                Text(WorkRow.detail(of: work, composed: model.enrichment.composed(work)?.span.text))
                                    .typeStyle(.footnote)
                                    .foregroundStyle(Palette.textSecondary)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right")
                                .typeStyle(.footnote)
                                .fontWeight(.semibold)
                                .foregroundStyle(Palette.textTertiary)
                        }
                    }
                    .buttonStyle(.plain)
                    .itemSeparator(first: work.id == listed.works.first?.id, last: work.id == listed.works.last?.id)
                    .accessibilityIdentifier("chronology-listed-work")
                }
            }
            .environment(\.pageHeading, "")
            .navigationTitle(listed.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(Palette.backgroundPage)
    }
}

/// The chart: lines, dots and rows at the places that `Chronology` and `Chronology.Chart` give. Each mark keeps
/// one identity across composers and levels, so a move glides lines and years instead of a cut (ADR 0016).
private struct ChronologyChart: View {
    typealias Chart = Chronology.Chart

    let chronology: Chronology
    let focus: Chronology.Composer?
    let playing: WorkIndex.Work?
    let lastOpened: String?
    let size: CGSize
    let move: (Chronology.Position) -> Void
    let list: (Chronology.Row) -> Void

    @Environment(AppNavigator.self) private var navigator
    @State private var scrub: Scrub?
    @State private var scrubEnded = Date.distantPast
    /// The footnote line of a row of works, scaled with Dynamic Type.
    @ScaledMetric(relativeTo: .footnote) private var rowLine = TypeStyle.footnote.size * TypeStyle.footnote.lineHeight

    struct Scrub: Equatable {
        var location: CGPoint
        var lane: Int?
    }

    struct Lane: Identifiable {
        var composer: Chronology.Composer
        var x: CGFloat
        var id: String { composer.name }
    }

    /// One drawn thing of the chart, at its centre.
    struct Mark: Identifiable {
        enum Kind {
            case band(Bool)
            case label(String)
            case tick(String)
            case line(Palette, dim: Bool, composer: String?)
            case dot(Palette, ring: Palette?, ringWidth: CGFloat)
        }

        var id: String
        var kind: Kind
        var center: CGPoint
        var size: CGSize
    }

    var body: some View {
        let lanes = self.lanes
        let picked = scrub?.lane.flatMap { lanes.indices.contains($0) ? lanes[$0].composer.name : nil }
        let scale = focus.map { chronology.scale(of: $0, height: size.height, rowHeight: rowHeight) }
        ZStack(alignment: .topLeading) {
            ForEach(marks(lanes: lanes, picked: picked, scale: scale)) { mark in
                view(of: mark)
                    .frame(width: mark.size.width, height: mark.size.height)
                    .position(mark.center)
            }
            if let focus, let scale {
                let left = Chart.rowsX(width: size.width)
                ForEach(chronology.rows(of: focus, scale: scale)) { row in
                    ChronologyRow(row: row, marked: row.works.contains { $0.id == playing?.id }) { open(row) }
                        .frame(width: max(0, size.width - left), height: rowHeight, alignment: .leading)
                        .position(x: left + (size.width - left) / 2, y: row.y)
                }
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .clipped()
        .overlay(alignment: .topLeading) {
            if let scrub, let picked {
                Text(picked)
                    .typeStyle(Layout.workRow)
                    .foregroundStyle(Palette.textPrimary)
                    .padding(.vertical, Layout.pickLabelVertical)
                    .padding(.horizontal, Layout.pickLabelHorizontal)
                    .background(Palette.backgroundElevated, in: .rect(cornerRadius: Layout.pickLabelCorner))
                    .shadow(
                        color: .black.opacity(Layout.pickLabelShadowOpacity), radius: Layout.pickLabelShadow / 2,
                        y: Layout.pickLabelShadowY
                    )
                    .fixedSize()
                    .position(
                        x: min(max(scrub.location.x, Chart.pickInset), size.width - Chart.pickInset),
                        y: scrub.location.y - Layout.pickLabelAbove
                    )
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .contentShape(.rect)
        .onTapGesture(coordinateSpace: .local) { point in tap(at: point, lanes: lanes, scale: scale) }
        .simultaneousGesture(scrubGesture(lanes: lanes))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("chronology-chart")
    }

    private var rowHeight: CGFloat { rowLine + Chart.rowPadding }

    // MARK: Lanes

    private var lanes: [Lane] {
        if let focus {
            let people = chronology.lanes(of: focus)
            return people.enumerated().map {
                Lane(composer: $1, x: Chart.laneX($0, count: people.count, width: size.width))
            }
        }
        return chronology.composers.enumerated().map {
            Lane(composer: $1, x: Chart.overviewX($0, count: chronology.composers.count, width: size.width))
        }
    }

    /// The width and colour of a line: picked by a scrub, playing (accent), focus or last opened (ink), or plain.
    private func lineStyle(_ composer: Chronology.Composer, picked: String?) -> (width: CGFloat, colour: Palette) {
        if composer.name == picked { return (Layout.linePicked, .textPrimary) }
        if composer.name == playing?.composer { return (Layout.linePlaying, .tint) }
        if composer.name == focus?.name || (focus == nil && composer.name == lastOpened) {
            return (Layout.lineMarked, .textPrimary)
        }
        return (Layout.line, .textTertiary)
    }

    // MARK: Marks

    private func marks(lanes: [Lane], picked: String?, scale: Chronology.Scale?) -> [Mark] {
        var marks: [Mark] = []
        func line(_ key: String, _ lane: Lane, from top: CGFloat, to bottom: CGFloat, dim: Bool, picked: String?) {
            let style = lineStyle(lane.composer, picked: picked)
            let isFocus = lane.composer == focus
            marks.append(
                Mark(
                    id: key + lane.composer.name,
                    kind: .line(
                        style.colour, dim: dim && lane.composer.name != picked,
                        composer: isFocus ? nil : lane.composer.name),
                    center: CGPoint(x: lane.x, y: (top + bottom) / 2),
                    size: CGSize(width: style.width, height: max(style.width, bottom - top))))
        }
        guard let focus, let scale else {
            guard let years = chronology.overviewYears else { return [] }
            let y = { (year: Int) in Chart.y(year, in: years, height: size.height) }
            for (index, period) in Chronology.periods.enumerated()
            where period.end >= years.lowerBound && period.start <= years.upperBound {
                let top = y(max(period.start, years.lowerBound))
                let bottom = y(min(period.end, years.upperBound))
                marks.append(
                    Mark(
                        id: "band:" + period.name, kind: .band(index.isMultiple(of: 2)),
                        center: CGPoint(x: size.width / 2, y: (top + bottom) / 2),
                        size: CGSize(width: size.width, height: max(0, bottom - top))))
                // A band too short for its name, such as the edge of a period, shows no name.
                guard bottom - top >= Chart.bandLabelTop + rowLine else { continue }
                let labelWidth = max(0, size.width - Layout.bandLabelLeading)
                marks.append(
                    Mark(
                        id: "bandl:" + period.name, kind: .label(period.name),
                        center: CGPoint(
                            x: Layout.bandLabelLeading + labelWidth / 2,
                            y: top + Chart.bandLabelTop + rowLine / 2),
                        size: CGSize(width: labelWidth, height: rowLine)))
            }
            for lane in lanes {
                line(
                    "line:", lane, from: y(lane.composer.born), to: y(lane.composer.end(now: chronology.now)),
                    dim: false, picked: picked)
            }
            return marks
        }
        for year in stride(from: (focus.born + 9) / 10 * 10, through: focus.end(now: chronology.now), by: 10) {
            marks.append(
                Mark(
                    id: "tick:\(year)", kind: .tick(String(year)),
                    center: CGPoint(x: Layout.tickWidth / 2, y: scale.y(year)),
                    size: CGSize(width: Layout.tickWidth, height: rowLine)))
        }
        for lane in lanes {
            for (index, segment) in chronology.segments(of: lane.composer).enumerated() {
                line(
                    index == 0 ? "line:" : "linea:", lane, from: scale.y(segment.from), to: scale.y(segment.to),
                    dim: segment.dim, picked: picked)
            }
            let isFocus = lane.composer == focus
            let plays = lane.composer.name == playing?.composer
            for work in lane.composer.dated {
                let kind: Mark.Kind
                let width: CGFloat
                if work.id == playing?.id {
                    kind = .dot(.backgroundGrouped, ring: .tint, ringWidth: Layout.dotMarkedRing)
                    width = Layout.dotMarked
                } else if isFocus {
                    kind = .dot(plays ? .tint : .textPrimary, ring: nil, ringWidth: Layout.dotFocusRing)
                    width = Layout.dotFocus
                } else {
                    kind = .dot(plays ? .tint : .textTertiary, ring: nil, ringWidth: 0)
                    width = Layout.dot
                }
                marks.append(
                    Mark(
                        id: "dot:" + work.id, kind: kind,
                        center: CGPoint(x: lane.x, y: scale.y(work.year ?? focus.born)),
                        size: CGSize(width: width, height: width)))
            }
        }
        return marks
    }

    @ViewBuilder private func view(of mark: Mark) -> some View {
        switch mark.kind {
        case .band(let filled):
            Rectangle()
                .fill(filled ? Palette.fillQuiet.color : .clear)
                .accessibilityHidden(true)
        case .label(let text):
            Text(text)
                .typeStyle(Layout.chronologyYear)
                .foregroundStyle(Palette.textSecondary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityHidden(true)
        case .tick(let text):
            Text(text)
                .typeStyle(Layout.chronologyYear)
                .monospacedDigit()
                .foregroundStyle(Palette.textSecondary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .accessibilityHidden(true)
        case .line(let colour, let dim, let composer):
            let shape = Capsule().fill(colour).opacity(dim ? Layout.lineDim : 1)
            if let composer, let lane = chronology.composer(named: composer), !mark.id.hasPrefix("linea:") {
                shape
                    .accessibilityElement()
                    .accessibilityLabel(composer)
                    .accessibilityValue(lane.died.map { "\(lane.born)–\($0)" } ?? "born \(lane.born)")
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction { move(Chronology.Position(level: .composer, composer: composer)) }
                    .accessibilityIdentifier("chronology-line")
            } else {
                shape.accessibilityHidden(true)
            }
        case .dot(let fill, let ring, let ringWidth):
            if let ring {
                Circle().fill(fill)
                    .overlay { Circle().strokeBorder(ring, lineWidth: ringWidth) }
                    .accessibilityHidden(true)
            } else {
                // A focus dot sits on a ring of the ground, so that it stands off its line.
                Circle().fill(fill)
                    .background { Circle().fill(Palette.backgroundGrouped).padding(-ringWidth) }
                    .accessibilityHidden(true)
            }
        }
    }

    // MARK: Gestures

    private var tapIsLive: Bool {
        scrub == nil && Date.now.timeIntervalSince(scrubEnded) > Chart.tapAfterScrub
    }

    /// A row of one work opens its work page; a row of several lists them (ADR 0022).
    private func open(_ row: Chronology.Row) {
        guard tapIsLive else { return }
        if !row.opensList {
            navigator.open(.work(row.works[0].id), in: .chronology)
        } else {
            list(row)
        }
    }

    /// A tap picks a work of the focus composer on its dot or beside the focus line. In the overview it opens the
    /// nearest line. The rows are buttons of their own (ADR 0016, 0022).
    private func tap(at point: CGPoint, lanes: [Lane], scale: Chronology.Scale?) {
        guard tapIsLive else { return }
        guard let focus, let scale else {
            guard let near = lanes.min(by: { abs($0.x - point.x) < abs($1.x - point.x) }) else { return }
            move(Chronology.Position(level: .composer, composer: near.composer.name))
            return
        }
        guard let lane = lanes.first(where: { $0.composer == focus }), abs(point.x - lane.x) < Chart.focusReach
        else { return }
        let distance = { (work: Chronology.Work) in abs(scale.y(work.year ?? focus.born) - point.y) }
        if let near = focus.dated.min(by: { distance($0) < distance($1) }), distance(near) < Chart.dotReach {
            navigator.open(.work(near.id), in: .chronology)
        }
    }

    /// A sideways drag scrubs across the lines on the screen: the chart width maps onto them in order. The chart
    /// stays until the finger lifts, then glides to the composer under it. It never zooms (ADR 0022).
    private func scrubGesture(lanes: [Lane]) -> some Gesture {
        DragGesture(minimumDistance: Chart.scrubStart, coordinateSpace: .local)
            .onChanged { drag in
                // A drag from the leading screen edge is the system back swipe (ADR 0056), not a scrub.
                if scrub == nil, drag.startLocation.x < Layout.edge { return }
                if scrub == nil, abs(drag.translation.width) <= abs(drag.translation.height) { return }
                scrub = Scrub(
                    location: drag.location,
                    lane: Chronology.lane(at: drag.location.x, width: size.width, count: lanes.count))
            }
            .onEnded { _ in
                guard let ended = scrub else { return }
                scrub = nil
                scrubEnded = .now
                guard let index = ended.lane, lanes.indices.contains(index) else { return }
                move(Chronology.Position(level: .composer, composer: lanes[index].composer.name))
            }
    }
}

/// A row in the column of works: the year or span, then the title or the count. The playing work takes the tint.
private struct ChronologyRow: View {
    @Environment(AppModel.self) private var model
    let row: Chronology.Row
    let marked: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .firstTextBaseline, spacing: Layout.workRowGap) {
                Text(row.years)
                    .monospacedDigit()
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize()
                MarkedTitle(
                    title: row.title,
                    isFavourite: !row.opensList && model.recordingOrder.isFavourite(row.works[0])
                )
                .foregroundStyle(marked ? Palette.tint : Palette.textPrimary)
                .lineLimit(1)
                .truncationMode(.tail)
            }
            .typeStyle(Layout.workRow)
            .padding(.horizontal, Layout.workRowPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect(cornerRadius: Layout.workRowCorner))
        }
        .buttonStyle(ChronologyRowPress())
        .accessibilityLabel("\(row.years), \(row.title)")
        .accessibilityAddTraits(marked ? .isSelected : [])
        .accessibilityIdentifier(row.opensList ? "chronology-works" : "chronology-work")
    }
}

/// The pressed row takes the quiet fill, as `.wrow:active` in the specimen.
private struct ChronologyRowPress: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                configuration.isPressed ? Palette.fillQuiet.color : .clear,
                in: .rect(cornerRadius: Layout.workRowCorner))
    }
}
