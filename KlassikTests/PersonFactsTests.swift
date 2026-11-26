import Foundation
import Testing
import UIKit

@testable import Klassik

/// Answers Wikidata, Wikipedia and Commons requests with trimmed bodies. The first rule whose text the URL
/// holds answers. It records each request.
final class PersonStub: @unchecked Sendable {
    private let lock = NSLock()
    private let rules: [(contains: String, body: String)]
    private(set) var requests: [String] = []
    private var failing: [String] = []

    init(_ rules: [(contains: String, body: String)]) {
        self.rules = rules
    }

    /// The URLs that hold one of these texts answer 503.
    func fail(_ texts: [String]) {
        lock.withLock { failing = texts }
    }

    var fetch: MusicBrainz.Fetch {
        { request in
            let url = request.url!.absoluteString.removingPercentEncoding ?? ""
            self.lock.withLock { self.requests.append(url) }
            if self.lock.withLock({ self.failing.contains { url.contains($0) } }) { return (Data(), 503) }
            guard let rule = self.rules.first(where: { url.contains($0.contains) }) else { return (Data(), 404) }
            return (Data(rule.body.utf8), 200)
        }
    }

    var service: PersonFactsService { PersonFactsService(fetch: fetch, pacer: WikimediaPacer(interval: .zero)) }

    static func search(_ qids: [String]) -> String {
        "{\"query\":{\"search\":[" + qids.map { "{\"title\":\"\($0)\"}" }.joined(separator: ",") + "]}}"
    }

    static func entity(
        _ qid: String, label: String, description: String?, born: String? = nil, died: String? = nil,
        active: String? = nil, picture: String? = nil, wiki: String? = nil
    ) -> String {
        func time(_ property: String, _ value: String?) -> String? {
            value.map {
                "\"\(property)\":[{\"rank\":\"normal\",\"mainsnak\":{\"datavalue\":{\"value\":{\"time\":\"\($0)\"}}}}]"
            }
        }
        var claims = [time("P569", born), time("P570", died), time("P2031", active)].compactMap(\.self)
        if let picture {
            claims.append("\"P18\":[{\"mainsnak\":{\"datavalue\":{\"value\":\"\(picture)\"}}}]")
        }
        let site = wiki.map { ",\"sitelinks\":{\"enwiki\":{\"title\":\"\($0)\"}}" } ?? ""
        let text = description.map { ",\"descriptions\":{\"en\":{\"value\":\"\($0)\"}}" } ?? ""
        return "{\"entities\":{\"\(qid)\":{\"labels\":{\"en\":{\"value\":\"\(label)\"}}\(text),"
            + "\"claims\":{\(claims.joined(separator: ","))}\(site)}}}"
    }

    static let bach = "Q1339"
    static let strauss1 = "Q9948"
    static let strauss2 = "Q68764"
    static let artistBach = "24f1766e-9635-4d58-a4d4-9413f9f98a4c"
    static let artistJohann = "9d2eb9a3-6f51-4d4a-8c1a-0d2a3c5e0c11"
    static let artistRichard = "73c2ce7e-8ee9-4a5c-a3a1-37d4d4a31a52"

    /// The composers that Wikidata finds for "Ludwig van Beethoven", in its order: each holds the occupation
    /// composer (P106 Q36834). Only Q255 is the composer of the works.
    static let beethovenHits: [PersonMatch] = [
        PersonMatch(qid: "Q255", name: "Ludwig van Beethoven", description: "German composer (1770-1827)"),
        PersonMatch(
            qid: "Q12368917", name: "Ludwig van Beethoven",
            description: "grandfather of composer Ludwig van Beethoven"),
        PersonMatch(qid: "Q2153541", name: "Johann van Beethoven", description: "father of Ludwig van Beethoven"),
        PersonMatch(
            qid: "Q64862", name: "Anton Schindler",
            description: "Associate, secretary, and early biographer of Ludwig van Beethoven (1795-1864)"),
        PersonMatch(
            qid: "Q6374627", name: "Kaspar Anton Karl van Beethoven",
            description: "German composer, brother of Ludwig van Beethoven (1774-1815)"),
        PersonMatch(
            qid: "Q472851", name: "Count Ferdinand Ernst Gabriel von Waldstein",
            description: "British Army general (1762-1823)"),
        PersonMatch(qid: "Q6216444", name: "Johanna van Beethoven", description: "Beethoven's sister-in-law"),
    ]

    static let beethovenRules: [(contains: String, body: String)] = {
        let labels = beethovenHits.map { hit in
            "\"\(hit.qid)\":{\"labels\":{\"en\":{\"value\":\"\(hit.name)\"}},"
                + "\"descriptions\":{\"en\":{\"value\":\"\(hit.description ?? "")\"}}}"
        }
        return [
            ("list=search", search(beethovenHits.map(\.qid))),
            (
                "ids=" + beethovenHits.map(\.qid).joined(separator: "|"),
                "{\"entities\":{\(labels.joined(separator: ","))}}"
            ),
            (
                "ids=Q255&props=labels|descriptions|claims",
                entity(
                    "Q255", label: "Ludwig van Beethoven", description: "German composer (1770-1827)",
                    born: "+1770-12-17T00:00:00Z", died: "+1827-03-26T00:00:00Z")
            ),
            (
                "ids=Q12368917&props=labels|descriptions|claims",
                entity(
                    "Q12368917", label: "Ludwig van Beethoven",
                    description: "grandfather of composer Ludwig van Beethoven", born: "+1712-01-05T00:00:00Z")
            ),
        ]
    }()

