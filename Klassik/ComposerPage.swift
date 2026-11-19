import SwiftUI

/// A composer as a person: a picture, the name, a description line, a Chronology button, and the tabs Works and
/// About (ADR 0017). Facts come from Wikidata; the tags stay the truth for the works.
struct ComposerPage: View {
    enum Tab: Hashable {
        case works, about
    }

    @Environment(AppModel.self) private var model
    @Environment(AppNavigator.self) private var navigator
    let composer: WorkIndex.Composer
    @State private var tab = Tab.works
    @State private var chips: Set<String> = []
    /// The open sets. Their works are rows of the list, so opening one adds rows below its title and the list
    /// keeps its offset. A system disclosure group scrolls the list to its new rows.
    @State private var openSets: Set<ComposerWorks.SetID> = []
    @AppStorage(ComposerWorks.separatesPartialKey) private var separatesPartial = true

    var body: some View {
        let people = model.people
        let artistIDs = composer.works.compactMap { model.enrichment.facts(of: $0)?.composerID }
        let facts = people.facts(ofComposer: composer.name)
        let catalogue = ComposerWorks(composer)
        GeometryReader { proxy in
            List {
                Group { content(proxy: proxy, facts: facts, catalogue: catalogue) }
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
        .navigationTitle(composer.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ShuffleButton(works: composer.works) }
        // A person page puts all its covers in front of the cover queue (ADR 0059).
        .onAppear { model.albumCovers.prefer(composer.works.flatMap { $0.recordings.compactMap(\.songs.first) }) }
        .task(id: artistIDs) { await people.resolve(composer: composer.name, artistIDs: artistIDs) }
    }

    @ViewBuilder private func content(
        proxy: GeometryProxy, facts: PersonFacts?, catalogue: ComposerWorks
    ) -> some View {
        PersonHero(
            name: composer.name, facts: facts, line: facts?.descriptionLine, kind: "composer",
            topInset: proxy.safeAreaInsets.top, width: proxy.size.width, spacesChronology: true
        )
        .listRowInsets(EdgeInsets())
        .listRowSeparator(.hidden)
        BackTipRow()
        Button {
            model.chronology.show(composer: composer.name, playing: model.playback.work)
            navigator.select(.chronology)
        } label: {
            Text("Chronology")
                .typeStyle(Layout.capsuleLabel)
                .foregroundStyle(Palette.tint)
                .frame(maxWidth: .infinity, minHeight: Layout.capsuleHeight)
                .background(Palette.fillQuiet, in: .capsule)
                .contentShape(.capsule)
        }
        .buttonStyle(FlatPress())
        // The gap above the button belongs to the hero, which knows whether a picture shows.
        .pageEdges()
        .listRowSeparator(.hidden)
        .accessibilityIdentifier("composer-chronology")
        PageTabs(tabs: [Tab.works, .about], title: { $0 == .works ? "Works" : "About" }, selection: $tab)
            .pageEdges(top: Layout.segmentedTop)
            .listRowSeparator(.hidden)
            .accessibilityIdentifier("composer-tabs")
        ResolutionNotice(tag: composer.name)
            .listRowSeparator(.hidden)
        switch tab {
        case .works: worksTab(catalogue)
        case .about: aboutTab(facts)
        }
    }

    @ViewBuilder private func worksTab(_ catalogue: ComposerWorks) -> some View {
        let genres = catalogue.genres
        let parts = catalogue.parts(filter: chips, separatingPartial: separatesPartial)
        if !genres.isEmpty {
            GenreChips(genres: genres, selection: $chips)
                .listRowInsets(EdgeInsets(top: Layout.chipsTop, leading: 0, bottom: 0, trailing: 0))
                .listRowSeparator(.hidden)
        }
        ForEach(parts) { part in
            worksSection(part)
        }
        let rows = parts.flatMap(\.rows)
        if rows.isEmpty {
            Text("No works with these genres.")
                .foregroundStyle(Palette.textSecondary)
                .listRowSeparator(.hidden)
        }
        if composer.works.contains(where: { !$0.isTagged }) {
            Section {
            } footer: {
                Text("Albums without a WORK tag show as one work each.")
            }
        }
    }

    @ViewBuilder private func worksSection(_ part: ComposerWorks.Part) -> some View {
        let rows = part.rows
        Section {
            CountedHeading(part.title, count: rows.reduce(0) { $0 + $1.works.count })
            ForEach(rows) { row in
                Group {
                    switch row {
                    case .work(let work):
                        WorkRow(work: work)
                    case .set(let name, let works):
                        setRow(id: part.setID(named: name), works: works, row: row, rows: rows)
                    }
                }
                .itemSeparator(first: row.id == rows.first?.id, last: row.id == rows.last?.id)
            }
        }
    }

    /// The title of a set stays where it is. Its works follow as rows below it, at once and without scrolling.
    @ViewBuilder private func setRow(
        id: ComposerWorks.SetID, works: [WorkIndex.Work], row: ComposerWorks.Row, rows: [ComposerWorks.Row]
    ) -> some View {
        let isOpen = openSets.contains(id)
        Button {
            var change = Transaction()
            change.disablesAnimations = true
            withTransaction(change) {
                if isOpen { openSets.remove(id) } else { openSets.insert(id) }
            }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: Layout.rowLineGap) {
                    Text(id.name)
                        .typeStyle(.body)
                        .ink()
                    Text("\(works.count) works")
                        .typeStyle(.footnote)
                        .foregroundStyle(Palette.textSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .typeStyle(.footnote)
                    .foregroundStyle(Palette.textSecondary)
                    .rotationEffect(.degrees(isOpen ? 90 : 0))
                    .accessibilityHidden(true)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityValue(isOpen ? "Expanded" : "Collapsed")
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("set")
        if isOpen {
            ForEach(works) {
                WorkRow(work: $0)
                    .padding(.leading, Layout.setMemberLeading - Layout.centredEdge)
                    .pageRow()
                    .itemSeparator(first: false, last: $0.id == works.last?.id && row.id == rows.last?.id)
            }
        }
    }

    @ViewBuilder private func aboutTab(_ facts: PersonFacts?) -> some View {
        if let facts {
            if let bio = facts.bio {
                Section {
                    SectionHeading("Biography")
                    Text(bio)
                        .ink()
                        .accessibilityIdentifier("composer-bio")
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
                Text("Wikidata has no facts for this composer. Klassik shows your tags.")
                    .foregroundStyle(Palette.textSecondary)
                    .listRowSeparator(.hidden)
            }
        }
        Section {
            SectionHeading("Your tags")
            let people = model.people
            let choosesAgain =
                people.resolution(ofComposer: composer.name) != nil && !people.loading.contains(composer.name)
            LabeledContent("Name in your tags", value: composer.name)
                .ink()
                .itemSeparator(first: true, last: false)
            LabeledContent("Works", value: composer.works.count.formatted())
                .ink()
                .itemSeparator(first: false, last: !choosesAgain)
            if choosesAgain {
                Button("Choose Composer Again") { Task { await people.chooseAgain(composer: composer.name) } }
                    .accessibilityIdentifier("composer-choose-again")
                    .itemSeparator(first: false, last: true)
            }
        }
    }
}

/// Genre chips. Several chips join with "or".
private struct GenreChips: View {
    let genres: [String]
    @Binding var selection: Set<String>

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Layout.chipGap) {
                ForEach(genres, id: \.self) { genre in
                    let isOn = selection.contains(genre)
                    Button {
                        if isOn { selection.remove(genre) } else { selection.insert(genre) }
                    } label: {
                        Text(genre)
                            .typeStyle(Layout.chipLabel)
                            .lineLimit(1)
                            .foregroundStyle(isOn ? Palette.onAccent : Palette.textPrimary)
                            .padding(.horizontal, Layout.chipPadding)
                            .frame(minHeight: height)
                            .background(isOn ? Palette.accentFill : Palette.fillQuiet, in: Capsule())
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isOn ? .isSelected : [])
                    .accessibilityIdentifier("genre-chip")
                }
            }
            .pagePadding()
        }
    }

    @ScaledMetric(relativeTo: .subheadline) private var height = Layout.chipHeight
}

/// One credit line as in the specimen: the source, then its link in the tint (person.html, `.link`).
/// Increase Contrast underlines the link in its own colour.
struct CreditRow: View {
    @Environment(\.colorSchemeContrast) private var contrast
    let credit: PersonCredit

    var body: some View {
        if let url = PersonFactsService.trusted(credit.url) {
            Link(destination: url) { line(link: credit.linkLabel(url)) }
                .accessibilityIdentifier("credit-\(credit.kind.rawValue)")
        } else {
            line(link: nil)
        }
    }

    private func line(link: String?) -> some View {
        words(link: link)
            .typeStyle(Layout.footnote)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
    }

    private func words(link: String?) -> Text {
        let lead = Text(credit.lead(linked: link != nil)).foregroundStyle(Palette.textPrimary.color)
        guard let link else { return lead }
        let label = Text(link).foregroundStyle(Palette.tint.color).underline(contrast == .increased)
        return Text("\(lead) \(label)")
    }
}

/// What the lookup says about the tag: a pick list, a notice about a mixed surname tag, or a failure.
private struct ResolutionNotice: View {
    @Environment(AppModel.self) private var model
    let tag: String

    var body: some View {
        let people = model.people
        switch people.resolution(ofComposer: tag) {
        case .pick(let matches):
            Section {
                SectionHeading("Which composer is this?")
                ForEach(matches) { match in
                    Button {
                        Task { await people.choose(match, forComposer: tag) }
                    } label: {
                        VStack(alignment: .leading) {
                            Text(match.name).ink()
                            if let description = match.description {
                                Text(description)
                                    .typeStyle(.subheadline)
                                    .foregroundStyle(Palette.textSecondary)
                            }
                        }
                    }
                    .accessibilityIdentifier("composer-match")
                }
                Button("None of These") { Task { await people.choose(nil, forComposer: tag) } }
            } footer: {
                Text("Your tag gives only \"\(tag)\" and your works do not say which composer it is.")
            }
        case .mixed(let names):
            Section {
                Text(
                    "The tag \"\(tag)\" holds works of \(names.formatted(.list(type: .and))). "
                        + "Retag them with full names. Klassik does not split a tag."
                )
                .ink()
                .accessibilityIdentifier("composer-mixed")
            }
        case .person:
            if !people.loading.contains(tag), people.facts(ofComposer: tag) == nil, people.lastError != nil {
                Section {
                    Text("Facts from Wikidata are not available now. Klassik tries again when you open this page.")
                        .foregroundStyle(Palette.textSecondary)
                }
                .listRowBackground(Color.clear)
            }
        case .unknown, nil:
            EmptyView()
        }
    }
}

/// The picture, the name and the description line. Without a picture the page shows the name on the plain ground.
/// `kind` prefixes the accessibility identifiers. Every picture shows (ADR 0043).
struct PersonHero: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.displayScale) private var displayScale
    @AppStorage(TimelineSide.storageKey) private var side = TimelineSide.standard
    let name: String
    let facts: PersonFacts?
    let line: String?
    let kind: String
    let topInset: CGFloat
    let width: CGFloat
    /// True when the Chronology button follows. The hero then keeps the specimen gap below it.
    var spacesChronology = false
    @State private var loadedPortrait: LoadedPortrait?
    private var portrait: LoadedPortrait? { PortraitLoader.ready(facts?.portrait) ?? loadedPortrait }
    @State private var showsPicture = false
    /// The height of the name and the facts line, which sets the blur and the scrim under them.
    @State private var textHeight: CGFloat = 96
    /// The right edge of the longest text line in the hero. Blur and scrim end beside it.
    @State private var textRight: CGFloat?
    @ScaledMetric(space: .inGroup) private var gap: CGFloat

