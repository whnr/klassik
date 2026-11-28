import SwiftUI
import UIKit

/// The Daily pick of the Library tab: a sentence that flows around its cover on the right (the specimen Library).
/// A tap on the cover or the title opens the recording or album. A name opens its person.
struct DailyPickView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppNavigator.self) private var navigator
    let pick: LibraryPage.Pick

    private var edges: EdgeInsets { Layout.edges(side: .standard, timeline: false) }

    var body: some View {
        let cover = Layout.dailyPickCover
        ZStack(alignment: .topTrailing) {
            PickSentence(
                pieces: pick.sentence, cover: CGSize(width: cover + Layout.dailyPickGap, height: cover), open: open
            )
            .accessibilityIdentifier("library-pick-text")
            Button {
                open(pick.page)
            } label: {
                CoverImage(song: pick.cover, points: cover)
                    .clipShape(RoundedRectangle(cornerRadius: Layout.albumCorner))
                    .frame(width: cover, height: cover)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(pick.title)
            .accessibilityIdentifier("library-pick-cover")
        }
        .padding(.top, Layout.dailyPickTop)
        .padding(.bottom, Layout.dailyPickTop)
        .padding(.leading, edges.leading)
        .padding(.trailing, edges.trailing)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func open(_ page: Page) {
        let place = navigator.selection
        Task {
            switch page {
            case .composer, .performer: await model.preparePortrait(for: page, opening: true)
            default: break
            }
            navigator.open(page, in: place)
        }
    }
}

/// The sentence as text that breaks around an empty box at its top right corner. No SwiftUI text does this, so
/// TextKit lays it out. The names are links, so VoiceOver finds them in the rotor.
private struct PickSentence: UIViewRepresentable {
    let pieces: [LibraryPage.Piece]
    /// The box that the cover and its gap take.
    let cover: CGSize
    let open: (Page) -> Void
    @Environment(\.dynamicTypeSize) private var typeSize

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> PickTextView {
        let view = PickTextView()
        view.delegate = context.coordinator
        return view
    }

    func updateUIView(_ view: PickTextView, context: Context) {
        context.coordinator.targets = pieces.compactMap { piece in
            if case .name(_, let page) = piece { page } else { nil }
        }
        context.coordinator.open = open
        view.apply(pieces, cover: cover, typeSize: typeSize)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView view: PickTextView, context: Context) -> CGSize? {
        view.apply(pieces, cover: cover, typeSize: typeSize)
        let width = proposal.width ?? view.bounds.width
        return CGSize(width: width, height: view.height(fitting: width))
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var targets: [Page] = []
        var open: (Page) -> Void = { _ in }

        func textView(
            _ textView: UITextView, primaryActionFor textItem: UITextItem, defaultAction: UIAction
        ) -> UIAction? {
            guard case .link(let url) = textItem.content, let host = url.host, let position = Int(host),
                targets.indices.contains(position)
            else { return nil }
            let page = targets[position]
            return UIAction { [open] _ in open(page) }
        }
    }
}

final class PickTextView: UITextView {
    private let manager: NSLayoutManager
    private let box: NSTextContainer
    private var cover = CGSize.zero
    private var applied: (pieces: [LibraryPage.Piece], typeSize: DynamicTypeSize)?

    init() {
        let storage = NSTextStorage()
        let manager = NSLayoutManager()
        let box = NSTextContainer()
        storage.addLayoutManager(manager)
        manager.addTextContainer(box)
        self.manager = manager
        self.box = box
        super.init(frame: .zero, textContainer: box)
        isEditable = false
        isScrollEnabled = false
        isSelectable = true
        backgroundColor = .clear
        textContainerInset = .zero
        box.lineFragmentPadding = 0
        linkTextAttributes = [.foregroundColor: Self.tint]
    }

    required init?(coder: NSCoder) { nil }

    private static var tint: UIColor { UIColor(named: Palette.tint.rawValue) ?? .tintColor }

    func apply(_ pieces: [LibraryPage.Piece], cover: CGSize, typeSize: DynamicTypeSize) {
        self.cover = cover
        guard applied?.pieces != pieces || applied?.typeSize != typeSize else { return }
        applied = (pieces, typeSize)
        attributedText = Self.text(pieces)
        setNeedsLayout()
    }

    override func layoutSubviews() {
        exclude(width: bounds.width)
        super.layoutSubviews()
    }

    func height(fitting width: CGFloat) -> CGFloat {
        exclude(width: width)
        box.size = CGSize(width: width, height: .greatestFiniteMagnitude)
        manager.ensureLayout(for: box)
        return max(ceil(manager.usedRect(for: box).height), cover.height)
    }

    private func exclude(width: CGFloat) {
        let hole = CGRect(x: max(0, width - cover.width), y: 0, width: cover.width, height: cover.height)
        box.exclusionPaths = [UIBezierPath(rect: hole)]
    }

    private static func text(_ pieces: [LibraryPage.Piece]) -> NSAttributedString {
        let style = Layout.dailyPickText
        let size = UIFontMetrics(forTextStyle: .title2).scaledValue(for: style.size)
        let regular = UIFont.systemFont(ofSize: size)
        let italic = regular.fontDescriptor.withSymbolicTraits(.traitItalic).map { UIFont(descriptor: $0, size: size) }
        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = size * style.lineHeight
        paragraph.maximumLineHeight = size * style.lineHeight
        paragraph.hyphenationFactor = 1
        let ink = UIColor(named: Palette.textPrimary.rawValue) ?? .label
        let result = NSMutableAttributedString()
        var position = 0
        // The first name is the title, which stands out in italics.
        let title = pieces.firstIndex { if case .name = $0 { true } else { false } }
        for (index, piece) in pieces.enumerated() {
            var attributes: [NSAttributedString.Key: Any] = [
                .font: regular, .foregroundColor: ink, .paragraphStyle: paragraph,
            ]
            if case .name = piece {
                if index == title { attributes[.font] = italic ?? regular }
                attributes[.link] = URL(string: "klassik-pick://\(position)")
                attributes[.foregroundColor] = tint
                position += 1
            }
            result.append(NSAttributedString(string: piece.string, attributes: attributes))
        }
        return result
    }
}