    static let commons = """
        {"query":{"pages":{"1":{"imageinfo":[{"thumburl":"https://thumb.wikimedia.org/bach-1200.jpg",\
        "descriptionurl":"https://commons.wikimedia.org/wiki/File:Bach.jpg","extmetadata":{\
        "Artist":{"value":"<a href=\\"//x\\">Elias Gottlob Haussmann</a> &amp; workshop"},\
        "LicenseShortName":{"value":"Public domain"}}}]}}}}
        """

    static let bachRules: [(contains: String, body: String)] = [
        ("haswbstatement:P434=\(artistBach)", search([bach])),
        ("list=search", search([bach])),
        (
            "ids=Q1339&props=labels|descriptions|claims",
            entity(
                bach, label: "Johann Sebastian Bach", description: "German composer (1685–1750)",
                born: "+1685-03-31T00:00:00Z", died: "+1750-07-28T00:00:00Z", active: "+1703-00-00T00:00:00Z",
                picture: "Bach.jpg", wiki: "Johann Sebastian Bach")
        ),
        (
            "ids=Q1339&props=labels|descriptions",
            entity(bach, label: "Johann Sebastian Bach", description: "German composer")
        ),
        ("commons.wikimedia.org", commons),
        (
            "en.wikipedia.org/api/rest_v1/page/summary/Johann_Sebastian_Bach",
            "{\"extract\":\"Johann Sebastian Bach was a German composer.\","
                + "\"content_urls\":{\"desktop\":{\"page\":\"https://en.wikipedia.org/wiki/Johann_Sebastian_Bach\"}}}"
        ),
    ]
}

struct PersonFactsServiceTests {
    @Test func composerSearchFiltersByOccupation() async throws {
        let stub = PersonStub(PersonStub.bachRules)
        let found = try await stub.service.composers(named: "Bach")
        #expect(found.map(\.qid) == ["Q1339"])
        #expect(found.first?.name == "Johann Sebastian Bach")
        #expect(stub.requests.first?.contains("haswbstatement:P106=Q36834") == true)
    }

    @Test func personByMusicBrainzArtist() async throws {
        let stub = PersonStub(PersonStub.bachRules)
        #expect(try await stub.service.person(musicBrainzArtist: PersonStub.artistBach)?.qid == "Q1339")
        #expect(try await stub.service.person(musicBrainzArtist: "not an id") == nil)
    }

    @Test func factsHoldDatesDescriptionBioPortraitAndCredits() async throws {
        let facts = try #require(try await PersonStub(PersonStub.bachRules).service.facts(qid: "Q1339"))
        #expect(facts.born == 1685 && facts.died == 1750 && facts.activeFrom == 1703)
        #expect(facts.bio == "Johann Sebastian Bach was a German composer.")
        #expect(facts.portrait?.url.absoluteString == "https://thumb.wikimedia.org/bach-1200.jpg")
        #expect(Set(facts.credits.map(\.kind)) == [.facts, .text, .picture])
        let text = try #require(facts.credits.first { $0.kind == .text })
        #expect(text.text == "Wikipedia, CC BY-SA 4.0")
        #expect(text.url?.absoluteString == "https://en.wikipedia.org/wiki/Johann_Sebastian_Bach")
        let picture = try #require(facts.credits.first { $0.kind == .picture })
        #expect(picture.text == "Elias Gottlob Haussmann & workshop, Public domain, Wikimedia Commons")
    }

    @Test func aMissingItemGivesNothing() async throws {
        let stub = PersonStub([("ids=Q5", "{\"entities\":{\"Q5\":{\"id\":\"Q5\",\"missing\":\"\"}}}")])
        #expect(try await stub.service.facts(qid: "Q5") == nil)
        #expect(try await stub.service.facts(qid: "not a qid") == nil)
    }

    @Test func aFailedRequestThrows() async {
        await #expect(throws: MusicBrainz.Failure.self) { try await PersonStub([]).service.composers(named: "Bach") }
    }

    @Test func aFailedBioLeavesTheFacts() async throws {
        let rules = PersonStub.bachRules.filter { !$0.contains.contains("wikipedia") }
        let facts = try #require(try await PersonStub(rules).service.facts(qid: "Q1339"))
        #expect(facts.bio == nil)
        #expect(facts.born == 1685)
    }

    @Test func aSummaryWithoutPageLinksToItsArticle() async throws {
        let rules = PersonStub.bachRules.map {
            $0.contains.contains("wikipedia") ? ($0.contains, #"{"extract":"A composer."}"#) : $0
        }
        let facts = try #require(try await PersonStub(rules).service.facts(qid: "Q1339"))
        let credit = try #require(facts.credits.first { $0.kind == .text })
        #expect(credit.url?.absoluteString == "https://en.wikipedia.org/wiki/Johann_Sebastian_Bach")
    }

    @Test func descriptionLineDropsTheYearsThenAddsThem() {
        func line(_ description: String?, _ born: Int?, _ died: Int?) -> String? {
            PersonFacts(qid: "Q1", name: "X", description: description, born: born, died: died).descriptionLine
        }
        #expect(line("German composer (1685–1750)", 1685, 1750) == "German composer, 1685–1750")
        #expect(
            line("German composer and organist, 1685-1750", 1685, 1750) == "German composer and organist, 1685–1750")
        #expect(line("Italian composer", 1678, 1741) == "Italian composer, 1678–1741")
        #expect(line("Estonian composer (born 1935)", 1935, nil) == "Estonian composer, born 1935")
        #expect(line("composer", nil, nil) == "composer")
        #expect(line(nil, 1900, 1980) == "1900–1980")
        #expect(line(nil, nil, nil) == nil)
    }