    /// The picture runs under the bars and keeps the specimen's proportion: 118% of the width, at most 470 pt.
    /// The fade over the name and the room above it set the least height.
    private var frame: CGSize {
        CGSize(
            width: width,
            height: max(
                min(width * Layout.pictureRatio, Layout.pictureMaxHeight),
                textHeight + Layout.pictureFade + Layout.pictureAboveFade))
    }

    /// The space stays reserved for a picture that Wikidata names, loaded or not, so the name never jumps when it
    /// arrives or fails (ADR 0059).
    private var hasPicture: Bool {
        portrait != nil || facts?.portrait != nil
    }

    var body: some View {
        // The load sits on one container outside the branches: a switch between them must not restart it.
        VStack(spacing: 0) {
            if hasPicture {
                let framing = portrait.map {
                    PortraitFraming.rect(
                        image: $0.image.size, frame: frame, face: $0.framingFace(performer: kind == "performer"))
                }
                ZStack(alignment: .bottomLeading) {
                    if let portrait, let framing {
                        picture(portrait, framing: framing, frame: frame)
                    } else {
                        Rectangle().fill(Palette.fillQuiet)
                    }
                    heading
                        .padding(.bottom, Layout.personHeadBottom)
                        .onGeometryChange(for: CGFloat.self) {
                            $0.size.height
                        } action: {
                            textHeight = $0
                        }
                }
                .coordinateSpace(.named(HeroSpace.name))
                .frame(width: width, height: frame.height, alignment: .bottomLeading)
                .clipped()
                .padding(.bottom, spacesChronology ? Layout.pictureBottom + Layout.buttonRowTop : 0)
            } else {
                // No picture: the name sits close under the back arrow, as a page title does.
                // The width frame keeps the grouped list from insetting the name, as in the picture branch.
                heading
                    .frame(width: width, alignment: .leading)
                    .padding(.top, topInset + Layout.headTop)
                    .padding(.bottom, Layout.personHeadBottom + (spacesChronology ? Layout.buttonRowTop : 0))
            }
        }
        // The list moves as one unit; the full-width portrait stays fixed behind the moving name.
        .offset(x: -Layout.contentShift(side: side, timeline: model.showsTimeline))
        .environment(\.pageContentPositioned, false)
        .modifier(load)
    }

