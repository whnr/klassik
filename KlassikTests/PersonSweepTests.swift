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
    func next() -> Int { lock.withLock { defer { value += 1 }; return value } }
    func record(_ seconds: Int) { lock.withLock { log.append(seconds) } }
    var seconds: [Int] { lock.withLock { log } }
}

@MainActor
struct PersonSweepTests {
    static let bach = PersonSweep.Person(kind: .composer, tag: "Johann Sebastian Bach")
    static let start = Date(timeIntervalSince1970: 1_800_000_000)

    private func makeStore(
        cache: String? = nil, fetch: MusicBrainz.Fetch? = nil
    ) throws -> (store: PersonFactsStore, stub: PersonStub) {
        let url = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).json")
        if let cache { try Data(cache.utf8).write(to: url) }
        let stub = PersonStub(PersonStub.bachRules)
        let service = PersonFactsService(fetch: fetch ?? stub.fetch, pacer: Pacer(interval: 0))
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
        let service = PersonFactsService(fetch: stub.fetch, pacer: Pacer(interval: 0))
        let first = PersonFactsStore(service: service, cacheURL: url)
        await PersonSweep(store: first, now: { Self.start }).run([Self.bach])
        for _ in 0..<100 where !FileManager.default.fileExists(atPath: url.path) {
            try await Task.sleep(for: .milliseconds(20))
        }
        let second = PersonFactsStore(service: PersonStub([]).service, cacheURL: url)
        #expect(PersonSweep(store: second, now: { Self.start }).plan([Self.bach]).new.isEmpty)
    }
}