    @Test func authorHtmlBecomesPlainText() {
        #expect(PersonFactsService.plain("<a href=\"x\">A  B</a> &amp; <b>C</b>") == "A B & C")
        // One pass: an escaped entity stays text. Numeric and no-break entities decode.
        #expect(PersonFactsService.plain("&amp;lt; &#233;&#x41; a&nbsp;b &unknown; &") == "&lt; éA a b &unknown; &")
    }

    @Test func onlyHttpsLinksOnTrustedHostsPass() {
        func trusted(_ text: String) -> Bool { PersonFactsService.trusted(URL(string: text)) != nil }
        #expect(trusted("https://upload.wikimedia.org/a.jpg"))
        #expect(trusted("https://thumb.wikimedia.org/a.jpg"))
        #expect(!trusted("https://thumb.wikimedia.org.evil.example/a.jpg"))
        #expect(trusted("https://commons.wikimedia.org/wiki/File:A.jpg"))
        #expect(trusted("https://en.wikipedia.org/wiki/A"))
        #expect(trusted("https://www.wikidata.org/wiki/Q1"))
        #expect(!trusted("http://upload.wikimedia.org/a.jpg"))
        #expect(!trusted("https://upload.example/a.jpg"))
        #expect(!trusted("https://upload.wikimedia.org.evil.example/a.jpg"))
        #expect(!trusted("tel:+4912345"))
        #expect(!trusted("javascript:alert(1)"))
        #expect(PersonFactsService.trusted(nil) == nil)
    }

    @Test func aPictureOnAnotherHostIsDropped() async throws {
        let evil = PersonStub.commons.replacingOccurrences(of: "thumb.wikimedia.org", with: "evil.example")
        let rules = PersonStub.bachRules.map { $0.contains == "commons.wikimedia.org" ? ($0.contains, evil) : $0 }
        let facts = try #require(try await PersonStub(rules).service.facts(qid: "Q1339"))
        #expect(facts.portrait == nil)
        #expect(!facts.credits.contains { $0.kind == .picture })
    }

    @Test func aFailedPictureRequestMarksThePictureUnread() async throws {
        let rules = PersonStub.bachRules.filter { $0.contains != "commons.wikimedia.org" }
        let facts = try #require(try await PersonStub(rules).service.facts(qid: "Q1339"))
        #expect(facts.born == 1685)
        #expect(facts.portrait == nil)
        #expect(facts.pictureUnread == true)
        #expect(facts.pictureFile == "Bach.jpg")
        let answered = try #require(try await PersonStub(PersonStub.bachRules).service.facts(qid: "Q1339"))
        #expect(answered.pictureUnread == nil)
    }

    @Test func aCreditLinkOnAnotherSchemeIsDropped() {
        let page = Data(
            """
            {"query":{"pages":{"1":{"imageinfo":[{"thumburl":"https://upload.wikimedia.org/a.jpg",\
            "descriptionurl":"tel:+4912345","extmetadata":{}}]}}}}
            """.utf8)
        let parsed = PersonFactsService.parsePortrait(page)
        #expect(parsed?.portrait.page == nil)
        #expect(parsed?.credit.url == nil)
    }

    @Test func aTagIsASearchPhrase() async throws {
        let stub = PersonStub(PersonStub.bachRules)
        _ = try await stub.service.composers(named: "Bach\" -haswbstatement:P31=Q5")
        let search = "srsearch=\"Bach -haswbstatement:P31=Q5\" haswbstatement:P106=Q36834"
        #expect(stub.requests.first?.contains(search) == true)
        #expect(stub.requests.first?.contains("srlimit=10") == true)
    }

    @Test func aDeprecatedStatementLosesToANormalOne() {
        let entity: [String: Any] = [
            "claims": [
                "P569": [
                    ["rank": "deprecated", "mainsnak": ["datavalue": ["value": ["time": "+1600-01-01T00:00:00Z"]]]],
                    ["rank": "normal", "mainsnak": ["datavalue": ["value": ["time": "+1685-03-31T00:00:00Z"]]]],
                ],
                "P570": [
                    [
                        "rank": "normal",
                        "mainsnak": ["datavalue": ["value": ["time": "+1700-00-00T00:00:00Z", "precision": 8]]],
                    ]
                ],
            ]
        ]
        let facts = PersonFactsService.parse(entity, qid: "Q1")
        #expect(facts.born == 1685)
        // A decade is no year.
        #expect(facts.died == nil)
    }

    @Test func aBracketWithoutAYearStays() {
        #expect(PersonFacts.withoutYears("composer (Op. 100)") == "composer (Op. 100)")
        #expect(PersonFacts.withoutYears("composer (1685–1750)") == "composer")
    }

    // MARK: Recorded answers

    private static let recordedRules: [(contains: String, body: String)] = [
        ("ids=Q1339&props=labels|descriptions|claims", RecordedWikimedia.bachEntity),
        ("commons.wikimedia.org/w/api.php", RecordedWikimedia.bachCommons),
    ]

