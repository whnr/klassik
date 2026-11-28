import Foundation
import Testing

@testable import Klassik
@testable import KlassikEngine

/// The app language, its catalog and the formats that follow it (sz-odf9). Tests name concrete languages to read
/// their texts; the app code names none.
extension AppLanguage {
    static let english = AppLanguage("en")
    static let german = AppLanguage("de")
}

struct LocalizationTests {
    /// A store of its own, so that a test never changes the fallback language of the running app.
    private func localization(
        _ language: AppLanguage = .english, fallback: TextFallback = .language(.english)
    ) -> Localization {
        let defaults = UserDefaults(suiteName: "LocalizationTests-\(UUID().uuidString)")!
        let localization = Localization(defaults: defaults, preferred: { [language.rawValue] })
        localization.select(fallback: fallback)
        return localization
    }

    // MARK: Choosing the language

    @Test func theBundleDeclaresTheLanguages() {
        let available = AppLanguage.available()
        #expect(available.first == AppLanguage.source)
        #expect(available.contains(.english))
        #expect(available.contains(.german))
    }

    /// iOS lists the languages in the order of the listener. The first one that the app speaks wins.
    @Test func takesTheFirstPreferredLanguageThatTheAppSpeaks() {
        let available = [AppLanguage.english, .german]
        #expect(AppLanguage.matching(["de-DE", "en"], among: available) == .german)
        #expect(AppLanguage.matching(["fr-FR", "de-AT", "en"], among: available) == .german)
        #expect(AppLanguage.matching(["en-GB"], among: available) == .english)
        #expect(AppLanguage.matching(["fr-FR"], among: available) == .source)
        #expect(AppLanguage.matching([], among: available) == .source)
    }

    @Test func aLanguageNeedsNoCodeBesidesTheBundle() {
        let french = AppLanguage("fr")
        #expect(AppLanguage.matching(["fr-CA"], among: [.english, french]) == french)
        #expect(french.name == "français")
        #expect(PersonFactsService.wikipedia(french).host == "fr.wikipedia.org")
    }

    @Test func remembersTheFallback() {
        let defaults = UserDefaults(suiteName: "LocalizationTests-\(UUID().uuidString)")!
        let first = Localization(defaults: defaults, preferred: { ["en"] })
        first.select(fallback: .off)
        #expect(Localization(defaults: defaults, preferred: { ["en"] }).fallbackSetting == .off)
        first.select(fallback: .language(.german))
        #expect(Localization(defaults: defaults, preferred: { ["en"] }).fallbackSetting == .language(.german))
    }

    @Test func aFallbackThatTheBundleLacksGivesTheSourceLanguage() {
        #expect(TextFallback(stored: "xx") == .language(.source))
        #expect(TextFallback(stored: nil) == .language(.source))
        #expect(TextFallback(stored: "off") == .off)
    }

    // MARK: Languages of fetched texts

    @Test func textLanguagesPutTheAppFirst() {
        #expect(localization(.german, fallback: .language(.english)).textLanguages.wanted == [.german, .english])
        #expect(localization(.german, fallback: .language(.english)).textLanguages.key == "de>en")
        #expect(localization(.english, fallback: .language(.german)).textLanguages.key == "en>de")
    }

    @Test func theFallbackNeverRepeatsTheAppLanguage() {
        #expect(localization(.english, fallback: .language(.english)).textLanguages.wanted == [.english])
        #expect(localization(.german, fallback: .language(.german)).textLanguages.key == "de")
    }

    @Test func fallbackOffWantsTheAppLanguageOnly() {
        #expect(localization(.german, fallback: .off).textLanguages.wanted == [.german])
    }

    // MARK: The catalog

    @Test func theCatalogHoldsTheLanguages() {
        let loc = localization()
        #expect(loc.string("Settings", in: .english) == "Settings")
        #expect(loc.string("Settings", in: .german) == "Einstellungen")
        #expect(loc.string("Library", in: .german) == "Bibliothek")
    }

    @Test func rowFilterTitlesUseTheCatalog() {
        let loc = localization()
        for language in [AppLanguage.english, .german] {
            let base = loc.string("Composers", in: language)
            let qualifier = loc.string("filtered", in: language)
            let title = loc.string("\(base), \(qualifier)", in: language)
            #expect(title == (language == .german ? "Komponisten, gefiltert" : "Composers, filtered"))
            #expect(loc.string("Filter", in: language) == "Filter")
        }
    }

