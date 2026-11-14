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
                PersonHero(
                    name: composer.name, facts: facts, topInset: proxy.safeAreaInsets.top, width: proxy.size.width
                )
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                BackTipRow()
                Section {
                    Button("Chronology", systemImage: "calendar") { navigator.select(.chronology) }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("composer-chronology")
                    Picker("Show", selection: $tab) {
                        Text("Works").tag(Tab.works)
                        Text("About").tag(Tab.about)
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("composer-tabs")
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                ResolutionNotice(tag: composer.name)
                switch tab {
                case .works: worksTab(catalogue)
                case .about: aboutTab(facts)
                }
            }
            .grounds()
            .ignoresSafeArea(.container, edges: .top)
        }
        .navigationTitle(composer.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ShuffleButton(works: composer.works) }
        .task(id: artistIDs) { await people.resolve(composer: composer.name, artistIDs: artistIDs) }
    }

    @ViewBuilder private func worksTab(_ catalogue: ComposerWorks) -> some View {
        let genres = catalogue.genres
        let rows = catalogue.rows(filter: chips)
        if !genres.isEmpty {
            GenreChips(genres: genres, selection: $chips)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        }
        Section {
            ForEach(rows) { row in
                switch row {
                case .work(let work):
                    WorkRow(work: work)
                case .set(let name, let works):
                    DisclosureGroup {
                        ForEach(works) { WorkRow(work: $0) }
                    } label: {
                        LabeledContent(name, value: "\(works.count)")
                            .ink()
                    }
                    .accessibilityIdentifier("set")
                }
            }
        }
        .listRowBackground(Palette.backgroundRow.color)
        if rows.isEmpty {
            Text("No works with these genres.")
                .foregroundStyle(Palette.textSecondary)
                .listRowBackground(Color.clear)
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
                .listRowBackground(Palette.backgroundRow.color)
            }
            if !facts.credits.isEmpty {
                Section {
                    ForEach(facts.credits, id: \.self) { credit in
                        CreditRow(credit: credit)
                    }
                } header: {
                    SectionHeading("Credits")
                }
                .listRowBackground(Palette.backgroundRow.color)
            }
        } else {
            Section {
                Text("Wikidata has no facts for this composer. Klassik shows your tags.")
                    .foregroundStyle(Palette.textSecondary)
            }
            .listRowBackground(Palette.backgroundRow.color)
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
        .listRowBackground(Palette.backgroundRow.color)
    }
}

/// Genre chips. Several chips join with "or".
private struct GenreChips: View {
    let genres: [String]
    @Binding var selection: Set<String>

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Space.s.points) {
                ForEach(genres, id: \.self) { genre in
                    let isOn = selection.contains(genre)
                    Button {
                        if isOn { selection.remove(genre) } else { selection.insert(genre) }
                    } label: {
                        Text(genre)
                            .typeStyle(.footnote)
                            .foregroundStyle(isOn ? Palette.onAccent : Palette.textPrimary)
                            .padding(.horizontal, Space.m.points)
                            .frame(minHeight: Measure.hitTarget)
                            .background(isOn ? Palette.accentFill : Palette.fillQuiet, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isOn ? .isSelected : [])
                    .accessibilityIdentifier("genre-chip")
                }
            }
            .padding(.horizontal, Space.l.points)
        }
    }
}

private struct CreditRow: View {
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
            .listRowBackground(Palette.backgroundRow.color)
        case .mixed(let names):
            Section {
                Text(
                    "The tag \"\(tag)\" holds works of \(names.formatted(.list(type: .and))). "
                        + "Retag them with full names. Klassik does not split a tag."
                )
                .ink()
                .accessibilityIdentifier("composer-mixed")
            }
            .listRowBackground(Palette.backgroundRow.color)
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
private struct PersonHero: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorSchemeContrast) private var contrast
    @AppStorage(TimelineSide.storageKey) private var side = TimelineSide.standard
    let name: String
    let facts: PersonFacts?
    let topInset: CGFloat
    let width: CGFloat
    @State private var portrait: LoadedPortrait?
    @State private var showsPicture = false

    private static let bodyHeight: CGFloat = 300
    /// The part of the frame, from the bottom, that holds the name and the facts line.
    private static let textShare: CGFloat = 0.45

    var body: some View {
        let frame = CGSize(width: width, height: topInset + Self.bodyHeight)
        let framing = portrait.map {
            PortraitFraming.rect(image: $0.image.size, frame: frame, face: $0.face)
        }
        ZStack(alignment: .bottomLeading) {
            if let portrait, let framing {
                picture(portrait, framing: framing, frame: frame)
            }
            VStack(alignment: .leading, spacing: Space.xs.points) {
                Text(name)
                    .typeStyle(.pageTitle)
                    .foregroundStyle(portrait == nil ? Palette.textPrimary.color : paper)
                if let line = facts?.descriptionLine {
                    Text(line)
                        .typeStyle(.subheadline)
                        .foregroundStyle(portrait == nil ? Palette.textSecondary.color : paper)
                        .accessibilityIdentifier("composer-description")
                }
            }
            .padding(.horizontal, Space.l.points)
            .padding(.vertical, Space.l.points)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
        }
        .frame(width: width, height: frame.height, alignment: .bottomLeading)
        .clipped()
        .task(id: facts?.portrait?.url) {
            portrait = nil
            guard let url = facts?.portrait?.url else { return }
            portrait = await PortraitLoader.load(url)
        }
        .fullScreenCover(isPresented: $showsPicture) {
            if let portrait {
                WholePicture(
                    image: portrait.image, credit: facts?.credits.first { $0.kind == .picture },
                    isPresented: $showsPicture)
            }
        }
    }

    private var paper: Color {
        Color(red: PictureScrim.text.red, green: PictureScrim.text.green, blue: PictureScrim.text.blue)
    }

    private func picture(_ portrait: LoadedPortrait, framing: CGRect, frame: CGSize) -> some View {
        // The scrim comes from the picture under the text, as the frame shows it.
        let visible = PortraitFraming.visible(of: framing, in: frame)
        let region = CGRect(
            x: visible.minX, y: visible.minY + visible.height * (1 - Self.textShare), width: visible.width,
            height: visible.height * Self.textShare)
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
                    .init(color: hallColour.opacity(0), location: 1 - Self.textShare * 1.4),
                    .init(color: hallColour.opacity(opacity), location: 1 - Self.textShare),
                    .init(color: hallColour.opacity(opacity), location: 1),
                ], startPoint: .top, endPoint: .bottom)
        }
        .frame(width: frame.width, height: frame.height)
        .contentShape(Rectangle())
        .onTapGesture { showsPicture = true }
        .accessibilityElement()
        .accessibilityLabel("Picture of \(name)")
        .accessibilityHint("Shows the whole picture with its credit.")
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("composer-picture")
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
        .accessibilityIdentifier("composer-whole-picture")
    }
}