    /// Keep the recorded thumbnail host intact to check the trust boundary against Commons responses.
    @Test func theRecordedAnswersGiveBachAPictureWithItsCredit() async throws {
        let facts = try #require(try await PersonStub(Self.recordedRules).service.facts(qid: "Q1339"))
        let portrait = try #require(facts.portrait)
        #expect(portrait.url.host == "thumb.wikimedia.org")
        #expect(portrait.page?.absoluteString == "https://commons.wikimedia.org/wiki/File:Johann_Sebastian_Bach.png")
        let credit = try #require(facts.credits.first { $0.kind == .picture })
        #expect(credit.text == "Elias Gottlob Haussmann, Public domain, Wikimedia Commons")
        #expect(credit.url == portrait.page)
        #expect(facts.born == 1685 && facts.died == 1750)
    }

    @Test func theRecordedPictureFileIsP18() throws {
        let entity = try #require(PersonFactsService.entity("Q1339", in: Data(RecordedWikimedia.bachEntity.utf8)))
        #expect(PersonFactsService.pictureFile(entity) == "Johann Sebastian Bach.png")
    }

    @Test func theLoaderTakesTheRecordedPictureUrl() async throws {
        let facts = try #require(try await PersonStub(Self.recordedRules).service.facts(qid: "Q1339"))
        let url = try #require(facts.portrait?.url)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let png = UIGraphicsImageRenderer(size: CGSize(width: 40, height: 60), format: format).pngData { context in
            UIColor.gray.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 40, height: 60))
        }
        // The loader asks for no URL outside the trusted list: a refused URL gives nil without a request.
        let loaded = await PortraitLoader.load(url) { _ in (png, 200) }
        #expect(loaded?.image.size == CGSize(width: 40, height: 60))
    }
}

@MainActor
struct PersonFactsStoreTests {
    private func makeStore(_ rules: [(contains: String, body: String)], file: String = UUID().uuidString) -> (
        PersonFactsStore, PersonStub, URL
    ) {
        let stub = PersonStub(rules)
        let url = FileManager.default.temporaryDirectory.appending(path: "\(file).json")
        return (PersonFactsStore(service: stub.service, cacheURL: url), stub, url)
    }

    @Test func aFullNameFindsTheComposer() async throws {
        let (store, _, _) = makeStore(PersonStub.bachRules)
        await store.resolve(composer: "Johann Sebastian Bach", artistIDs: [])
        #expect(store.resolution(ofComposer: "Johann Sebastian Bach") == .person("Q1339"))
        #expect(store.facts(ofComposer: "Johann Sebastian Bach")?.born == 1685)
    }

    @Test func theWorksDecideASurnameTag() async throws {
        let (store, stub, _) = makeStore(PersonStub.bachRules)
        await store.resolve(composer: "Bach", artistIDs: [PersonStub.artistBach, PersonStub.artistBach])
        #expect(store.resolution(ofComposer: "Bach") == .person("Q1339"))
        // The works decided: no name search ran.
        #expect(!stub.requests.contains { $0.contains("haswbstatement:P106") })
    }

    @Test func aSurnameTagWithoutWorkIDsAsksTheListener() async throws {
        let rules: [(contains: String, body: String)] = [
            ("list=search", PersonStub.search(["Q9948", "Q68764"])),
            (
                "ids=Q9948|Q68764",
                "{\"entities\":{\"Q9948\":{\"labels\":{\"en\":{\"value\":\"Richard Strauss\"}}},"
                    + "\"Q68764\":{\"labels\":{\"en\":{\"value\":\"Johann Strauss II\"}}}}}"
            ),
        ]
        let (store, _, _) = makeStore(rules)
        await store.resolve(composer: "Strauss", artistIDs: [])
        guard case .pick(let matches)? = store.resolution(ofComposer: "Strauss") else {
            Issue.record("expected a pick list, got \(String(describing: store.resolution(ofComposer: "Strauss")))")
            return
        }
        #expect(matches.map(\.name) == ["Richard Strauss", "Johann Strauss II"])
    }

    @Test func aSurnameTagOfSeveralComposersGivesANotice() async throws {
        let rules: [(contains: String, body: String)] = [
            ("haswbstatement:P434=\(PersonStub.artistJohann)", PersonStub.search([PersonStub.strauss2])),
            ("haswbstatement:P434=\(PersonStub.artistRichard)", PersonStub.search([PersonStub.strauss1])),
            (
                "ids=Q68764&props=labels|descriptions|claims",
                PersonStub.entity("Q68764", label: "Johann Strauss II", description: "Austrian composer")
            ),
            (
                "ids=Q9948&props=labels|descriptions|claims",
                PersonStub.entity("Q9948", label: "Richard Strauss", description: "German composer")
            ),
            ("ids=Q68764", PersonStub.entity("Q68764", label: "Johann Strauss II", description: nil)),
            ("ids=Q9948", PersonStub.entity("Q9948", label: "Richard Strauss", description: nil)),
        ]
        let (store, _, _) = makeStore(rules)
        await store.resolve(composer: "Strauss", artistIDs: [PersonStub.artistRichard, PersonStub.artistJohann])
        #expect(store.resolution(ofComposer: "Strauss") == .mixed(["Johann Strauss II", "Richard Strauss"]))
    }

    @Test func noMatchLeavesTheTagsOnly() async throws {
        let (store, _, _) = makeStore([("list=search", PersonStub.search([]))])
        await store.resolve(composer: "Nobody Knownby", artistIDs: [])
        #expect(store.resolution(ofComposer: "Nobody Knownby") == .unknown)
        #expect(store.facts(ofComposer: "Nobody Knownby") == nil)
    }

