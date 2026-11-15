import Foundation
import Testing

@testable import Klassik

private final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var date: Date
    init(_ date: Date) { self.date = date }
    var now: Date { lock.withLock { date } }
    func advance(days: Double) { lock.withLock { date = date.addingTimeInterval(days * 86_400) } }
}

private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    private var log: [Int] = []
    func next() -> Int {
        lock.withLock {
            defer { value += 1 }
            return value
        }
    }
    func record(_ seconds: Int) { lock.withLock { log.append(seconds) } }
    var seconds: [Int] { lock.withLock { log } }
}

@MainActor
struct PersonSweepTests {
    static let bach = PersonSweep.Person(kind: .composer, tag: "Johann Sebastian Bach")
    nonisolated static let start = Date(timeIntervalSince1970: 1_800_000_000)

    private func makeStore(
        cache: String? = nil, fetch: MusicBrainz.Fetch? = nil
    ) throws -> (store: PersonFactsStore, stub: PersonStub) {
        let url = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).json")
        if let cache { try Data(cache.utf8).write(to: url) }
        let stub = PersonStub(PersonStub.bachRules)
        let service = PersonFactsService(fetch: fetch ?? stub.fetch, pacer: WikimediaPacer(interval: .zero))
        return (PersonFactsStore(service: service, cacheURL: url), stub)
    }

    /// A saved cache with one person. `born` and `died` are years; the person is checked at `checked` seconds.
    private func cache(tag: String, born: Int, died: Int?, checked: Date, kind: String = "composer") -> String {
        let death = died.map { ",\"died\":\($0)" } ?? ""
        let facts = "{\"qid\":\"Q1\",\"name\":\"\(tag)\",\"born\":\(born)\(death),\"credits\":[]}"
        let stamp = checked.timeIntervalSinceReferenceDate
        let resolution =
            kind == "composer"
            ? "\"composers\":{\"\(tag)\":{\"person\":{\"_0\":\"Q1\"}}},\"performers\":{}"
            : "\"composers\":{},\"performers\":{\"\(tag)\":\"Q1\"}"
        return "{\"people\":{\"Q1\":\(facts)},\(resolution),\"artists\":{},\"chosen\":[],\"inputs\":{},"
            + "\"checked\":{\"\(kind):\(tag)\":\(stamp)},\"version\":\(PersonFactsStore.Cache.version)}"
    }

    @Test func aNewPersonIsLookedUpAndSettled() async throws {
        let (store, stub) = try makeStore()
        let sweep = PersonSweep(store: store, now: { Self.start })
        await sweep.run([Self.bach])
        #expect(store.facts(ofComposer: Self.bach.tag)?.name == "Johann Sebastian Bach")
        #expect(store.cache.checked[Self.bach.key] == Self.start)
        #expect(sweep.state == .upToDate)
        #expect(!stub.requests.isEmpty)
    }

    @Test func aSecondPassAsksNothingForKnownPeople() async throws {
        let (store, stub) = try makeStore()
        let sweep = PersonSweep(store: store, now: { Self.start })
        await sweep.run([Self.bach])
        let asked = stub.requests.count
        await sweep.run([Self.bach])
        #expect(stub.requests.count == asked)
        #expect(sweep.state == .upToDate)
    }

    @Test func aNewPersonComesBeforeADueOne() throws {
        let old = Self.start.addingTimeInterval(-400 * 86_400)
        let (store, _) = try makeStore(cache: cache(tag: "Old Master", born: 1600, died: 1670, checked: old))
        let sweep = PersonSweep(store: store, now: { Self.start })
        let master = PersonSweep.Person(kind: .composer, tag: "Old Master")
        let plan = sweep.plan([master, Self.bach])
        #expect(plan.new == [Self.bach])
        #expect(plan.due == [master])
    }

    @Test func aLivingPersonIsDueAfterAMonthAndADeadOneAfterAYear() throws {
        let clock = TestClock(Self.start)
        let living = cache(tag: "Alive", born: 1960, died: nil, checked: Self.start)
        let dead = cache(tag: "Gone", born: 1700, died: 1760, checked: Self.start)
        let alive = PersonSweep.Person(kind: .composer, tag: "Alive")
        let gone = PersonSweep.Person(kind: .composer, tag: "Gone")
        let livingSweep = PersonSweep(store: try makeStore(cache: living).store, now: { clock.now })
        let deadSweep = PersonSweep(store: try makeStore(cache: dead).store, now: { clock.now })
        clock.advance(days: 29)
        #expect(livingSweep.plan([alive]).due.isEmpty)
        clock.advance(days: 2)
        #expect(livingSweep.plan([alive]).due == [alive])
        #expect(deadSweep.plan([gone]).due.isEmpty)
        clock.advance(days: 340)
        #expect(deadSweep.plan([gone]).due == [gone])
    }

    @Test func aPersonWithoutAnItemIsDueAfterThreeMonths() throws {
        let tag = "Nobody"
        let stamp = Self.start.timeIntervalSinceReferenceDate
        let cache =
            "{\"people\":{},\"composers\":{},\"performers\":{\"\(tag)\":\"\"},\"artists\":{},\"chosen\":[],"
            + "\"inputs\":{},\"checked\":{\"performer:\(tag)\":\(stamp)},\"version\":\(PersonFactsStore.Cache.version)}"
        let clock = TestClock(Self.start)
        let person = PersonSweep.Person(kind: .performer, tag: tag)
        let sweep = PersonSweep(store: try makeStore(cache: cache).store, now: { clock.now })
        clock.advance(days: 89)
        #expect(sweep.plan([person]).due.isEmpty)
        clock.advance(days: 2)
        #expect(sweep.plan([person]).due == [person])
    }

    @Test func aDuePersonKeepsTheirResolutionAndGetsNewFacts() async throws {
        let old = Self.start.addingTimeInterval(-400 * 86_400)
        let saved = cache(tag: "Johann Sebastian Bach", born: 1685, died: 1750, checked: old)
            .replacingOccurrences(of: "\"Q1\"", with: "\"Q1339\"").replacingOccurrences(of: "Q1:", with: "Q1339:")
        let (store, stub) = try makeStore(cache: saved)
        let sweep = PersonSweep(store: store, now: { Self.start })
        await sweep.run([Self.bach])
        #expect(stub.requests.contains { $0.contains("ids=Q1339") })
        #expect(store.facts(ofComposer: Self.bach.tag)?.bio == "Johann Sebastian Bach was a German composer.")
        #expect(store.cache.checked[Self.bach.key] == Self.start)
    }

    @Test func aPoorConnectionPausesThePass() async throws {
        let (store, _) = try makeStore()
        let checks = Counter()
        let paused = Counter()
        let sweep = PersonSweep(
            store: store, isConnectionGood: { checks.next() >= 2 }, now: { Self.start },
            sleep: { duration in paused.record(Int(duration.components.seconds)) })
        await sweep.run([Self.bach])
        #expect(paused.seconds == [30, 30])
        #expect(sweep.state == .upToDate)
        #expect(store.cache.checked[Self.bach.key] != nil)
    }

    @Test func aFailedRequestWaitsThenTriesTheSamePersonAgain() async throws {
        let stub = PersonStub(PersonStub.bachRules)
        let attempts = Counter()
        let waits = Counter()
        let (store, _) = try makeStore(fetch: { request in
            if attempts.next() < 2 { throw MusicBrainz.Failure.http(429) }
            return try await stub.fetch(request)
        })
        let sweep = PersonSweep(
            store: store, now: { Self.start }, sleep: { duration in waits.record(Int(duration.components.seconds)) })
        await sweep.run([Self.bach])
        #expect(waits.seconds == [60, 120])
        #expect(store.facts(ofComposer: Self.bach.tag) != nil)
        #expect(sweep.state == .upToDate)
    }

    @Test func aLongRetryAfterHoldsThePassUntilItEnds() async throws {
        let clock = PacerClock()
        let stub = PersonStub(PersonStub.bachRules)
        let sent = Counter()
        let waits = Counter()
        let sentBeforeWait = Counter()
        let service = PersonFactsService(
            respond: { request in
                if sent.next() == 0 { return .init(data: Data(), status: 429, retryAfter: 600) }
                let (data, status) = try await stub.fetch(request)
                return .init(data: data, status: status)
            }, pacer: WikimediaPacer(interval: .zero, now: { clock.now }))
        let url = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).json")
        let store = PersonFactsStore(service: service, cacheURL: url)
        let sweep = PersonSweep(
            store: store, now: { Self.start },
            sleep: { duration in
                let seconds = Int(duration.components.seconds)
                waits.record(seconds)
                sentBeforeWait.record(stub.requests.count)
                clock.advance(seconds: seconds)
            })
        await sweep.run([Self.bach])
        #expect(waits.seconds == [600])
        #expect(sentBeforeWait.seconds == [0])
        #expect(store.facts(ofComposer: Self.bach.tag) != nil)
    }

    @Test func aFailedPersonIsNotMarkedChecked() async throws {
        let (store, _) = try makeStore(fetch: { _ in throw URLError(.notConnectedToInternet) })
        let sweep = PersonSweep(store: store, now: { Self.start })
        let task = Task { await sweep.run([Self.bach]) }
        try await Task.sleep(for: .milliseconds(200))
        task.cancel()
        await task.value
        #expect(store.cache.checked[Self.bach.key] == nil)
    }

    @Test func theSavedCheckSurvivesARestart() async throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).json")
        let stub = PersonStub(PersonStub.bachRules)
        let service = PersonFactsService(fetch: stub.fetch, pacer: WikimediaPacer(interval: .zero))
        let first = PersonFactsStore(service: service, cacheURL: url)
        await PersonSweep(store: first, now: { Self.start }).run([Self.bach])
        for _ in 0..<100 where !FileManager.default.fileExists(atPath: url.path) {
            try await Task.sleep(for: .milliseconds(20))
        }
        let second = PersonFactsStore(service: PersonStub([]).service, cacheURL: url)
        #expect(PersonSweep(store: second, now: { Self.start }).plan([Self.bach]).new.isEmpty)
    }

    // MARK: Parallel start and one person per request

    @Test func thePersonPassDoesNotWaitForTheMusicBrainzPass() async throws {
        let gate = Gate()
        let finished = Gate()
        let musicBrainzCalls = Counter()
        let blocked: MusicBrainz.Fetch = { _ in
            _ = musicBrainzCalls.next()
            while !gate.isOpen { try await Task.sleep(for: .milliseconds(10)) }
            return (Data(), 404)
        }
        let enrichment = Enrichment(
            musicBrainz: MusicBrainz(fetch: blocked, pacer: Pacer(interval: 0)),
            wikidata: Wikidata(fetch: blocked, pacer: Pacer(interval: 0)),
            cacheURL: FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).json"))
        let (store, stub) = try makeStore()
        let sweep = PersonSweep(store: store, now: { Self.start })
        let index = WorkIndex(songs: [
            EnrichmentTests.song("1", composer: "Johann Sebastian Bach", work: "Cello Suite No. 1")
        ])
        let pass = Task {
            await AppModel.enrich(index, enrichment: enrichment, sweep: sweep)
            finished.open()
        }
        for _ in 0..<300 where store.cache.checked[Self.bach.key] == nil {
            try await Task.sleep(for: .milliseconds(10))
        }
        // The person is settled while the MusicBrainz pass still waits for its answer.
        #expect(store.facts(ofComposer: Self.bach.tag) != nil)
        #expect(store.cache.checked[Self.bach.key] != nil)
        #expect(!finished.isOpen)
        #expect(musicBrainzCalls.next() > 0)
        #expect(!stub.requests.isEmpty)
        gate.open()
        await pass.value
        #expect(finished.isOpen)
    }

    @Test func aLookupUsesTheNameOnlyAndAsksForOnePersonAtATime() async throws {
        let mutter = PersonSweep.Person(kind: .performer, tag: "Anne-Sophie Mutter")
        let (store, stub) = try makeStore()
        let sweep = PersonSweep(store: store, now: { Self.start })
        await sweep.run([Self.bach, mutter])
        #expect(stub.requests.contains { $0.contains(Self.bach.tag) })
        #expect(stub.requests.contains { $0.contains(mutter.tag) })
        for request in stub.requests {
            // No lookup by a MusicBrainz composer ID or work ID.
            #expect(!request.contains("P434="))
            #expect(!request.contains("P435"))
            #expect([Self.bach.tag, mutter.tag].filter { request.contains($0) }.count <= 1)
            if request.contains("props=labels|descriptions|claims") {
                let tail = request.components(separatedBy: "ids=").dropFirst().first ?? ""
                let ids = tail.components(separatedBy: "&").first ?? ""
                #expect(!ids.isEmpty)
                #expect(!ids.contains("|"))
            }
        }
    }

    // MARK: Jitter

    @Test func aDueTimeMovesByAtMostTenDays() async throws {
        for (offset, expected) in [(10.0, 375.0), (-10.0, 355.0), (25.0, 375.0), (-25.0, 355.0), (0.0, 365.0)] {
            let (store, _) = try makeStore()
            let sweep = PersonSweep(store: store, now: { Self.start }, jitter: { offset })
            await sweep.run([Self.bach])
            let due = try #require(store.cache.due[Self.bach.key])
            #expect(due == Self.start.addingTimeInterval(expected * 86_400))
        }
    }

    @Test func theRandomJitterStaysInsideItsBounds() async throws {
        #expect(PersonSweep.jitterDays == 10)
        var spread: Set<Double> = []
        for _ in 0..<20 {
            let (store, _) = try makeStore()
            await PersonSweep(store: store, now: { Self.start }).run([Self.bach])
            let due = try #require(store.cache.due[Self.bach.key])
            let days = due.timeIntervalSince(Self.start) / 86_400
            #expect((355...375).contains(days))
            spread.insert(days)
        }
        #expect(spread.count > 1)
    }

    @Test func thePlanUsesTheSavedDueTime() throws {
        let stamp = Self.start.addingTimeInterval(25 * 86_400).timeIntervalSinceReferenceDate
        let saved = cache(tag: "Alive", born: 1960, died: nil, checked: Self.start)
            .replacingOccurrences(of: ",\"version\"", with: ",\"due\":{\"composer:Alive\":\(stamp)},\"version\"")
        let clock = TestClock(Self.start)
        let alive = PersonSweep.Person(kind: .composer, tag: "Alive")
        let sweep = PersonSweep(store: try makeStore(cache: saved).store, now: { clock.now })
        clock.advance(days: 24)
        #expect(sweep.plan([alive]).due.isEmpty)
        clock.advance(days: 2)
        #expect(sweep.plan([alive]).due == [alive])
    }
}

