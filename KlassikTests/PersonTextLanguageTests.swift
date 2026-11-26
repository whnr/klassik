import Foundation
import Testing

@testable import Klassik

/// The language of the texts that Wikidata and Wikipedia give (sz-odf9): the app language first, then the fallback.
@MainActor
struct PersonTextLanguageTests {
    /// The languages of a run. A test changes them, as the listener does in Settings.
    final class Languages: @unchecked Sendable {
        private let lock = NSLock()
        private var current: TextLanguages
        init(_ current: TextLanguages) { self.current = current }
        var value: TextLanguages {
            get { lock.withLock { current } }
            set { lock.withLock { current = newValue } }
        }
    }

    static let german = TextLanguages(app: .german, fallback: .english)

    /// An item with English and German texts. `wiki` names the editions that have an article.
    static func entity(descriptions: [String: String], wiki: [String: String]) -> String {
        let texts = descriptions.sorted { $0.key < $1.key }
            .map { "\"\($0.key)\":{\"value\":\"\($0.value)\"}" }.joined(separator: ",")
        let sites = wiki.sorted { $0.key < $1.key }
            .map { "\"\($0.key)wiki\":{\"title\":\"Johann Sebastian Bach\"}" }.joined(separator: ",")
        return "{\"entities\":{\"Q1339\":{\"labels\":{\"en\":{\"value\":\"Johann Sebastian Bach\"}},"
            + "\"descriptions\":{\(texts)},\"claims\":{},\"sitelinks\":{\(sites)}}}}"
    }

    static func article(_ language: String, _ text: String) -> (contains: String, body: String) {
        (
            "\(language).wikipedia.org/api/rest_v1/page/summary/Johann_Sebastian_Bach",
            "{\"extract\":\"\(text)\",\"content_urls\":{\"desktop\":{\"page\":"
                + "\"https://\(language).wikipedia.org/wiki/Johann_Sebastian_Bach\"}}}"
        )
    }

    static func service(
        _ stub: PersonStub, _ languages: Languages
    ) -> PersonFactsService {
        var service = stub.service
        service.textLanguages = { languages.value }
        return service
    }

    static let both = [
        article("de", "Johann Sebastian Bach war ein deutscher Komponist."),
        article("en", "Johann Sebastian Bach was a German composer."),
    ]

    @Test func theAppLanguageGivesTheTexts() async throws {
        let stub = PersonStub(
            [
                (
                    "ids=Q1339&props=labels|descriptions|claims",
                    Self.entity(
                        descriptions: ["de": "deutscher Komponist", "en": "German composer"],
                        wiki: ["de": "x", "en": "x"])
                )
            ] + Self.both)
        let facts = try #require(try await Self.service(stub, Languages(Self.german)).facts(qid: "Q1339"))
        #expect(facts.description == "deutscher Komponist")
        #expect(facts.bio == "Johann Sebastian Bach war ein deutscher Komponist.")
        #expect(facts.credits.first { $0.kind == .text }?.url?.host() == "de.wikipedia.org")
        #expect(facts.textKey == "de>en")
        let request = try #require(stub.requests.first)
        #expect(request.contains("languages=de|en"))
        #expect(request.contains("sitefilter=dewiki|enwiki"))
    }

    @Test func theFallbackGivesWhatTheAppLanguageLacks() async throws {
        let stub = PersonStub(
            [
                (
                    "ids=Q1339&props=labels|descriptions|claims",
                    Self.entity(descriptions: ["en": "German composer"], wiki: ["en": "x"])
                )
            ] + Self.both)
        let facts = try #require(try await Self.service(stub, Languages(Self.german)).facts(qid: "Q1339"))
        #expect(facts.description == "German composer")
        #expect(facts.bio == "Johann Sebastian Bach was a German composer.")
        #expect(facts.credits.first { $0.kind == .text }?.url?.host() == "en.wikipedia.org")
    }

    /// A failed German request is no "no article": the English text shows, marked incomplete, and the next pass
    /// asks for German again.
    @Test func aFailedAppLanguageRequestKeepsTheFallbackMarked() async throws {
        let stub = PersonStub(
            [
                (
                    "ids=Q1339&props=labels|descriptions|claims",
                    Self.entity(
                        descriptions: ["de": "deutscher Komponist", "en": "German composer"],
                        wiki: ["de": "x", "en": "x"])
                )
            ] + Self.both)
        stub.fail(["de.wikipedia.org"])
        let service = Self.service(stub, Languages(Self.german))
        let failed = try #require(try await service.facts(qid: "Q1339"))
        #expect(failed.bio == "Johann Sebastian Bach was a German composer.")
        #expect(failed.needsTexts(for: Self.german))
        stub.fail([])
        let again = try #require(try await service.facts(qid: "Q1339"))
        #expect(again.bio == "Johann Sebastian Bach war ein deutscher Komponist.")
        #expect(!again.needsTexts(for: Self.german))
    }

    /// A failed Wikipedia request gives no text: the saved biography and its credit stay, and the next pass asks again.
    @Test func aFailedTextRequestKeepsTheSavedBiography() async throws {
        let item = Self.entity(descriptions: ["de": "deutscher Komponist", "en": "German composer"], wiki: ["en": "x"])
        let germanOnly = Self.entity(descriptions: ["de": "deutscher Komponist"], wiki: ["de": "x"])
        let stub = PersonStub(
            [
                ("list=search", PersonStub.search(["Q1339"])),
                ("ids=Q1339&props=labels|descriptions|claims", item),
                ("ids=Q1339&props=labels|descriptions&languages", item),
            ] + Self.both)
        let languages = Languages(TextLanguages(app: .english, fallback: nil))
        let url = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).json")
        let store = PersonFactsStore(service: Self.service(stub, languages), cacheURL: url)
        #expect(await store.resolve(performer: "Johann Sebastian Bach"))
        await store.saved()
        let saved = try #require(store.facts(ofPerformer: "Johann Sebastian Bach"))
        #expect(saved.bio == "Johann Sebastian Bach was a German composer.")

