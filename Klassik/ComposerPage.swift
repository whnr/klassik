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

    var body: some View {
        let people = model.people
        let artistIDs = composer.works.compactMap { model.enrichment.facts(of: $0)?.composerID }
        let facts = people.facts(ofComposer: composer.name)
        let catalogue = ComposerWorks(composer)
        GeometryReader { proxy in
            List {
                Group { content(proxy: proxy, facts: facts, catalogue: catalogue) }
                    .listRowBackground(Color.clear)
            }
            .listStyle(.plain)
            .environment(\.defaultMinListRowHeight, 0)
            .scrollContentBackground(.hidden)
            .background(Palette.backgroundPage)
            .ignoresSafeArea(.container, edges: .top)
        }
        .navigationTitle(composer.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ShuffleButton(works: composer.works) }
        .task(id: artistIDs) { await people.resolve(composer: composer.name, artistIDs: artistIDs) }
    }

    @ViewBuilder private func content(
        proxy: GeometryProxy, facts: PersonFacts?, catalogue: ComposerWorks
    ) -> some View {
        PersonHero(
            name: composer.name, facts: facts, line: facts?.descriptionLine, kind: "composer",
            topInset: proxy.safeAreaInsets.top, width: proxy.size.width
        )
        .listRowInsets(EdgeInsets())
        .listRowSeparator(.hidden)
        BackTipRow()
        Button {
            navigator.select(.chronology)
        } label: {
            Text("Chronology")
                .typeStyle(.headline)
                .foregroundStyle(Palette.tint)
                .frame(maxWidth: .infinity, minHeight: Measure.hitTarget)
                .background(Palette.fillQuiet, in: .capsule)
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .listRowInsets(Self.insets(top: Space.l.points, bottom: 0))
        .listRowSeparator(.hidden)
        .accessibilityIdentifier("composer-chronology")
        Picker("Show", selection: $tab) {
            Text("Works").tag(Tab.works)
            Text("About").tag(Tab.about)
        }
        .pickerStyle(.segmented)
        .listRowInsets(Self.insets(top: Space.l.points, bottom: 0))
        .listRowSeparator(.hidden)
        .accessibilityIdentifier("composer-tabs")
        ResolutionNotice(tag: composer.name)
        switch tab {
        case .works: worksTab(catalogue)
        case .about: aboutTab(facts)
        }
    }

    /// Rows and the page title sit 20 pt from the edges, as on the work page.
    private static func insets(top: CGFloat, bottom: CGFloat) -> EdgeInsets {
        EdgeInsets(top: top, leading: 20, bottom: bottom, trailing: 20)
    }

    private static let rowInsets = insets(
        top: Space.betweenGroups.points / 2, bottom: Space.betweenGroups.points / 2)

    @ViewBuilder private func worksTab(_ catalogue: ComposerWorks) -> some View {
        let genres = catalogue.genres
        let rows = catalogue.rows(filter: chips)
        if !genres.isEmpty {
            GenreChips(genres: genres, selection: $chips)
                .listRowInsets(EdgeInsets(top: Space.m.points, leading: 0, bottom: 0, trailing: 0))
                .listRowSeparator(.hidden)
        }
        Section {
            ForEach(rows) { row in
                switch row {
                case .work(let work):
                    WorkRow(work: work)
                        .listRowInsets(Self.rowInsets)
                case .set(let name, let works):
                    DisclosureGroup {
                        ForEach(works) {
                            WorkRow(work: $0)
                                .listRowInsets(Self.rowInsets)
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: Space.inGroup.points) {
                            Text(name)
                                .typeStyle(.body)
                                .ink()
                            Text("\(works.count) works")
                                .typeStyle(.footnote)
                                .foregroundStyle(Palette.textSecondary)
                        }
                        .accessibilityElement(children: .combine)
                    }
                    .listRowInsets(Self.rowInsets)
                    .accessibilityIdentifier("set")
                }
            }
        } header: {
            // A plain list indents its section header by 16 pt. The page title and rows sit at 20 pt.
            CountedHeading("Works", count: rows.reduce(0) { $0 + $1.works.count })
                .padding(.leading, 4)
                .padding(.top, Space.betweenSections.points - Space.m.points)
        }
        if rows.isEmpty {
            Text("No works with these genres.")
                .foregroundStyle(Palette.textSecondary)
                .listRowInsets(Self.rowInsets)
        }
        if composer.works.contains(where: { !$0.isTagged }) {
            Section {
            } footer: {
                Text("Albums without a WORK tag show as one work each.")
            }
        }
    }

    @ViewBuilder private func aboutTab(_ facts: PersonFacts?) -> some View {
        if let facts {
            if let bio = facts.bio {
                Section {
                    Text(bio)
                        .ink()
                        .accessibilityIdentifier("composer-bio")
                } header: {
                    SectionHeading("Biography")
                }
            }
            if !facts.credits.isEmpty {
                Section {
                    ForEach(facts.credits, id: \.self) { credit in
                        CreditRow(credit: credit)
                    }
                } header: {
                    SectionHeading("Credits")
                }
            }
        } else {
            Section {
                Text("Wikidata has no facts for this composer. Klassik shows your tags.")
                    .foregroundStyle(Palette.textSecondary)
            }
        }
        Section {
            LabeledContent("Name in your tags", value: composer.name)
                .ink()
            LabeledContent("Works", value: composer.works.count.formatted())
                .ink()
            let people = model.people
            if people.resolution(ofComposer: composer.name) != nil, !people.loading.contains(composer.name) {
                Button("Choose Composer Again") { Task { await people.chooseAgain(composer: composer.name) } }
                    .accessibilityIdentifier("composer-choose-again")
            }
        } header: {
            SectionHeading("Your tags")
        }
    }
}