/// A pacer clock that moves only when the test moves it.
private final class PacerClock: @unchecked Sendable {
    private let lock = NSLock()
    private let start = ContinuousClock.now
    private var offset = Duration.zero
    var now: ContinuousClock.Instant { lock.withLock { start + offset } }
    func advance(seconds: Int) { lock.withLock { offset += .seconds(seconds) } }
}

private final class Gate: @unchecked Sendable {
    private let lock = NSLock()
    private var opened = false
    var isOpen: Bool { lock.withLock { opened } }
    func open() { lock.withLock { opened = true } }
}

/// Wikimedia's throttle signals: 429, 503 with Retry-After, and the maxlag error (ADR 0042).
struct WikimediaPacingTests {
    private final class Script: @unchecked Sendable {
        private let lock = NSLock()
        private var answers: [PersonFactsService.Response]
        private var sent: [String] = []
        private var slept: [Double] = []

        init(_ answers: [PersonFactsService.Response]) { self.answers = answers }

        var respond: PersonFactsService.Respond {
            { request in
                self.lock.withLock {
                    self.sent.append(request.url?.absoluteString.removingPercentEncoding ?? "")
                    return self.answers.count > 1 ? self.answers.removeFirst() : self.answers[0]
                }
            }
        }

        func sleep(_ duration: Duration) {
            let (seconds, attoseconds) = duration.components
            lock.withLock { slept.append(Double(seconds) + Double(attoseconds) / 1e18) }
        }

