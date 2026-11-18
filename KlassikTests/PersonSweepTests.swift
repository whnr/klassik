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

/// The pictures that the sweep hands on, with the picture that each person had before.
@MainActor private final class PictureLog {
    private(set) var found: [PersonPortrait] = []
    private(set) var old: [PersonPortrait?] = []
    func add(_ portrait: PersonPortrait, _ before: PersonPortrait?) {
        found.append(portrait)
        old.append(before)
    }
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

    @Test func eachLookupKeepsThePictureAndALaterLookupFetchesItAgain() async throws {
        let (store, _) = try makeStore()
        let clock = TestClock(Self.start)
        let log = PictureLog()
        let sweep = PersonSweep(
            store: store, now: { clock.now }, jitter: { 0 },
            pictures: { portrait, old in
                log.add(portrait, old)
                return true
            })
        await sweep.run([Self.bach])
        await sweep.finish()
        #expect(log.found.map(\.url.absoluteString) == ["https://thumb.wikimedia.org/bach-1200.jpg"])
        #expect(log.old == [nil])
        clock.advance(days: Double(PersonSweep.deadDays) + PersonSweep.jitterDays + 1)
        await sweep.run([Self.bach])
        await sweep.finish()
        #expect(log.found.count == 2)
        #expect(log.old.count == 2)
        #expect(log.old[1] == log.found[0])
    }

    @Test func aCheckedPersonGetsItsMissingPictureWithoutAnotherMetadataLookup() async throws {
        let (store, stub) = try makeStore()
        let initial = PersonSweep(store: store, now: { Self.start })
        await initial.run([Self.bach])
        await initial.finish()
        let checked = store.cache.checked
        let requests = stub.requests.count
        let log = PictureLog()
        let sweep = PersonSweep(
            store: store, now: { Self.start },
            pictures: { portrait, old in
                log.add(portrait, old)
                return true
            }, hasPicture: { _ in false })
        await sweep.run([Self.bach])
        await sweep.finish()
        #expect(log.found.count == 1)
        #expect(store.cache.checked == checked)
        #expect(stub.requests.count == requests)
        #expect(store.cache.picturePending.isEmpty)
    }

    @Test func aFailedPictureRetriesBeforeMetadataExpires() async throws {
        let (store, stub) = try makeStore()
        let attempts = Counter()
        let sweep = PersonSweep(
            store: store, now: { Self.start },
            pictures: { _, _ in
                attempts.next() > 0
            })
        await sweep.run([Self.bach])
        await sweep.finish()
        #expect(store.cache.picturePending.count == 1)
        let checked = store.cache.checked
        let requests = stub.requests.count
        await sweep.run([Self.bach])
        await sweep.finish()
        #expect(store.cache.picturePending.isEmpty)
        #expect(store.cache.checked == checked)
        #expect(stub.requests.count == requests)
    }

