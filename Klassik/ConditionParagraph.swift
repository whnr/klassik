import Foundation

/// The conditions of a search as one paragraph: chips joined by small "and" and "or" words, and a "+ or" button at
/// the end of each condition. This is the model; `ChipParagraphView` draws it.
struct ConditionParagraph: Equatable {
    enum Kind: Equatable {
        case chip(condition: Int, term: Search.Term)
        case plus(condition: Int, isMarked: Bool)
        case and
        case or
    }

    struct Piece: Equatable {
        var kind: Kind
        var text: String

        /// A chip and its remove sign are one button for VoiceOver. A line break cannot split it.
        var accessibilityLabel: String {
            switch kind {
            case .chip(_, let term): L("Remove \(term.name)")
            case .plus: L("Or")
            case .and: L("and")
            case .or: L("or")
            }
        }

        var isButton: Bool {
            switch kind {
            case .chip, .plus: true
            case .and, .or: false
            }
        }
    }

    /// A no-break space ties the remove sign to the last word of a chip, and "+" to "or".
    static let tie = "\u{00A0}"
    static let remove = "\u{00D7}"

    private(set) var pieces: [Piece] = []

    /// `joining` is the condition that the next term joins with "or". Another index marks nothing.
    init(conditions: [Search.Condition], joining: Int?) {
        let plus = L("+ or").replacing(" ", with: Self.tie)
        for (position, condition) in conditions.enumerated() {
            if position > 0 { pieces.append(Piece(kind: .and, text: L("and"))) }
            for (offset, term) in condition.terms.enumerated() {
                if offset > 0 { pieces.append(Piece(kind: .or, text: L("or"))) }
                pieces.append(
                    Piece(kind: .chip(condition: position, term: term), text: term.name + Self.tie + Self.remove))
            }
            pieces.append(Piece(kind: .plus(condition: position, isMarked: joining == position), text: plus))
        }
    }

    /// The text of the paragraph, with one space between two pieces, and the range of each piece in it.
    func layout() -> (text: String, ranges: [NSRange]) {
        var text = ""
        var ranges: [NSRange] = []
        for (index, piece) in pieces.enumerated() {
            if index > 0 { text += " " }
            ranges.append(NSRange(location: (text as NSString).length, length: (piece.text as NSString).length))
            text += piece.text
        }
        return (text, ranges)
    }
}

/// The part of a chip on one line. A chip breaks across lines like text: it is round at its real start and its
/// real end and square where a line breaks it.
struct ChipSegment: Equatable {
    var range: NSRange
    var roundsStart: Bool
    var roundsEnd: Bool

    /// The segments of `chip`, one for each line that it touches. `lines` are the character ranges of the lines.
    static func split(_ chip: NSRange, lines: [NSRange]) -> [ChipSegment] {
        lines.compactMap { line in
            let part = NSIntersectionRange(chip, line)
            guard part.length > 0 else { return nil }
            return ChipSegment(
                range: part, roundsStart: part.location == chip.location,
                roundsEnd: part.upperBound == chip.upperBound)
        }
    }
}