        var urls: [String] { lock.withLock { sent } }
        /// The waits of a second or more, rounded. The pacer also waits microseconds between requests.
        var waits: [Double] { lock.withLock { slept.filter { $0 >= 1 }.map { $0.rounded() } } }
    }

    private static let found = PersonFactsService.Response(data: Data(PersonStub.search([]).utf8), status: 200)
    private static let lag = Data(#"{"error":{"code":"maxlag","info":"Waiting for db: 6 seconds lagged."}}"#.utf8)

    private func service(_ script: Script) -> PersonFactsService {
        PersonFactsService(
            respond: script.respond, pacer: WikimediaPacer(interval: .zero, sleep: { script.sleep($0) }))
    }

    @Test func everyActionRequestCarriesMaxlagAndADescriptiveUserAgent() async throws {
        let script = Script([Self.found])
        _ = try await service(script).composers(named: "Johann Sebastian Bach")
        #expect(!script.urls.isEmpty)
        #expect(script.urls.allSatisfy { $0.contains("maxlag=5") })
        #expect(PersonFactsService.userAgent.hasPrefix("Klassik/"))
        #expect(PersonFactsService.userAgent.contains("(https://github.com/whnr/klassik)"))
        #expect(PersonFactsService.userAgent.hasSuffix("bot"))
    }

    @Test func a429WaitsForRetryAfterAndTriesAgain() async throws {
        let script = Script([.init(data: Data(), status: 429, retryAfter: 7), Self.found])
        _ = try await service(script).composers(named: "Bach")
        #expect(script.waits == [7])
        #expect(script.urls.count == 2)
    }

    @Test func a429WithoutRetryAfterWaitsFiveSecondsThenDoubles() async throws {
        let busy = PersonFactsService.Response(data: Data(), status: 429)
        let script = Script([busy, busy, Self.found])
        _ = try await service(script).composers(named: "Bach")
        #expect(script.waits == [5, 10])
    }

    @Test func aShortRetryAfterStillWaitsFiveSeconds() async throws {
        let script = Script([.init(data: Data(), status: 429, retryAfter: 1), Self.found])
        _ = try await service(script).composers(named: "Bach")
        #expect(script.waits == [5])
    }

    @Test func aMaxlagErrorWaitsForRetryAfterAndTriesAgain() async throws {
        let script = Script([.init(data: Self.lag, status: 200, retryAfter: 6), Self.found])
        _ = try await service(script).composers(named: "Bach")
        #expect(script.waits == [6])
        #expect(script.urls.count == 2)
    }

    @Test func a503TriesAgainOnlyWithRetryAfter() async throws {
        let again = Script([.init(data: Data(), status: 503, retryAfter: 5), Self.found])
        _ = try await service(again).composers(named: "Bach")
        #expect(again.urls.count == 2)
        let down = Script([.init(data: Data(), status: 503)])
        await #expect(throws: MusicBrainz.Failure.http(503)) {
            _ = try await service(down).composers(named: "Bach")
        }
        #expect(down.urls.count == 1)
    }

    @Test func aLongRetryAfterHoldsEveryLaterRequest() async throws {
        let script = Script([.init(data: Data(), status: 429, retryAfter: 600), Self.found])
        let service = service(script)
        await #expect(throws: MusicBrainz.Failure.http(429)) {
            _ = try await service.composers(named: "Bach")
        }
        await #expect(throws: MusicBrainz.Failure.http(429)) {
            _ = try await service.facts(qid: "Q1339")
        }
        #expect(script.urls.count == 1)
        #expect(await service.pacer.hold > 599)
    }

    @Test func aLongThrottleFailsTheRequestSoThatThePassBacksOff() async throws {
        let script = Script([.init(data: Data(), status: 429)])
        await #expect(throws: MusicBrainz.Failure.http(429)) {
            _ = try await service(script).composers(named: "Bach")
        }
        #expect(script.waits == [5, 10, 20, 40])
    }
}