    @Test func theListenersPickSticks() async throws {
        let (store, _, _) = makeStore(PersonStub.bachRules)
        let match = PersonMatch(qid: "Q1339", name: "Johann Sebastian Bach", description: nil)
        await store.choose(match, forComposer: "Bach")
        #expect(store.resolution(ofComposer: "Bach") == .person("Q1339"))
        // A later lookup with works that say otherwise does not override the listener.
        await store.resolve(composer: "Bach", artistIDs: [PersonStub.artistRichard])
        #expect(store.resolution(ofComposer: "Bach") == .person("Q1339"))
        await store.choose(nil, forComposer: "Bach")
        #expect(store.resolution(ofComposer: "Bach") == .unknown)
    }

    /// Fails the facts request on the first run, then answers.
    private final class FlakyStub: @unchecked Sendable {
        private let lock = NSLock()
        private var failing = true
        private let missing: Bool
        let stub = PersonStub(PersonStub.bachRules)

        init(missing: Bool = false) { self.missing = missing }

        func recover() { lock.withLock { failing = false } }

        var fetch: MusicBrainz.Fetch {
            { request in
                let down = self.lock.withLock { self.failing }
                let url = request.url!.absoluteString.removingPercentEncoding ?? ""
                if down, url.contains("props=labels|descriptions|claims") {
                    if self.missing {
                        return (Data(#"{"entities":{"Q1339":{"missing":""}}}"#.utf8), 200)
                    }
                    throw URLError(.notConnectedToInternet)
                }
                return try await self.stub.fetch(request)
            }
        }
    }

    @Test func aFailedFactsLoadLeavesTheTagOpenForTheNextVisit() async throws {
        let flaky = FlakyStub()
        let url = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).json")
        let store = PersonFactsStore(
            service: PersonFactsService(fetch: flaky.fetch, pacer: WikimediaPacer(interval: .zero)), cacheURL: url)
        await store.resolve(composer: "Johann Sebastian Bach", artistIDs: [])
        #expect(store.resolution(ofComposer: "Johann Sebastian Bach") == nil)
        #expect(store.lastError != nil)
        flaky.recover()
        await store.resolve(composer: "Johann Sebastian Bach", artistIDs: [])
        #expect(store.resolution(ofComposer: "Johann Sebastian Bach") == .person("Q1339"))
        #expect(store.facts(ofComposer: "Johann Sebastian Bach")?.born == 1685)
    }

    @Test func aPickBeforeTheWorksHaveIDsDoesNotPinTheTag() async throws {
        let (store, _, _) = makeStore(PersonStub.bachRules)
        await store.resolve(composer: "Bach", artistIDs: [])
        let match = PersonMatch(qid: "Q1339", name: "Johann Sebastian Bach", description: nil)
        await store.choose(match, forComposer: "Bach")
        #expect(!store.cache.chosen.contains("Bach"))
        // The IDs arrive and the works decide.
        await store.resolve(composer: "Bach", artistIDs: [PersonStub.artistBach])
        #expect(store.cache.inputs["Bach"] == [PersonStub.artistBach])
        #expect(store.resolution(ofComposer: "Bach") == .person("Q1339"))
    }

    @Test func choosingAgainOffersThePickListAgain() async throws {
        let (store, _, _) = makeStore(PersonStub.bachRules)
        await store.resolve(composer: "Johann Sebastian Bach", artistIDs: [PersonStub.artistBach])
        await store.chooseAgain(composer: "Johann Sebastian Bach")
        guard case .pick(let matches)? = store.resolution(ofComposer: "Johann Sebastian Bach") else {
            Issue.record("expected a pick list")
            return
        }
        #expect(matches.map(\.qid) == ["Q1339"])
    }

