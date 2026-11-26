import Foundation
import Observation
import Synchronization

/// A language that the app speaks. The bundle declares the languages (the catalogs and `CFBundleLocalizations`), and
/// iOS offers them in Settings, Klassik, Language. A new language needs a catalog column, a line in `project.yml`
/// and a Wikipedia edition of the same code, and no code.
struct AppLanguage: RawRepresentable, Hashable, Identifiable, Sendable {
    let rawValue: String

    init(rawValue: String) { self.rawValue = rawValue }
    init(_ code: String) { self.init(rawValue: code) }

    var id: String { rawValue }

    /// The name in its own language, so that a listener finds it whatever the app language is.
    var name: String {
        Locale(identifier: rawValue).localizedString(forLanguageCode: rawValue) ?? rawValue
    }

    /// The language of the keys in the catalogs and of the texts that no catalog holds.
    static var source: AppLanguage { AppLanguage(Bundle.main.developmentLocalization ?? "en") }

    /// The languages that the bundle holds, the source language first.
    static func available(in bundle: Bundle = .main) -> [AppLanguage] {
        let first = source.rawValue
        let others = Set(bundle.localizations).subtracting([first, "Base"]).sorted()
        return ([first] + others).map { AppLanguage($0) }
    }

    /// The first of `all` among preferred languages such as `Bundle.preferredLocalizations`. The source language
    /// when none.
    static func matching(_ preferred: [String], among all: [AppLanguage] = AppLanguage.available()) -> AppLanguage {
        for tag in preferred {
            let code = Locale(identifier: tag).language.languageCode?.identifier
            if let found = all.first(where: { $0.rawValue == code }) { return found }
        }
        return .source
    }
}

/// The language of fetched texts when the app language has none. `off` leaves such a text empty.
enum TextFallback: Hashable, Identifiable, Sendable {
    case language(AppLanguage)
    case off

    /// What `UserDefaults` holds: a language code, or "off". A code that the bundle lacks gives the source language.
    init(stored: String?) {
        switch stored {
        case "off": self = .off
        case let code?: self = .language(AppLanguage.available().first { $0.rawValue == code } ?? .source)
        case nil: self = .language(.source)
        }
    }

    var stored: String {
        switch self {
        case .language(let language): language.rawValue
        case .off: "off"
        }
    }

    var id: String { stored }
    var language: AppLanguage? {
        if case .language(let language) = self { language } else { nil }
    }

    /// Every language of the bundle, then off.
    static var all: [TextFallback] { AppLanguage.available().map(TextFallback.language) + [.off] }
}

/// The languages in which fetched texts (a Wikidata description, a Wikipedia lead) are wanted, best first.
struct TextLanguages: Equatable, Sendable {
    var app: AppLanguage
    var fallback: AppLanguage?

    /// The app language, then the fallback when it is another one.
    var wanted: [AppLanguage] {
        guard let fallback, fallback != app else { return [app] }
        return [app, fallback]
    }

    /// Stored with each fetched text. Another key means that the text needs a new fetch.
    var key: String { wanted.map(\.rawValue).joined(separator: ">") }
}

/// The language of the app, and the strings in it. iOS picks the app language (Settings, Klassik, Language) and
/// starts the app again after a change, so the language is fixed for a run: SwiftUI literals, formats and plurals
/// follow the bundle, and no code overrides it. A string that a view does not draw from a literal comes from `L`.
/// Only the fallback language of fetched texts changes inside a run, so only its reads track `revision`.
@Observable
final class Localization: @unchecked Sendable {
    static let shared = Localization()
    static let fallbackKey = "settings.textFallback"
    /// The language that the main bundle resolved. A `Localization` made with another language (a test) reads its
    /// folder instead.
    static let bundleLanguage = AppLanguage.matching(Bundle.main.preferredLocalizations)

    @ObservationIgnored private let fallback: Mutex<TextFallback>
    @ObservationIgnored private let defaults: UserDefaults
    /// The language is fixed for a run, so it is resolved once.
    let language: AppLanguage
    private var revision = 0

    init(
        defaults: UserDefaults = .standard,
        preferred: @escaping @Sendable () -> [String] = { Bundle.main.preferredLocalizations }
    ) {
        self.defaults = defaults
        language = AppLanguage.matching(preferred())
        fallback = Mutex(TextFallback(stored: defaults.string(forKey: Self.fallbackKey)))
    }

