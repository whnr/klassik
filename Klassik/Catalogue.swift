import Foundation

/// A catalogue number in a work title, such as "BWV 1007", "Op. 10 No. 1" or "KK IVa/16".
/// Klassik searches MusicBrainz by composer and this number when a work has no MusicBrainz ID.
struct CatalogueNumber: Equatable, Sendable {
    /// The prefix as MusicBrainz spells it in titles, such as "op." or "BWV".
    var prefix: String
    var number: String

    /// "op. 10 no. 1": the form that MusicBrainz titles use, so it can be a phrase in a search.
    var text: String { "\(prefix) \(number)" }

    /// Thematic catalogues come first: they name one work, an opus can hold several.
    private static let prefixes: [(pattern: String, prefix: String)] = [
        ("BWV", "BWV"), ("RV", "RV"), ("HWV", "HWV"), ("TWV", "TWV"), ("Hob\\.?", "Hob."), ("KV|K\\.?", "K."),
        ("D\\.?", "D."), ("KK", "KK"), ("S\\.", "S."), ("BB", "BB"), ("Sz\\.?", "Sz."), ("Wq\\.?", "Wq."),
        ("WoO", "WoO"), ("[Oo]p(?:us|\\.)?", "op."),
    ]

    /// The first catalogue number in the title, in the order of `prefixes`.
    static func find(in title: String) -> CatalogueNumber? {
        for (pattern, prefix) in prefixes {
            // A number starts with a digit or a Roman numeral, so "D major" and "Opera" do not match.
            let expression =
                "(?<![\\p{L}])(?:\(pattern))\\s*([0-9]+[a-z]?|[IVXL]+[a-z]?(?=[:/ ]))((?:[:/][0-9IVXa-z]+)*)"
                + "(?:,?\\s*[Nn]o\\.?\\s*([0-9]+))?"
            guard let regex = try? NSRegularExpression(pattern: expression),
                let match = regex.firstMatch(in: title, range: NSRange(title.startIndex..., in: title))
            else { continue }
            func group(_ index: Int) -> String? {
                Range(match.range(at: index), in: title).map { String(title[$0]) }.flatMap { $0.isEmpty ? nil : $0 }
            }
            var number = (group(1) ?? "") + (group(2) ?? "")
            if let item = group(3) { number += " no. \(item)" }
            return CatalogueNumber(prefix: prefix, number: number)
        }
        return nil
    }

    /// True if a MusicBrainz title names this number. MusicBrainz writes "op. 10 no. 1" and "KKIVa/16" alike.
    func matches(_ title: String) -> Bool {
        let wanted = Self.squeeze(text)
        let found = Self.squeeze(title)
        guard let range = found.range(of: wanted) else { return false }
        // "op. 1" must not match "op. 10".
        guard let next = found[range.upperBound...].first else { return true }
        return !next.isNumber
    }

    /// Lower case without accents, spaces, dots, commas and colons. MusicBrainz writes "op. 59: No. 1".
    private static func squeeze(_ text: String) -> String {
        text.lowercased().folding(options: .diacriticInsensitive, locale: nil)
            .filter { !" .,:\u{2009}\u{00a0}".contains($0) }
    }
}