    @Test func aThrownNetworkErrorIsNotCached() async throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).json")
        let service = PersonFactsService(
            fetch: { _ in throw URLError(.notConnectedToInternet) }, pacer: WikimediaPacer(interval: .zero))
        let store = PersonFactsStore(service: service, cacheURL: url)
        await store.resolve(composer: "Johann Sebastian Bach", artistIDs: [])
        #expect(store.resolution(ofComposer: "Johann Sebastian Bach") == nil)
        #expect(store.lastError != nil)
    }

    @Test func anHttpErrorIsNotCached() async throws {
        let (store, _, _) = makeStore([])
        await store.resolve(composer: "Johann Sebastian Bach", artistIDs: [])
        #expect(store.resolution(ofComposer: "Johann Sebastian Bach") == nil)
        #expect(store.lastError != nil)
    }

    @Test func factsComeFromTheDeviceCacheNextTime() async throws {
        let (first, _, url) = makeStore(PersonStub.bachRules)
        await first.resolve(composer: "Johann Sebastian Bach", artistIDs: [])
        // The write runs on its own task: wait for the file.
        for _ in 0..<100 where !FileManager.default.fileExists(atPath: url.path) {
            try await Task.sleep(for: .milliseconds(20))
        }
        let offline = PersonStub([])
        let second = PersonFactsStore(service: offline.service, cacheURL: url)
        await second.resolve(composer: "Johann Sebastian Bach", artistIDs: [])
        #expect(second.facts(ofComposer: "Johann Sebastian Bach")?.name == "Johann Sebastian Bach")
        #expect(offline.requests.isEmpty)
    }

    private func oldPinnedCacheURL() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).json")
        let old = Data(
            #"""
            {"people":{"Q1339":{"qid":"Q1339","name":"Johann Sebastian Bach","born":1685,"credits":[]}},
            "composers":{"Bach":{"person":{"_0":"Q1339"}},"Nobody":{"unknown":{}}},
            "artists":{},"chosen":["Bach","Nobody"],"inputs":{"Bach":["saved-artist-id"]}}
            """#.utf8)
        try old.write(to: url)
        return url
    }

    @Test func aMigratedPinnedComposerReloadsFactsAndPicture() async throws {
        let url = try oldPinnedCacheURL()
        let stub = PersonStub(PersonStub.bachRules)
        let store = PersonFactsStore(service: stub.service, cacheURL: url)
        #expect(store.facts(ofComposer: "Bach") == nil)
        await store.resolve(composer: "Bach", artistIDs: [PersonStub.artistRichard])
        let facts = try #require(store.facts(ofComposer: "Bach"))
        #expect(facts.born == 1685 && facts.died == 1750)
        #expect(facts.bio == "Johann Sebastian Bach was a German composer.")
        #expect(facts.portrait?.url.host == "thumb.wikimedia.org")
        #expect(Set(facts.credits.map(\.kind)) == [.facts, .text, .picture])
        #expect(store.resolution(ofComposer: "Bach") == .person("Q1339"))
        #expect(store.cache.chosen == ["Bach", "Nobody"])
        #expect(store.cache.inputs["Bach"] == ["saved-artist-id"])
        #expect(store.lastError == nil)
        let requests = stub.requests.count
        await store.resolve(composer: "Bach", artistIDs: [])
        await store.resolve(composer: "Nobody", artistIDs: [PersonStub.artistBach])
        #expect(store.resolution(ofComposer: "Nobody") == .unknown)
        #expect(stub.requests.count == requests)
        #expect(!stub.requests.contains { $0.contains("list=search") })
    }

    @Test(arguments: [false, true])
    func aMigratedPinSurvivesFailedReloadsAndRetries(missing: Bool) async throws {
        let url = try oldPinnedCacheURL()
        let flaky = FlakyStub(missing: missing)
        let store = PersonFactsStore(
            service: PersonFactsService(fetch: flaky.fetch, pacer: WikimediaPacer(interval: .zero)), cacheURL: url)
        await store.resolve(composer: "Bach", artistIDs: [PersonStub.artistRichard])
        #expect(store.facts(ofComposer: "Bach") == nil)
        #expect(store.resolution(ofComposer: "Bach") == .person("Q1339"))
        #expect(store.cache.chosen == ["Bach", "Nobody"])
        #expect(store.loading.isEmpty)
        #expect((store.lastError != nil) == !missing)
        flaky.recover()
        await store.resolve(composer: "Bach", artistIDs: [PersonStub.artistRichard])
        #expect(store.facts(ofComposer: "Bach")?.portrait?.url.host == "thumb.wikimedia.org")
        #expect(store.resolution(ofComposer: "Bach") == .person("Q1339"))
        #expect(store.cache.chosen == ["Bach", "Nobody"])
        #expect(store.cache.inputs["Bach"] == ["saved-artist-id"])
        #expect(store.lastError == nil)
        #expect(!flaky.stub.requests.contains { $0.contains("list=search") })
    }

    @Test func aFullNameTakesTheComposerOverHisRelatives() async throws {
        let (store, _, _) = makeStore(PersonStub.beethovenRules)
        await store.resolve(composer: "Ludwig van Beethoven", artistIDs: [])
        #expect(store.resolution(ofComposer: "Ludwig van Beethoven") == .person("Q255"))
        #expect(store.facts(ofComposer: "Ludwig van Beethoven")?.born == 1770)
    }

    @Test func theBackgroundPassTakesTheComposerOverHisRelatives() async throws {
        let (store, _, _) = makeStore(PersonStub.beethovenRules)
        #expect(await store.lookUp(composer: "Ludwig van Beethoven"))
        #expect(store.resolution(ofComposer: "Ludwig van Beethoven") == .person("Q255"))
    }

    @Test func theWorksDecideBetweenNamesakes() async throws {
        let artist = "1f9df192-a621-4f54-8850-2c5373b7eac9"
        let grandfather = PersonStub.entity(
            "Q12368917", label: "Ludwig van Beethoven", description: "grandfather of composer Ludwig van Beethoven")
        let rules =
            [
                ("haswbstatement:P434=\(artist)", PersonStub.search(["Q12368917"])),
                ("ids=Q12368917&props=labels|descriptions&", grandfather),
            ] + PersonStub.beethovenRules
        let (store, _, _) = makeStore(rules)
        await store.resolve(composer: "Ludwig van Beethoven", artistIDs: [artist])
        #expect(store.resolution(ofComposer: "Ludwig van Beethoven") == .person("Q12368917"))
    }

    @Test func otherNamesNeverCountForAFullName() {
        let hits = PersonStub.beethovenHits
        #expect(PersonFactsStore.settle("Ludwig van Beethoven", found: hits) == .person("Q255"))
        // Without the composer, the namesake is the one hit with the name.
        #expect(PersonFactsStore.settle("Ludwig van Beethoven", found: Array(hits.dropFirst())) == .person("Q12368917"))
        #expect(PersonFactsStore.settle("Johann van Beethoven", found: hits) == .person("Q2153541"))
        // Two namesakes that the descriptions do not tell apart leave the choice to the listener, between them only.
        let twin = PersonMatch(qid: "Q1", name: "Ludwig van Beethoven", description: "German organist")
        #expect(
            PersonFactsStore.settle("Ludwig van Beethoven", found: [hits[0], twin] + hits.dropFirst(2))
                == .pick([hits[0], twin]))
        // A surname tag still asks.
        #expect(PersonFactsStore.settle("Beethoven", found: hits) == .pick(hits))
    }

    @Test func aSavedPickThatTheNameSettlesTakesTheComposer() throws {
        var cache = PersonFactsStore.Cache()
        cache.composers["Ludwig van Beethoven"] = .pick(PersonStub.beethovenHits)
        cache.checked["composer:Ludwig van Beethoven"] = .now
        cache.composers["Beethoven"] = .pick(PersonStub.beethovenHits)
        // The listener asked to choose again: the list stays.
        cache.composers["Johann van Beethoven"] = .pick(PersonStub.beethovenHits)
        cache.chosen.insert("Johann van Beethoven")
        let url = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).json")
        try JSONEncoder().encode(cache).write(to: url)
        let store = PersonFactsStore(service: PersonStub([]).service, cacheURL: url)
        #expect(store.resolution(ofComposer: "Ludwig van Beethoven") == .person("Q255"))
        // The background pass takes the tag again, to load the facts and the picture.
        #expect(store.cache.checked["composer:Ludwig van Beethoven"] == nil)
        #expect(store.resolution(ofComposer: "Beethoven") == .pick(PersonStub.beethovenHits))
        #expect(store.resolution(ofComposer: "Johann van Beethoven") == .pick(PersonStub.beethovenHits))
    }

    @Test func aReopenedPickerWithoutWorkIDsSurvivesRelaunch() async throws {
        let (store, _, url) = makeStore(PersonStub.beethovenRules)
        let tag = "Ludwig van Beethoven"
        await store.resolve(composer: tag, artistIDs: [])
        #expect(store.resolution(ofComposer: tag) == .person("Q255"))
        await store.chooseAgain(composer: tag)
        #expect(store.resolution(ofComposer: tag) == .pick(PersonStub.beethovenHits))
        #expect(!store.cache.chosen.contains(tag))
        await store.saved()

        let relaunched = PersonFactsStore(service: PersonStub([]).service, cacheURL: url)
        #expect(relaunched.resolution(ofComposer: tag) == .pick(PersonStub.beethovenHits))
    }

    @Test func aFailedSelectionKeepsTheReopenedPickerAfterRelaunch() async throws {
        let stub = PersonStub(PersonStub.beethovenRules)
        let service = PersonFactsService(
            fetch: { request in
                let url = request.url!.absoluteString.removingPercentEncoding ?? ""
                if url.contains("ids=Q12368917&props=labels|descriptions|claims") {
                    throw URLError(.notConnectedToInternet)
                }
                return try await stub.fetch(request)
            }, pacer: WikimediaPacer(interval: .zero))
        let url = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = PersonFactsStore(service: service, cacheURL: url)
        let tag = "Ludwig van Beethoven"
        await store.resolve(composer: tag, artistIDs: [])
        #expect(store.resolution(ofComposer: tag) == .person("Q255"))
        await store.chooseAgain(composer: tag)
        await store.choose(PersonStub.beethovenHits[1], forComposer: tag)
        #expect(store.lastError != nil)
        #expect(store.resolution(ofComposer: tag) == .pick(PersonStub.beethovenHits))
        #expect(store.cache.reopenedPickers.contains(tag))
        #expect(!store.cache.chosen.contains(tag))
        await store.saved()

        let relaunched = PersonFactsStore(service: PersonStub([]).service, cacheURL: url)
        #expect(relaunched.resolution(ofComposer: tag) == .pick(PersonStub.beethovenHits))
    }

    @Test(arguments: [false, true])
    func aCompletedSelectionClearsTheReopenedPicker(none: Bool) async throws {
        let (store, _, url) = makeStore(PersonStub.beethovenRules)
        defer { try? FileManager.default.removeItem(at: url) }
        let tag = "Ludwig van Beethoven"
        await store.resolve(composer: tag, artistIDs: [])
        await store.chooseAgain(composer: tag)
        await store.choose(none ? nil : PersonStub.beethovenHits[1], forComposer: tag)
        #expect(store.lastError == nil)
        #expect(!store.cache.reopenedPickers.contains(tag))
        await store.saved()

        let relaunched = PersonFactsStore(service: PersonStub([]).service, cacheURL: url)
        #expect(relaunched.resolution(ofComposer: tag) == (none ? .unknown : .person("Q12368917")))
    }

    @Test func surnameOnlyMeansOneWord() {
        #expect(PersonFactsStore.isSurnameOnly("Strauss"))
        #expect(!PersonFactsStore.isSurnameOnly("Richard Strauss"))
    }
}

@MainActor
struct PerformerFactsTests {
    static let carl = "Q100"

    private static func rules(
        filtered: [String], unfiltered: [String], label: String = "Carl Fixture"
    ) -> [(contains: String, body: String)] {
        [
            ("haswbstatement:P434", PersonStub.search(filtered)),
            ("list=search", PersonStub.search(unfiltered)),
            (
                "ids=\(carl)&props=labels|descriptions|claims",
                PersonStub.entity(
                    carl, label: label, description: "Fixture conductor", born: "+1950-01-01T00:00:00Z")
            ),
            ("ids=\(carl)&props=labels|descriptions", PersonStub.entity(carl, label: label, description: nil)),
        ]
    }

    private func makeStore(_ rules: [(contains: String, body: String)]) -> (PersonFactsStore, PersonStub) {
        let stub = PersonStub(rules)
        let url = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).json")
        return (PersonFactsStore(service: stub.service, cacheURL: url), stub)
    }

    @Test func theSearchFiltersByP434First() async throws {
        let (store, stub) = makeStore(Self.rules(filtered: [Self.carl], unfiltered: []))
        await store.resolve(performer: "Carl Fixture")
        #expect(store.facts(ofPerformer: "Carl Fixture")?.born == 1950)
        #expect(stub.requests.first?.contains("srsearch=\"Carl Fixture\" haswbstatement:P434") == true)
        // The filtered search found the item: no unfiltered search ran.
        #expect(stub.requests.filter { $0.contains("list=search") }.count == 1)
    }

    @Test func withoutP434TheSearchRunsAgainUnfiltered() async throws {
        let (store, stub) = makeStore(Self.rules(filtered: [], unfiltered: [Self.carl]))
        await store.resolve(performer: "Carl Fixture")
        #expect(store.facts(ofPerformer: "Carl Fixture")?.qid == Self.carl)
        let searches = stub.requests.filter { $0.contains("list=search") }
        #expect(searches.count == 2)
        #expect(searches.last?.contains("haswbstatement") == false)
    }

    @Test func noMatchLeavesTheTagsOnlyAndIsRememberedWithoutAskingAgain() async throws {
        let (store, stub) = makeStore(Self.rules(filtered: [], unfiltered: []))
        await store.resolve(performer: "Nobody Knownby")
        #expect(store.facts(ofPerformer: "Nobody Knownby") == nil)
        #expect(store.hasResolved(performer: "Nobody Knownby"))
        let asked = stub.requests.count
        await store.resolve(performer: "Nobody Knownby")
        #expect(stub.requests.count == asked)
    }

    @Test func anUnfilteredHitWithAnotherNameIsNoMatch() async throws {
        let (store, _) = makeStore(Self.rules(filtered: [], unfiltered: [Self.carl], label: "Carl Fixture Hall"))
        await store.resolve(performer: "Carl Fixture")
        #expect(store.facts(ofPerformer: "Carl Fixture") == nil)
        #expect(store.hasResolved(performer: "Carl Fixture"))
    }

    @Test func aFailedLookupLeavesTheTagOpen() async throws {
        let (store, _) = makeStore([])
        await store.resolve(performer: "Carl Fixture")
        #expect(!store.hasResolved(performer: "Carl Fixture"))
        #expect(store.lastError != nil)
    }

    @Test func aCacheFromBeforePerformerPagesStillLoads() throws {
        let old = Data(#"{"people":{},"composers":{},"artists":{},"chosen":[],"inputs":{}}"#.utf8)
        let cache = try JSONDecoder().decode(PersonFactsStore.Cache.self, from: old)
        #expect(cache.performers.isEmpty)
    }

    @Test func factsFromAnOlderCacheAreDroppedAndTheTagsStay() throws {
        let old = Data(
            ("{\"people\":{\"Q1339\":{\"qid\":\"Q1339\",\"name\":\"Johann Sebastian Bach\",\"credits\":[]}},"
                + "\"composers\":{\"Johann Sebastian Bach\":{\"person\":{\"_0\":\"Q1339\"}}},"
                + "\"artists\":{},\"chosen\":[\"Johann Sebastian Bach\"],\"inputs\":{}}").utf8)
        let cache = try JSONDecoder().decode(PersonFactsStore.Cache.self, from: old)
        #expect(cache.people.isEmpty)
        #expect(cache.composers["Johann Sebastian Bach"] == .person("Q1339"))
        #expect(cache.chosen == ["Johann Sebastian Bach"])
        #expect(cache.version == PersonFactsStore.Cache.version)
    }
}

/// About credit lines put the source first and name the link as person.html does.
struct PersonCreditLineTests {
    @Test func aPictureLinkNamesCommonsOnce() throws {
        let url = try #require(URL(string: "https://commons.wikimedia.org/wiki/File:Bach.jpg"))
        let credit = PersonCredit(kind: .picture, text: "Haussmann, Public domain, Wikimedia Commons", url: url)
        #expect(credit.lead(linked: true) == "Picture: Haussmann, Public domain.")
        #expect(credit.linkLabel(url) == "Wikimedia Commons")
        #expect(credit.lead(linked: false) == "Picture: Haussmann, Public domain, Wikimedia Commons.")
    }

    @Test func textAndFactsLinksNameTheArticleAndTheItem() throws {
        let article = try #require(URL(string: "https://en.wikipedia.org/wiki/Johann_Sebastian_Bach"))
        let text = PersonCredit(kind: .text, text: "Wikipedia, CC BY-SA 4.0", url: article)
        #expect(text.lead(linked: true) == "Text: Wikipedia, CC BY-SA 4.0.")
        #expect(text.linkLabel(article) == "Article")
        let item = try #require(URL(string: "https://www.wikidata.org/wiki/Q1339"))
        let facts = PersonCredit(kind: .facts, text: "Wikidata, CC0", url: item)
        #expect(facts.lead(linked: true) == "Facts: Wikidata, CC0.")
        #expect(facts.linkLabel(item) == "Q1339")
    }
}