    private var load: PortraitLoad {
        PortraitLoad(
            task: PortraitTask(portrait: facts?.portrait, screen: screen, store: .pictures),
            facts: facts,
            portrait: $loadedPortrait, showsPicture: $showsPicture)
    }

    private var heading: some View {
        textLines
            .onGeometryChange(for: CGFloat.self) {
                $0.frame(in: .named(HeroSpace.name)).maxX
            } action: {
                textRight = $0
            }
            .pagePadding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .contain)
            .accessibilityAddTraits(.isHeader)
            .accessibilityIdentifier("\(kind)-name")
    }

    /// The name and the line, as wide as the longer of the two.
    private var textLines: some View {
        VStack(alignment: .leading, spacing: gap) {
            if model.recordingOrder.artist(named: name) != nil {
                FavouriteTitle(
                    title: name, isSet: model.recordingOrder.isFavourite(person: name),
                    action: { model.recordingOrder.toggleAtOnce(person: name) }, textIdentifier: "\(kind)-title",
                    ink: portrait == nil ? Palette.textPrimary.color : paper
                )
                .accessibilityIdentifier("favourite-\(kind)")
            } else {
                Text(name)
                    .typeStyle(Layout.pageTitle)
                    .foregroundStyle(portrait == nil ? Palette.textPrimary.color : paper)
            }
            if let line {
                Text(line)
                    .typeStyle(Layout.metaLine)
                    .foregroundStyle(portrait == nil ? Palette.textSecondary.color : paper)
                    .accessibilityIdentifier("\(kind)-description")
            }
        }
    }

    private var screen: PortraitSize.Screen {
        PortraitSize.Screen(hero: frame, scale: displayScale)
    }

    struct PortraitTask: Equatable {
        var portrait: PersonPortrait?
        var screen: PortraitSize.Screen
        var revision: Int

        @MainActor init(portrait: PersonPortrait?, screen: PortraitSize.Screen, store: ImageStore) {
            self.portrait = portrait
            self.screen = screen
            let files = portrait.map(PortraitLoader.files(of:)) ?? []
            revision = store.revision(of: files.map(\.absoluteString))
        }
    }

    /// Loads the picture and presents it whole. Both branches of the hero carry it, so a load survives the switch.
    fileprivate struct PortraitLoad: ViewModifier {
        let task: PortraitTask
        let facts: PersonFacts?
        @Binding var portrait: LoadedPortrait?
        @Binding var showsPicture: Bool

        func body(content: Content) -> some View {
            content
                .task(id: task) {
                    guard let file = facts?.portrait else {
                        portrait = nil
                        return
                    }
                    // A shown picture stays until its replacement loads.
                    if let result = await PortraitLoader.load(file, screen: task.screen), !Task.isCancelled {
                        portrait = result
                    }
                }
                .fullScreenCover(isPresented: $showsPicture) {
                    if let portrait {
                        WholePicture(
                            image: portrait.image, credit: facts?.credits.first { $0.kind == .picture },
                            isPresented: $showsPicture)
                    }
                }
        }
    }

    /// Picture pixels for each screen pixel in the hero. Only a UI test with stubbed facts reads it, as the
    /// accessibility value, so VoiceOver never speaks it.
    private func density(_ portrait: LoadedPortrait, framing: CGRect) -> String {
        #if DEBUG
            if PersonLaunchStub.fetch != nil {
                return String(format: "%.2f", portrait.image.size.width / (framing.width * displayScale))
            }
        #endif
        return ""
    }

    private var paper: Color {
        Color(red: PictureScrim.text.red, green: PictureScrim.text.green, blue: PictureScrim.text.blue)
    }

    private func picture(_ portrait: LoadedPortrait, framing: CGRect, frame: CGSize) -> some View {
        // The scrim comes from the picture under the text, as the frame shows it.
        let visible = PortraitFraming.visible(of: framing, in: frame)
        // From the bottom: the text block with a margin, the blur strip, and the fade of the scrim (picture.css).
        let geometry = ScrimGeometry(
            frame: frame, textHeight: textHeight, textRight: textRight ?? frame.width, margin: Space.m.points)
        let under = geometry.under
        let blurTop = geometry.blurTop
        let scrimTop = geometry.scrimTop
        // Only the text needs the contrast, so the measured region ends at the longest line.
        let region = CGRect(
            x: visible.minX, y: visible.minY + visible.height * (1 - under), width: visible.width * geometry.across,
            height: visible.height * under)
        let opacity = PictureScrim.opacity(
            over: portrait.brightestColour(in: region), increasedContrast: contrast == .increased)
        let hall = PictureScrim.hall
        let hallColour = Color(red: hall.red, green: hall.green, blue: hall.blue)
        let image = Image(uiImage: portrait.image).resizable()
        return Button {
            showsPicture = true
        } label: {
            ZStack {
                image
                    .frame(width: framing.width, height: framing.height)
                    .position(x: framing.midX, y: framing.midY)
                    .accessibilityHidden(true)
                // The name sits on a blur, which averages a small bright patch away (ADR 0034).
                image
                    .frame(width: framing.width, height: framing.height)
                    .position(x: framing.midX, y: framing.midY)
                    .blur(radius: 16)
                    .mask(
                        LinearGradient(
                            stops: [
                                .init(color: .clear, location: 1 - blurTop),
                                .init(color: .black, location: 1 - geometry.blurUnder),
                            ], startPoint: .top, endPoint: .bottom)
                    )
                    .mask(sideMask(geometry))
                    .accessibilityHidden(true)
                if model.playback.item != nil {
                    // Under the timeline the picture blurs and fades towards the hall colour, as under a bar.
                    // The fade only darkens, so the scrim below, measured on the sharp picture, still covers it.
                    ZStack {
                        image
                            .frame(width: framing.width, height: framing.height)
                            .position(x: framing.midX, y: framing.midY)
                            .blur(radius: 14)
                        hallColour.opacity(0.5)
                    }
                    .mask(edgeMask)
                    .accessibilityHidden(true)
                }
                // The scrim is the top layer, so that it lifts the text over the blurred strip as well.
                LinearGradient(
                    stops: [
                        .init(color: hallColour.opacity(0), location: 1 - scrimTop),
                        .init(color: hallColour.opacity(opacity), location: 1 - under),
                        .init(color: hallColour.opacity(opacity), location: 1),
                    ], startPoint: .top, endPoint: .bottom
                )
                .mask(sideMask(geometry))
            }
            .frame(width: frame.width, height: frame.height)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Picture of \(name)")
        .accessibilityValue(density(portrait, framing: framing))
        .accessibilityHint("Shows the whole picture with its credit.")
        .accessibilityIdentifier("\(kind)-picture")
    }

    /// Full beside the text, then a fade to nothing: the picture stays sharp and bright where no text is.
    private func sideMask(_ geometry: ScrimGeometry) -> some View {
        LinearGradient(
            stops: [
                .init(color: .black, location: geometry.sideFull),
                .init(color: .clear, location: geometry.sideClear),
            ], startPoint: .leading, endPoint: .trailing)
    }

    private var edgeMask: some View {
        let strip = min(1, (Measure.hitTarget + Space.l.points) / max(width, 1))
        let stops: [Gradient.Stop] =
            side == .right
            ? [.init(color: .clear, location: 1 - strip), .init(color: .black, location: 1)]
            : [.init(color: .black, location: 0), .init(color: .clear, location: strip)]
        return LinearGradient(stops: stops, startPoint: .leading, endPoint: .trailing)
    }
}

