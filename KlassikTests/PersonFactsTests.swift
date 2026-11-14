import Foundation
import Testing

@testable import Klassik

/// Answers Wikidata, Wikipedia and Commons requests with trimmed bodies. The first rule whose text the URL
/// holds answers. It records each request.
final class PersonStub: @unchecked Sendable {
    private let lock = NSLock()
    private let rules: [(contains: String, body: String)]
    private(set) var requests: [String] = []

    init(_ rules: [(contains: String, body: String)]) {
        self.rules = rules
    }

    var fetch: MusicBrainz.Fetch {
        { request in
            let url = request.url!.absoluteString.removingPercentEncoding ?? ""
            self.lock.withLock { self.requests.append(url) }
            guard let rule = self.rules.first(where: { url.contains($0.contains) }) else { return (Data(), 404) }
            return (Data(rule.body.utf8), 200)
        }
    }

    var service: PersonFactsService { PersonFactsService(fetch: fetch, pacer: Pacer(interval: 0)) }

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

    static let commons = """
        {"query":{"pages":{"1":{"imageinfo":[{"thumburl":"https://upload.wikimedia.org/bach-1200.jpg",\
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
        #expect(facts.portrait?.url.absoluteString == "https://upload.wikimedia.org/bach-1200.jpg")
        #expect(Set(facts.credits.map(\.kind)) == [.facts, .text, .picture])
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
        let evil = PersonStub.commons.replacingOccurrences(of: "upload.wikimedia.org", with: "evil.example")
        let rules = PersonStub.bachRules.map { $0.contains == "commons.wikimedia.org" ? ($0.contains, evil) : $0 }
        let facts = try #require(try await PersonStub(rules).service.facts(qid: "Q1339"))
        #expect(facts.portrait == nil)
        #expect(!facts.credits.contains { $0.kind == .picture })
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
        let stub = PersonStub(PersonStub.bachRules)

        func recover() { lock.withLock { failing = false } }

        var fetch: MusicBrainz.Fetch {
            { request in
                let down = self.lock.withLock { self.failing }
                let url = request.url!.absoluteString.removingPercentEncoding ?? ""
                if down, url.contains("props=labels|descriptions|claims") {
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
            service: PersonFactsService(fetch: flaky.fetch, pacer: Pacer(interval: 0)), cacheURL: url)
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
            fetch: { _ in throw URLError(.notConnectedToInternet) }, pacer: Pacer(interval: 0))
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
}
