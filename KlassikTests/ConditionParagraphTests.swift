import Foundation
import Testing

@testable import Klassik

/// The conditions as one paragraph of chips: the pieces in reading order, and how a chip breaks over lines.
struct ConditionParagraphTests {
    static func term(_ name: String, _ scope: Search.Scope = .composers) -> Search.Term {
        Search.Term(scope: scope, name: name)
    }

    static let conditions = [
        Search.Condition(terms: [term("Bach"), term("Chopin")]),
        Search.Condition(terms: [term("Piano", .genres)]),
    ]

    @Test func conditionsReadAsOneSentence() {
        let paragraph = ConditionParagraph(conditions: Self.conditions, joining: nil)
        #expect(paragraph.pieces.map(\.kind) == [
            .chip(condition: 0, term: Self.term("Bach")), .or, .chip(condition: 0, term: Self.term("Chopin")),
            .plus(condition: 0, isMarked: false), .and,
            .chip(condition: 1, term: Self.term("Piano", .genres)), .plus(condition: 1, isMarked: false),
        ])
    }

    @Test func theMarkedConditionShowsItsPlusOn() {
        let paragraph = ConditionParagraph(conditions: Self.conditions, joining: 1)
        let plus = paragraph.pieces.compactMap { piece -> Bool? in
            if case .plus(_, let isMarked) = piece.kind { isMarked } else { nil }
        }
        #expect(plus == [false, true])
    }

    @Test func noConditionsLeaveNoPieces() {
        #expect(ConditionParagraph(conditions: [], joining: nil).pieces.isEmpty)
    }

    /// A joining index that no condition has marks nothing.
    @Test func aStaleJoiningMarksNothing() {
        let paragraph = ConditionParagraph(conditions: Self.conditions, joining: 5)
        #expect(!paragraph.pieces.contains { $0.kind == .plus(condition: 0, isMarked: true) })
        #expect(!paragraph.pieces.contains { $0.kind == .plus(condition: 1, isMarked: true) })
    }

    /// A chip and its x are one button for VoiceOver: one label names the term and the removal.
    @Test func aChipReadsAsOneRemoveButton() {
        let chip = ConditionParagraph(conditions: Self.conditions, joining: nil).pieces[0]
        #expect(chip.accessibilityLabel == L("Remove \(Self.term("Bach").name)"))
        #expect(chip.isButton)
    }

    @Test func wordsAreNotButtons() {
        let pieces = ConditionParagraph(conditions: Self.conditions, joining: nil).pieces
        #expect(pieces.filter { !$0.isButton }.map(\.kind) == [.or, .and])
    }

    /// The text of the paragraph keeps its pieces in order, one space between two, and the ranges of the pieces
    /// cover exactly their own text.
    @Test func rangesCoverThePieces() {
        let paragraph = ConditionParagraph(conditions: Self.conditions, joining: nil)
        let (text, ranges) = paragraph.layout()
        #expect(ranges.count == paragraph.pieces.count)
        for (piece, range) in zip(paragraph.pieces, ranges) {
            #expect((text as NSString).substring(with: range) == piece.text)
        }
        #expect(ranges.dropFirst().enumerated().allSatisfy { $0.element.location == ranges[$0.offset].upperBound + 1 })
    }

    /// A chip that fits on one line is round at both ends.
    @Test func aChipOnOneLineIsRoundAtBothEnds() {
        let segments = ChipSegment.split(NSRange(location: 4, length: 6), lines: [NSRange(location: 0, length: 30)])
        #expect(segments == [ChipSegment(range: NSRange(location: 4, length: 6), roundsStart: true, roundsEnd: true)])
    }

    /// A chip that breaks is square where it breaks and round at its real start and end.
    @Test func aBrokenChipIsSquareAtTheBreak() {
        let lines = (0..<3).map { NSRange(location: $0 * 10, length: 10) }
        let segments = ChipSegment.split(NSRange(location: 6, length: 18), lines: lines)
        #expect(segments == [
            ChipSegment(range: NSRange(location: 6, length: 4), roundsStart: true, roundsEnd: false),
            ChipSegment(range: NSRange(location: 10, length: 10), roundsStart: false, roundsEnd: false),
            ChipSegment(range: NSRange(location: 20, length: 4), roundsStart: false, roundsEnd: true),
        ])
    }

    /// A line that the chip does not touch adds no segment.
    @Test func aLineOutsideTheChipAddsNothing() {
        let lines = [NSRange(location: 0, length: 10), NSRange(location: 10, length: 10)]
        let segments = ChipSegment.split(NSRange(location: 12, length: 3), lines: lines)
        #expect(segments.map(\.range) == [NSRange(location: 12, length: 3)])
    }
}