/// The whole picture with its credit, full screen. A swipe down or the system close button closes it, as for any
/// full-screen overlay. Flo chose this over the specimen's sheet with Done (sz-rs30.1.105.73).
private struct WholePicture: View {
    /// A drag down this far, or a flick that would carry this far, closes the picture.
    static let closeDistance = 120.0

    let image: UIImage
    let credit: PersonCredit?
    @Binding var isPresented: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drag = CGFloat.zero

    var body: some View {
        NavigationStack {
            VStack(spacing: Space.m.points) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityLabel("Whole picture")
                if let credit {
                    Text(credit.text)
                        .typeStyle(.footnote)
                        .foregroundStyle(Palette.textPrimary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, Space.l.points)
                }
            }
            .padding(.vertical, Space.l.points)
            .offset(y: drag)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Palette.backgroundPage)
            .contentShape(Rectangle())
            .gesture(close)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .close) { isPresented = false }
                        .accessibilityIdentifier("whole-picture-close")
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
        }
        .accessibilityIdentifier("whole-picture")
    }

    /// The picture follows the finger down. Short of the distance it springs back.
    private var close: some Gesture {
        DragGesture()
            .onChanged { drag = max(0, $0.translation.height) }
            .onEnded { value in
                if max(value.translation.height, value.predictedEndTranslation.height) > Self.closeDistance {
                    isPresented = false
                } else {
                    withAnimation(Motion.inPlace.animation(reduceMotion: reduceMotion)) { drag = 0 }
                }
            }
    }
}