    // MARK: Reading

    var fallbackSetting: TextFallback {
        _ = revision
        return fallback.withLock { $0 }
    }

    /// The languages of fetched texts now.
    var textLanguages: TextLanguages {
        TextLanguages(app: language, fallback: fallbackSetting.language)
    }

    /// The formats of the app language: numbers, dates, durations, lists and plurals. The device region stays when the
    /// device speaks the language, so that a German iPhone in Switzerland keeps its separators.
    var locale: Locale { locale(for: language) }

    func locale(for language: AppLanguage) -> Locale {
        if Locale.current.language.languageCode?.identifier == language.rawValue { return .current }
        return Locale(identifier: language.rawValue)
    }

    /// The strings of one language. The app language reads the main bundle, as iOS resolved it. Another language
    /// (a text in the fallback language, a test) reads its own folder, or the main bundle when the build holds none.
    func bundle(for language: AppLanguage) -> Bundle {
        if language == Self.bundleLanguage { return .main }
        return Bundle.main.path(forResource: language.rawValue, ofType: "lproj").flatMap(Bundle.init(path:)) ?? .main
    }

    /// A string of the catalog in the app language, or in `language`.
    func string(_ key: String.LocalizationValue, in language: AppLanguage? = nil) -> String {
        let language = language ?? self.language
        return String(localized: key, bundle: bundle(for: language), locale: locale(for: language))
    }

    /// A text of the engine library, which holds no catalog, in the app language. A text that the catalog lacks stays.
    func translated(_ english: String) -> String {
        let http = "The server answered with HTTP "
        if english.hasPrefix(http), let status = Int(english.dropFirst(http.count).dropLast()) {
            return string("The server answered with HTTP \(status).")
        }
        return string(String.LocalizationValue(english))
    }

    // MARK: Writing

    func select(fallback setting: TextFallback) {
        fallback.withLock { $0 = setting }
        defaults.set(setting.stored, forKey: Self.fallbackKey)
        revision += 1
    }
}

/// A string of the catalog in the app language, for text that a view does not draw from a literal. The short upper
/// case name keeps the many call sites readable, as `NSLocalizedString` does.
// swift-format-ignore: AlwaysUseLowerCamelCase
func L(_ key: String.LocalizationValue) -> String {
    Localization.shared.string(key)
}

// MARK: Formats of the app language

extension BinaryInteger {
    /// The number in the formats of the app language.
    func localized() -> String {
        formatted(IntegerFormatStyle<Self>(locale: Localization.shared.locale))
    }
}

extension BinaryFloatingPoint {
    func localized() -> String {
        formatted(FloatingPointFormatStyle<Self>(locale: Localization.shared.locale))
    }
}

extension Date {
    func localized(date: Date.FormatStyle.DateStyle, time: Date.FormatStyle.TimeStyle) -> String {
        formatted(Date.FormatStyle(date: date, time: time, locale: Localization.shared.locale))
    }

    /// "yesterday", "2 hours ago": the relative time in the app language.
    func localizedRelative() -> String {
        formatted(Date.RelativeFormatStyle(presentation: .named, locale: Localization.shared.locale))
    }
}

extension BinaryInteger {
    /// "4.2 MB" in the formats of the app language.
    func localizedByteCount() -> String {
        Int64(clamping: self).formatted(ByteCountFormatStyle(style: .file, locale: Localization.shared.locale))
    }
}

extension Array where Element == String {
    /// "A, B and C" in the app language.
    func localizedList(width: ListFormatStyle<StringStyle, [String]>.Width = .standard) -> String {
        formatted(.list(type: .and, width: width).locale(Localization.shared.locale))
    }
}

// MARK: Names in the pickers

extension TextFallback {
    var title: String {
        switch self {
        case .language(let language): language.name
        case .off: L("Off")
        }
    }
}

extension Duration {
    /// "3:07" or "1:03:07" in the formats of the app language.
    func localizedTime(_ pattern: Duration.TimeFormatStyle.Pattern) -> String {
        formatted(Duration.TimeFormatStyle(pattern: pattern, locale: Localization.shared.locale))
    }
}