        // Only the German edition has an article now, and that request fails.
        let failing = PersonStub(
            [
                ("list=search", PersonStub.search(["Q1339"])),
                ("ids=Q1339&props=labels|descriptions|claims", germanOnly),
            ] + Self.both)
        failing.fail(["de.wikipedia.org"])
        languages.value = TextLanguages(app: .german, fallback: nil)
        let again = PersonFactsStore(service: Self.service(failing, languages), cacheURL: url)
        #expect(await again.refresh("Q1339"))
        let kept = try #require(again.facts(ofPerformer: "Johann Sebastian Bach"))
        #expect(kept.bio == saved.bio)
        #expect(kept.credits.contains { $0.kind == .text })
        #expect(kept.needsTexts(for: languages.value))
        await again.saved()
        try? FileManager.default.removeItem(at: url)
    }

    /// A device language that changed while the app was closed marks the saved texts at the start of a pass.
    @Test func aPassMarksTheTextsOfAnotherLanguageAtLaunch() async throws {
        let item = Self.entity(
            descriptions: ["de": "deutscher Komponist", "en": "German composer"], wiki: ["de": "x", "en": "x"])
        let stub = PersonStub(
            [
                ("list=search", PersonStub.search(["Q1339"])),
                ("ids=Q1339&props=labels|descriptions|claims", item),
                ("ids=Q1339&props=labels|descriptions&languages", item),
            ] + Self.both)
        let languages = Languages(TextLanguages(app: .english, fallback: .english))
        let url = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).json")
        let store = PersonFactsStore(service: Self.service(stub, languages), cacheURL: url)
        #expect(await store.resolve(performer: "Johann Sebastian Bach"))
        let person = PersonSweep.Person(kind: .performer, tag: "Johann Sebastian Bach")
        store.markChecked(person.key, at: .now, due: .distantFuture)
        let sweep = PersonSweep(store: store)
        #expect(sweep.plan([person]).new.isEmpty)

        languages.value = Self.german
        sweep.invalidateStaleTexts()
        #expect(sweep.plan([person]).new.count == 1)
        await store.saved()
        try? FileManager.default.removeItem(at: url)
    }

    /// With the fallback off and no German text, the about field stays empty. The name stays English.
    @Test func withoutFallbackNothingFills() async throws {
        let stub = PersonStub(
            [
                (
                    "ids=Q1339&props=labels|descriptions|claims",
                    Self.entity(descriptions: ["en": "German composer"], wiki: ["en": "x"])
                )
            ] + Self.both)
        let languages = Languages(TextLanguages(app: .german, fallback: nil))
        let facts = try #require(try await Self.service(stub, languages).facts(qid: "Q1339"))
        #expect(facts.description == nil)
        #expect(facts.bio == nil)
        #expect(!facts.credits.contains { $0.kind == .text })
        #expect(facts.name == "Johann Sebastian Bach")
        #expect(facts.textKey == "de")
    }

    @Test func englishFactsFromBeforeNeedNoNewFetch() {
        var facts = PersonFacts(qid: "Q1", name: "A")
        #expect(!facts.needsTexts(for: TextLanguages(app: .english, fallback: .english)))
        #expect(facts.needsTexts(for: Self.german))
        facts.textKey = "de>en"
        #expect(!facts.needsTexts(for: Self.german))
    }

    /// A change of the language marks the saved facts. The old texts stay until the new ones load.
    @Test func aNewLanguageLoadsTheTextsAgain() async throws {
        let item = Self.entity(
            descriptions: ["de": "deutscher Komponist", "en": "German composer"], wiki: ["de": "x", "en": "x"])
        let stub = PersonStub(
            [
                ("list=search", PersonStub.search(["Q1339"])),
                ("ids=Q1339&props=labels|descriptions|claims", item),
                ("ids=Q1339&props=labels|descriptions&languages", item),
            ] + Self.both)
        let languages = Languages(TextLanguages(app: .english, fallback: .english))
        let url = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).json")
        let store = PersonFactsStore(service: Self.service(stub, languages), cacheURL: url)
        #expect(await store.resolve(performer: "Johann Sebastian Bach"))
        #expect(store.facts(ofPerformer: "Johann Sebastian Bach")?.description == "German composer")
        store.markChecked("performer:Johann Sebastian Bach", at: .now, due: .distantFuture)
        #expect(!store.hasStaleTexts("Q1339"))

        languages.value = Self.german
        #expect(store.hasStaleTexts("Q1339"))
        #expect(store.facts(ofPerformer: "Johann Sebastian Bach")?.description == "German composer")
        store.invalidateTexts()
        #expect(store.cache.checked["performer:Johann Sebastian Bach"] == nil)

        #expect(await store.resolve(performer: "Johann Sebastian Bach"))
        #expect(store.facts(ofPerformer: "Johann Sebastian Bach")?.description == "deutscher Komponist")
        #expect(!store.hasStaleTexts("Q1339"))
        await store.saved()
        try? FileManager.default.removeItem(at: url)
    }
}