    @Test func anInterruptedPictureRemainsPendingAcrossRelaunch() async throws {
        let (store, _) = try makeStore()
        let started = Gate()
        let sweep = PersonSweep(
            store: store, now: { Self.start },
            pictures: { _, _ in
                started.open()
                do { try await Task.sleep(for: .seconds(60)) } catch { return false }
                return false
            })
        await sweep.run([Self.bach])
        for _ in 0..<300 where !started.isOpen { try await Task.sleep(for: .milliseconds(10)) }
        #expect(started.isOpen)
        sweep.stop()
        await sweep.finish()
        await store.saved()
        #expect(store.cache.picturePending.count == 1)
        let json = try #require(String(data: JSONEncoder().encode(store.cache), encoding: .utf8))
        let (restored, stub) = try makeStore(cache: json)
        let log = PictureLog()
        let retry = PersonSweep(
            store: restored, now: { Self.start },
            pictures: { portrait, old in
                log.add(portrait, old)
                return true
            })
        await retry.run([Self.bach])
        await retry.finish()
        #expect(log.found.count == 1)
        #expect(stub.requests.isEmpty)
        #expect(restored.cache.picturePending.isEmpty)
        #expect(restored.cache.checked == store.cache.checked)
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

    /// A fetch that fails every request naming `failing` for its first `times` requests, and answers the rest from
    /// the Bach rules. It logs the tag that each name request carries, in order.
    private func failing(_ failing: String, times: Int = .max, names: [String], log: NameLog) -> MusicBrainz.Fetch {
        let stub = PersonStub(PersonStub.bachRules)
        let attempts = Counter()
        return { request in
            let url = request.url?.absoluteString.removingPercentEncoding ?? ""
            if let name = names.first(where: { url.contains($0) }) { log.append(name) }
            if url.contains(failing), attempts.next() < times { throw URLError(.timedOut) }
            return try await stub.fetch(request)
        }
    }

    @Test func aFailedPersonMovesToTheEndOfTheQueue() async throws {
        let mutter = PersonSweep.Person(kind: .performer, tag: "Anne-Sophie Mutter")
        let log = NameLog()
        let names = [Self.bach.tag, mutter.tag]
        let (store, _) = try makeStore(fetch: failing(Self.bach.tag, times: 1, names: names, log: log))
        let waits = Counter()
        let sweep = PersonSweep(
            store: store, now: { Self.start }, sleep: { duration in waits.record(Int(duration.components.seconds)) })
        await sweep.run([Self.bach, mutter])
        // Bach fails first, Mutter goes next, and Bach is tried again after her.
        #expect(log.names.first == Self.bach.tag)
        let mutterFirst = try #require(log.names.firstIndex(of: mutter.tag))
        let bachAgain = try #require(log.names.indices.dropFirst().first { log.names[$0] == Self.bach.tag })
        #expect(mutterFirst < bachAgain)
        #expect(waits.seconds.isEmpty)
        #expect(store.cache.checked[Self.bach.key] == Self.start)
        #expect(store.cache.checked[mutter.key] == Self.start)
        #expect(sweep.state == .upToDate)
    }

    @Test func aPersonStopsAfterTwoFailuresAndWaitsForTheStandardCadence() async throws {
        let mutter = PersonSweep.Person(kind: .performer, tag: "Anne-Sophie Mutter")
        let log = NameLog()
        let clock = TestClock(Self.start)
        let (store, _) = try makeStore(fetch: failing(Self.bach.tag, names: [Self.bach.tag], log: log))
        let sweep = PersonSweep(store: store, now: { clock.now }, sleep: { _ in }, jitter: { 0 })
        await sweep.run([Self.bach, mutter])
        #expect(PersonSweep.triesPerPass == 2)
        #expect(log.names == [Self.bach.tag, Self.bach.tag])
        #expect(store.cache.checked[Self.bach.key] == nil)
        #expect(store.cache.checked[mutter.key] != nil)
        let due = try #require(store.cache.due[Self.bach.key])
        #expect(due == Self.start.addingTimeInterval(Double(PersonSweep.unknownDays) * 86_400))
        // The failed person waits for its due time, then is looked up as a new person.
        await sweep.run([Self.bach, mutter])
        #expect(log.names.count == 2)
        clock.advance(days: Double(PersonSweep.unknownDays) - 1)
        #expect(sweep.plan([Self.bach]).new.isEmpty)
        clock.advance(days: 2)
        #expect(sweep.plan([Self.bach]).new == [Self.bach])
    }

    @Test func aCancelledSecondAttemptStaysInTheNextPass() async throws {
        let attempts = Counter()
        let (started, signal) = AsyncStream.makeStream(of: Int.self)
        let stub = PersonStub(PersonStub.bachRules)
        let (store, _) = try makeStore(fetch: { request in
            let attempt = attempts.next()
            signal.yield(attempt)
            if attempt == 0 { throw URLError(.timedOut) }
            if attempt == 1 { try await Task.sleep(for: .seconds(60)) }
            return try await stub.fetch(request)
        })
        let sweep = PersonSweep(store: store, now: { Self.start }, jitter: { 0 })
        let task = Task { await sweep.run([Self.bach]) }
        defer { task.cancel() }
        var requests = started.makeAsyncIterator()
        #expect(await requests.next() == 0)
        #expect(await requests.next() == 1)
        task.cancel()
        await task.value
        #expect(store.cache.checked[Self.bach.key] == nil)
        #expect(store.cache.due[Self.bach.key] == nil)
        #expect(sweep.plan([Self.bach]).new == [Self.bach])
        #expect(sweep.newCount == 1)
        #expect(sweep.state == .idle)

        await sweep.run([Self.bach])
        #expect(store.cache.checked[Self.bach.key] == Self.start)
        #expect(sweep.state == .upToDate)
    }

    @Test func failuresInARowBackOffFromTheSecond() async throws {
        let (store, _) = try makeStore(fetch: { _ in throw URLError(.timedOut) })
        let other = PersonSweep.Person(kind: .composer, tag: "Other Composer")
        let waits = Counter()
        let sweep = PersonSweep(
            store: store, now: { Self.start }, sleep: { duration in waits.record(Int(duration.components.seconds)) })
        await sweep.run([Self.bach, other])
        // Bach, Other, Bach, Other: no wait after the first failure, none after the last try of the pass.
        #expect(waits.seconds == [60, 120])
        #expect(store.cache.checked.isEmpty)
        #expect(store.cache.due[Self.bach.key] != nil)
        #expect(store.cache.due[other.key] != nil)
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

    // MARK: Order (ADR 0046)

    static let mutter = PersonSweep.Person(kind: .performer, tag: "Anne-Sophie Mutter")
    static let ma = PersonSweep.Person(kind: .performer, tag: "Yo-Yo Ma")

    /// The names in the order the pass took them, each lookup once.
    private func lookups(_ log: NameLog) -> [String] {
        log.names.reduce(into: []) { order, name in if order.last != name { order.append(name) } }
    }

    @Test func everyComposerComesBeforeEveryPerformer() throws {
        let old = Self.start.addingTimeInterval(-400 * 86_400)
        let (store, _) = try makeStore(cache: cache(tag: "Old Master", born: 1600, died: 1670, checked: old))
        let sweep = PersonSweep(store: store, now: { Self.start })
        let master = PersonSweep.Person(kind: .composer, tag: "Old Master")
        // A due composer still goes before a new performer; new ones go first inside each group.
        #expect(sweep.order([Self.mutter, master, Self.ma, Self.bach]) == [Self.bach, master, Self.mutter, Self.ma])
    }

    @Test func thePassLooksUpComposersBeforePerformers() async throws {
        let log = NameLog()
        let names = [Self.bach.tag, Self.mutter.tag]
        let (store, _) = try makeStore(fetch: failing("nobody", times: 0, names: names, log: log))
        let sweep = PersonSweep(store: store, now: { Self.start })
        await sweep.run([Self.mutter, Self.bach])
        #expect(lookups(log) == [Self.bach.tag, Self.mutter.tag])
    }

    @Test func aShownPerformerGoesFirst() async throws {
        let log = NameLog()
        let names = [Self.bach.tag, Self.mutter.tag, Self.ma.tag]
        let (store, _) = try makeStore(fetch: failing("nobody", times: 0, names: names, log: log))
        let sweep = PersonSweep(store: store, now: { Self.start })
        sweep.prefer(performers: [Self.ma.tag])
        await sweep.run([Self.bach, Self.mutter, Self.ma])
        #expect(lookups(log) == [Self.ma.tag, Self.bach.tag, Self.mutter.tag])
        #expect(sweep.shown.isEmpty)
    }

    @Test func aPageShownDuringThePassMovesItsPerformersForward() async throws {
        let log = NameLog()
        let names = [Self.bach.tag, Self.mutter.tag, Self.ma.tag]
        let gate = Gate()
        let (started, signal) = AsyncStream.makeStream(of: Void.self)
        let inner = failing("nobody", times: 0, names: names, log: log)
        let (store, _) = try makeStore(fetch: { request in
            signal.yield()
            while !gate.isOpen { try await Task.sleep(for: .milliseconds(10)) }
            return try await inner(request)
        })
        let sweep = PersonSweep(store: store, now: { Self.start })
        let pass = Task { await sweep.run([Self.bach, Self.mutter, Self.ma]) }
        var requests = started.makeAsyncIterator()
        _ = await requests.next()
        sweep.prefer(performers: [Self.ma.tag])
        gate.open()
        await pass.value
        #expect(lookups(log) == [Self.bach.tag, Self.ma.tag, Self.mutter.tag])
    }

    @Test func aCheckedPerformerIsNotPutInFront() throws {
        let (store, _) = try makeStore(
            cache: cache(tag: Self.mutter.tag, born: 1963, died: nil, checked: Self.start, kind: "performer"))
        let sweep = PersonSweep(store: store, now: { Self.start })
        sweep.prefer(performers: [Self.mutter.tag, Self.ma.tag, Self.ma.tag])
        #expect(sweep.shown == [Self.ma])
    }

    @Test func theLatestPageGoesFirst() throws {
        let (store, _) = try makeStore()
        let sweep = PersonSweep(store: store, now: { Self.start })
        sweep.prefer(performers: [Self.mutter.tag])
        sweep.prefer(performers: [Self.ma.tag, Self.mutter.tag])
        #expect(sweep.shown == [Self.ma, Self.mutter])
        sweep.prefer(performers: (0..<150).map { "Player \($0)" })
        #expect(sweep.shown.count == PersonSweep.shownLimit)
    }

    @Test func aShownPerformerThatFailsStillGoesToTheEnd() async throws {
        let log = NameLog()
        let names = [Self.bach.tag, Self.mutter.tag, Self.ma.tag]
        let (store, _) = try makeStore(fetch: failing(Self.ma.tag, times: 1, names: names, log: log))
        let sweep = PersonSweep(store: store, now: { Self.start }, sleep: { _ in })
        sweep.prefer(performers: [Self.ma.tag])
        await sweep.run([Self.bach, Self.mutter, Self.ma])
        #expect(lookups(log) == [Self.ma.tag, Self.bach.tag, Self.mutter.tag, Self.ma.tag])
        #expect(store.cache.checked[Self.ma.key] == Self.start)
    }

    @Test func aCancelledShownPerformerStaysInFront() async throws {
        let attempts = Counter()
        let (started, signal) = AsyncStream.makeStream(of: Int.self)
        let stub = PersonStub(PersonStub.bachRules)
        let (store, _) = try makeStore(fetch: { request in
            let attempt = attempts.next()
            signal.yield(attempt)
            if attempt == 0 { try await Task.sleep(for: .seconds(60)) }
            return try await stub.fetch(request)
        })
        let sweep = PersonSweep(store: store, now: { Self.start }, jitter: { 0 })
        sweep.prefer(performers: [Self.ma.tag])
        let task = Task { await sweep.run([Self.bach, Self.ma]) }
        defer { task.cancel() }
        var requests = started.makeAsyncIterator()
        #expect(await requests.next() == 0)
        task.cancel()
        await task.value
        #expect(store.cache.checked[Self.ma.key] == nil)
        #expect(store.cache.due[Self.ma.key] == nil)
        #expect(sweep.shown == [Self.ma])
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

/// The person names of the requests, in the order sent.
private final class NameLog: @unchecked Sendable {
    private let lock = NSLock()
    private var log: [String] = []
    func append(_ name: String) { lock.withLock { log.append(name) } }
    var names: [String] { lock.withLock { log } }
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

    @Test(arguments: [Double.infinity, 1e300, Double(Int64.max)])
    func aHugeRetryAfterHoldsForTheLongestHoldWithoutCrashing(retryAfter: Double) async throws {
        let script = Script([.init(data: Data(), status: 429, retryAfter: retryAfter), Self.found])
        let service = service(script)
        await #expect(throws: MusicBrainz.Failure.http(429)) {
            _ = try await service.composers(named: "Bach")
        }
        let hold = await service.pacer.hold
        #expect(hold > 3500 && hold <= WikimediaPacer.longestHold)
    }

    @Test func aNanRetryAfterCountsAsAbsent() async throws {
        let script = Script([.init(data: Data(), status: 429, retryAfter: .nan), Self.found])
        _ = try await service(script).composers(named: "Bach")
        #expect(script.waits == [5])
    }

    @Test func aNegativeRetryAfterCountsAsAbsent() async throws {
        let script = Script([.init(data: Data(), status: 429, retryAfter: -30), Self.found])
        _ = try await service(script).composers(named: "Bach")
        #expect(script.waits == [5])
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