/// Genre chips. Several chips join with "or".
private struct GenreChips: View {
    let genres: [String]
    @Binding var selection: Set<String>

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Space.xs.points) {
                ForEach(genres, id: \.self) { genre in
                    let isOn = selection.contains(genre)
                    Button {
                        if isOn { selection.remove(genre) } else { selection.insert(genre) }
                    } label: {
                        Text(genre)
                            .typeStyle(.subheadline)
                            .lineLimit(1)
                            .foregroundStyle(isOn ? Palette.onAccent : Palette.textPrimary)
                            .padding(.horizontal, Space.m.points)
                            .frame(minHeight: height)
                            .background(isOn ? Palette.accentFill : Palette.fillQuiet, in: Capsule())
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isOn ? .isSelected : [])
                    .accessibilityIdentifier("genre-chip")
                }
            }
            .padding(.horizontal, 20)
        }
    }

    /// The specimen chip: smaller than a row, so the chips read as a filter, not as buttons of the page.
    @ScaledMetric(relativeTo: .subheadline) private var height: CGFloat = 30
}

struct CreditRow: View {
    let credit: PersonCredit

    var body: some View {
        if let url = PersonFactsService.trusted(credit.url) {
            Link(destination: url) { content }
        } else {
            content
        }
    }

    private var content: some View {
        VStack(alignment: .leading) {
            Text(credit.kind.title)
                .typeStyle(.footnote)
                .foregroundStyle(Palette.textSecondary)
            Text(credit.text)
                .ink()
        }
        .accessibilityElement(children: .combine)
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
            } header: {
                SectionHeading("Which composer is this?")
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
/// `kind` prefixes the accessibility identifiers. A performer's picture shows only when it is a portrait.
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
    @State private var portrait: LoadedPortrait?
    @State private var loaded = false
    @State private var showsPicture = false
    /// The height of the name and the facts line, which sets the blur and the scrim under them.
    @State private var textHeight: CGFloat = 96
    @ScaledMetric(space: .inGroup) private var gap: CGFloat

    /// The picture runs under the bars and keeps the specimen's proportion: 118% of the width, at most 470 pt.
    private var frame: CGSize {
        CGSize(width: width, height: max(min(width * 1.18, 470), topInset + 260))
    }

    /// The space stays reserved while a picture loads, so the name does not jump when it arrives.
    private var hasPicture: Bool {
        portrait != nil || (facts?.portrait != nil && !loaded)
    }

    var body: some View {
        // The load sits outside the branches: a switch between them must not restart it.
        Group {
            if hasPicture {
                let framing = portrait.map {
                    PortraitFraming.rect(image: $0.image.size, frame: frame, face: $0.face)
                }
                ZStack(alignment: .bottomLeading) {
                    if let portrait, let framing {
                        picture(portrait, framing: framing, frame: frame)
                    }
                    heading
                        .padding(.bottom, Space.m.points)
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: {
                            textHeight = $0
                        }
                }
                .frame(width: width, height: frame.height, alignment: .bottomLeading)
                .clipped()
            } else {
                // No picture: the name sits close under the back arrow, as a page title does.
                heading
                    .padding(.top, topInset + Space.xs.points)
                    .padding(.bottom, Space.s.points)
            }
        }
        .modifier(load)
    }

    private var load: PortraitLoad {
        PortraitLoad(
            task: PortraitTask(portrait: facts?.portrait, screen: screen), facts: facts, kind: kind,
            portrait: $portrait, loaded: $loaded, showsPicture: $showsPicture)
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: gap) {
            Text(name)
                .typeStyle(.pageTitle)
                .foregroundStyle(portrait == nil ? Palette.textPrimary.color : paper)
            if let line {
                Text(line)
                    .typeStyle(.subheadline)
                    .foregroundStyle(portrait == nil ? Palette.textSecondary.color : paper)
                    .accessibilityIdentifier("\(kind)-description")
            }
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private var screen: PortraitSize.Screen {
        PortraitSize.Screen(hero: frame, scale: displayScale)
    }

    fileprivate struct PortraitTask: Equatable {
        var portrait: PersonPortrait?
        var screen: PortraitSize.Screen
    }

    /// Loads the picture and presents it whole. Both branches of the hero carry it, so a load survives the switch.
    fileprivate struct PortraitLoad: ViewModifier {
        let task: PortraitTask
        let facts: PersonFacts?
        let kind: String
        @Binding var portrait: LoadedPortrait?
        @Binding var loaded: Bool
        @Binding var showsPicture: Bool

        func body(content: Content) -> some View {
            content
                .task(id: task) {
                    portrait = nil
                    loaded = false
                    defer { loaded = true }
                    guard let file = facts?.portrait else { return }
                    let result = await PortraitLoader.load(file, screen: task.screen)
                    portrait = kind == "performer" ? result.flatMap { $0.isPortrait ? $0 : nil } : result
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
        let height = max(frame.height, 1)
        // From the bottom: the text block with a margin, the blur strip, and the fade of the scrim (person.html).
        let under = min(1, (textHeight + Space.m.points) / height)
        let blurTop = min(1, (textHeight + 60) / height)
        let scrimTop = min(1, (textHeight + 140) / height)
        let region = CGRect(
            x: visible.minX, y: visible.minY + visible.height * (1 - under), width: visible.width,
            height: visible.height * under)
        let opacity = PictureScrim.opacity(
            over: portrait.brightestColour(in: region), increasedContrast: contrast == .increased)
        let hall = PictureScrim.hall
        let hallColour = Color(red: hall.red, green: hall.green, blue: hall.blue)
        let image = Image(uiImage: portrait.image).resizable()
        return ZStack {
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
                            .init(color: .black, location: 1 - under),
                        ], startPoint: .top, endPoint: .bottom)
                )
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
                ], startPoint: .top, endPoint: .bottom)
        }
        .frame(width: frame.width, height: frame.height)
        .contentShape(Rectangle())
        .onTapGesture { showsPicture = true }
        .accessibilityElement()
        .accessibilityLabel("Picture of \(name)")
        .accessibilityValue(density(portrait, framing: framing))
        .accessibilityHint("Shows the whole picture with its credit.")
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("\(kind)-picture")
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

/// The whole picture with its credit. The Close button closes it.
private struct WholePicture: View {
    let image: UIImage
    let credit: PersonCredit?
    @Binding var isPresented: Bool

    var body: some View {
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
            Button("Close") { isPresented = false }
                .buttonStyle(.bordered)
        }
        .padding(.vertical, Space.l.points)
        .background(Palette.backgroundPage)
        .accessibilityIdentifier("whole-picture")
    }
}
