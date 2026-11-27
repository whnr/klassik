import Foundation

/// SwiftUI `Text` has no hyphenation switch. A soft hyphen marks where the system dictionary allows a break; the
/// line breaker uses it only at a line end.
enum Hyphenation {
    private static let soft = "\u{00AD}"
    /// Words under this length stay whole, as a break in them reads worse than a short line.
    private static let shortestWord = 6

    /// The text with a soft hyphen at each place where the language allows a break.
    static func soften(_ text: String, locale: Locale) -> String {
        guard CFStringIsHyphenationAvailableForLocale(locale as CFLocale) else { return text }
        return text.split(separator: " ", omittingEmptySubsequences: false)
            .map { word in
                String(word).count < shortestWord ? String(word) : soften(word: String(word), locale: locale)
            }
            .joined(separator: " ")
    }

    private static func soften(word: String, locale: Locale) -> String {
        let ns = word as NSString
        let whole = CFRangeMake(0, ns.length)
        var breaks: [Int] = []
        var index = ns.length
        while index > 0 {
            let at = CFStringGetHyphenationLocationBeforeIndex(ns, index, whole, 0, locale as CFLocale, nil)
            if at == kCFNotFound || at <= 0 { break }
            breaks.append(at)
            index = at
        }
        var result = word
        for at in breaks {
            result.insert(contentsOf: soft, at: String.Index(utf16Offset: at, in: result))
        }
        return result
    }
}
