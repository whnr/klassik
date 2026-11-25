import Foundation
import Observation
import Synchronization

/// A language that the app speaks. A new language is a new case, a catalog column and a Wikipedia edition.
enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case english = "en"
    case german = "de"

    var id: String { rawValue }

    /// The name in its own language, so that a listener finds it whatever the app language is.
    var name: String {
        switch self {
        case .english: "English"
        case .german: "Deutsch"
        }
    }

    /// The first app language among preferred languages such as `Locale.preferredLanguages`. English when none.
    static func matching(_ preferred: [String]) -> AppLanguage {
        for tag in preferred {
            let code = Locale(identifier: tag).language.languageCode?.identifier
            if let found = code.flatMap(AppLanguage.init(rawValue:)) { return found }
        }
        return .english
    }
}

/// What the listener picked for the app language. `system` follows the device.
enum LanguageSetting: String, CaseIterable, Identifiable, Sendable {
    case system
    case english = "en"
    case german = "de"

    var id: String { rawValue }
    var language: AppLanguage? { AppLanguage(rawValue: rawValue) }
}

/// The language of fetched texts when the app language has none. `off` leaves such a text empty.
enum TextFallback: String, CaseIterable, Identifiable, Sendable {
    case english = "en"
    case german = "de"
    case off

    var id: String { rawValue }
    var language: AppLanguage? { AppLanguage(rawValue: rawValue) }
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

/// The language of the app, and the strings in it. SwiftUI literals follow `locale` through the environment. A
/// string that a view does not draw from a literal comes from `L`. Each read tracks `revision`, so that a view
/// draws again when the language changes.
@Observable
final class Localization: @unchecked Sendable {
    static let shared = Localization()
    static let languageKey = "settings.language"
    static let fallbackKey = "settings.textFallback"

    private struct Choice: Sendable {
        var setting: LanguageSetting
        var fallback: TextFallback
    }

    @ObservationIgnored private let choice: Mutex<Choice>
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let preferred: @Sendable () -> [String]
    private var revision = 0

    init(
        defaults: UserDefaults = .standard,
        preferred: @escaping @Sendable () -> [String] = { Locale.preferredLanguages }
    ) {
        self.defaults = defaults
        self.preferred = preferred
        choice = Mutex(
            Choice(
                setting: defaults.string(forKey: Self.languageKey).flatMap(LanguageSetting.init) ?? .system,
                fallback: defaults.string(forKey: Self.fallbackKey).flatMap(TextFallback.init) ?? .english))
    }

    // MARK: Reading

    var setting: LanguageSetting {
        _ = revision
        return choice.withLock { $0.setting }
    }

    var fallbackSetting: TextFallback {
        _ = revision
        return choice.withLock { $0.fallback }
    }

    /// The language of the app now.
    var language: AppLanguage {
        _ = revision
        return choice.withLock { $0.setting }.language ?? AppLanguage.matching(preferred())
    }

    /// The languages of fetched texts now.
    var textLanguages: TextLanguages {
        _ = revision
        return TextLanguages(app: language, fallback: choice.withLock { $0.fallback }.language)
    }

    /// The formats of the app language: numbers, dates, durations, lists and plurals. The device region stays when the
    /// device speaks the language, so that a German iPhone in Switzerland keeps its separators.
    var locale: Locale { locale(for: language) }

    func locale(for language: AppLanguage) -> Locale {
        if Locale.current.language.languageCode?.identifier == language.rawValue { return .current }
        return Locale(identifier: language.rawValue)
    }

    /// The strings of one language, or the main bundle when the build holds none for it.
    static func bundle(for language: AppLanguage) -> Bundle {
        Bundle.main.path(forResource: language.rawValue, ofType: "lproj").flatMap(Bundle.init(path:)) ?? .main
    }

    /// A string of the catalog in the app language, or in `language`.
    func string(_ key: String.LocalizationValue, in language: AppLanguage? = nil) -> String {
        let language = language ?? self.language
        return String(localized: key, bundle: Self.bundle(for: language), locale: locale(for: language))
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

    func select(_ setting: LanguageSetting) {
        choice.withLock { $0.setting = setting }
        defaults.set(setting.rawValue, forKey: Self.languageKey)
        revision += 1
    }

    func select(fallback: TextFallback) {
        choice.withLock { $0.fallback = fallback }
        defaults.set(fallback.rawValue, forKey: Self.fallbackKey)
        revision += 1
    }
}

/// A string of the catalog in the app language, for text that a view does not draw from a literal.
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

extension LanguageSetting {
    var title: String {
        switch self {
        case .system: L("Device Language")
        case .english: AppLanguage.english.name
        case .german: AppLanguage.german.name
        }
    }
}

extension TextFallback {
    var title: String {
        switch self {
        case .english: AppLanguage.english.name
        case .german: AppLanguage.german.name
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