    @Test func pluralsFollowTheLanguage() {
        let loc = localization()
        let one = 1
        let many = 3
        #expect(loc.string("\(one) recordings", in: .english) == "1 recording")
        #expect(loc.string("\(many) recordings", in: .english) == "3 recordings")
        #expect(loc.string("\(one) recordings", in: .german) == "1 Aufnahme")
        #expect(loc.string("\(many) recordings", in: .german) == "3 Aufnahmen")
        #expect(loc.string("\(one) movements", in: .german) == "1 Satz")
        #expect(loc.string("\(many) movements", in: .german) == "3 Sätze")
    }

    /// Every message of the engine library has a German text, since the engine holds no catalog.
    @Test func theEngineMessagesHaveGermanTexts() {
        let loc = localization(.german)
        let failures: [TrackTransfer.Failure] = [
            .storage, .exceedsStorage, .requiresCompleteFile, .timedOut, .truncated, .cancelled, .invalidRead,
        ]
        for message in failures.compactMap(\.errorDescription) {
            #expect(loc.translated(message) != message, "\(message)")
        }
        #expect(loc.translated("The server answered with HTTP 503.") == "Der Server antwortete mit HTTP 503.")
    }

    @Test func roleWordsTranslateAndTagsStay() {
        #expect(Localization.shared.string("conductor", in: .german) == "Dirigent")
        #expect(Localization.shared.string(String.LocalizationValue("violin"), in: .german) == "violin")
    }

    // MARK: Formats

    @Test func numbersFollowTheLanguage() {
        let german = localization(.german).locale
        let english = localization(.english).locale
        #expect(1_234_567.formatted(IntegerFormatStyle<Int>(locale: german)) == "1.234.567")
        #expect(1_234_567.formatted(IntegerFormatStyle<Int>(locale: english)) == "1,234,567")
        #expect(1.5.formatted(FloatingPointFormatStyle<Double>(locale: german)) == "1,5")
    }

    @Test func datesFollowTheLanguage() {
        let day = Date(timeIntervalSince1970: 1_700_000_000)
        func text(_ locale: Locale) -> String {
            day.formatted(Date.FormatStyle(date: .long, time: .omitted, locale: locale, timeZone: .gmt))
        }
        #expect(text(localization(.german).locale) == "14. November 2023")
        #expect(text(localization(.english).locale) == "November 14, 2023")
    }

    @Test func durationsAndListsFollowTheLanguage() {
        let german = localization(.german).locale
        let style = Duration.TimeFormatStyle(pattern: .minuteSecond, locale: german)
        #expect(Duration.seconds(187).formatted(style) == "3:07")
        #expect(["A", "B", "C"].formatted(.list(type: .and).locale(german)) == "A, B und C")
    }

    // MARK: Sorting and searching

    /// Ä, Ö and Ü sort with their base letters, as in a German dictionary.
    @Test func umlautsSortWithTheirBaseLetters() {
        let names = ["Zeppelin", "Ärger", "Apfel", "Öl", "Ofen", "Übung", "Uhr"]
        let german = Locale(identifier: "de")
        let sorted = names.sorted {
            $0.compare($1, options: [.caseInsensitive], range: nil, locale: german) == .orderedAscending
        }
        #expect(sorted == ["Apfel", "Ärger", "Ofen", "Öl", "Übung", "Uhr", "Zeppelin"])
        #expect(names.sorted { $0.localizedStandardCompare($1) == .orderedAscending } == sorted)
    }

    @Test func searchIgnoresDiacritics() {
        #expect(Search.fold("Müller") == Search.fold("MULLER"))
        #expect(Search.fold("Größe") == "grosse")
        #expect(Search.words(of: "Ärger Öl Übung") == ["arger", "ol", "ubung"])
    }

    /// Composer names and work titles stay as tagged, in every app language.
    @Test func namesStayAsTagged() {
        let tagged = "Pjotr Iljitsch Tschaikowski"
        #expect(Roles.displayLabel(tagged) == tagged)
    }
}
