import Foundation
import Network
import Observation

/// Looks up every composer and performer of the library on Wikidata, in the background, and asks again for
/// facts that can change (ADR 0042). The saved state lives in `PersonFactsStore.Cache.checked`.
@MainActor @Observable
final class PersonSweep {
    /// One person of the library: a composer tag or a performer tag. The lookup reads the name only, so the
    /// pass needs nothing from the MusicBrainz pass and runs beside it.
    struct Person: Hashable, Sendable {
        enum Kind: String, Sendable { case composer, performer }
        var kind: Kind
        var tag: String
        var key: String { "\(kind.rawValue):\(tag)" }
    }

    enum PauseReason: Equatable, Sendable {
        case connection
        case slowDown(until: Date)
    }

    enum State: Equatable, Sendable {
        case idle
        case running(done: Int, total: Int)
        case paused(PauseReason)
        case upToDate
    }

    /// How long facts stay fresh, in days (ADR 0042). A living person can change; a dead one rarely does.
    static let livingDays = 30
    static let deadDays = 365
    /// A person that Wikidata does not know may get an item later.
    static let unknownDays = 90
    /// Each due time moves by a random amount up to this many days, so that a library does not fall due at once.
    nonisolated static let jitterDays = 10.0

    private(set) var state = State.idle
    /// The persons that have no check yet, and the persons whose check is due.
    private(set) var newCount = 0
    private(set) var dueCount = 0

    private let store: PersonFactsStore
    private let isConnectionGood: @Sendable () -> Bool
    private let now: @Sendable () -> Date
    private let sleep: @Sendable (Duration) async -> Void
    private let jitter: @Sendable () -> Double
    private var task: Task<Void, Never>?

    init(
        store: PersonFactsStore, isConnectionGood: @escaping @Sendable () -> Bool = { true },
        now: @escaping @Sendable () -> Date = { .now },
        sleep: @escaping @Sendable (Duration) async -> Void = { try? await Task.sleep(for: $0) },
        jitter: @escaping @Sendable () -> Double = {
            Double.random(in: -PersonSweep.jitterDays...PersonSweep.jitterDays)
        }
    ) {
        self.store = store
        self.isConnectionGood = isConnectionGood
        self.now = now
        self.sleep = sleep
        self.jitter = jitter
    }

    // MARK: Plan

    /// The persons of the library, composers first, in the order the pass takes them.
    static func people(of index: WorkIndex) -> [Person] {
        let composers = index.composers.filter { $0.name != Song.unknownComposer }.map {
            Person(kind: .composer, tag: $0.name)
        }
        return composers + index.performers.map { Person(kind: .performer, tag: $0.name) }
    }

    /// The days after which the person is due again.
    func interval(of person: Person) -> Int {
        let qid = person.kind == .composer ? store.qid(ofComposer: person.tag) : store.qid(ofPerformer: person.tag)
        guard let qid, let facts = store.cache.people[qid] else { return Self.unknownDays }
        return facts.died == nil ? Self.livingDays : Self.deadDays
    }

    /// The persons to look up, new ones first in library order, then due ones with the longest wait first.
    func plan(_ people: [Person]) -> (new: [Person], due: [Person]) {
        let current = now()
        var new: [Person] = []
        var due: [(person: Person, overdue: TimeInterval)] = []
        for person in people {
            guard let last = store.cache.checked[person.key] else {
                new.append(person)
                continue
            }
            let expires = store.cache.due[person.key] ?? last.addingTimeInterval(Double(interval(of: person)) * 86_400)
            if expires <= current { due.append((person, current.timeIntervalSince(expires))) }
        }
        return (new, due.sorted { $0.overdue > $1.overdue }.map(\.person))
    }

    /// Counts what waits, for Settings.
    func measure(_ people: [Person]) {
        let found = plan(people)
        newCount = found.new.count
        dueCount = found.due.count
        if case .running = state { return }
        if case .paused = state { return }
        state = found.new.isEmpty && found.due.isEmpty ? .upToDate : .idle
    }

    // MARK: Run

    var isRunning: Bool { task != nil }

    /// Starts a pass over the persons. A pass that runs already keeps going.
    func start(_ people: [Person]) {
        guard task == nil else { return }
        task = Task { [weak self] in
            await self?.run(people)
            self?.task = nil
        }
    }

    /// Returns when the pass has ended.
    func finish() async {
        await task?.value
    }

    /// Stops the pass. The persons that it settled stay settled.
    func stop() {
        task?.cancel()
        task = nil
        if case .running = state { state = .idle }
    }

    /// Runs a pass to its end, and returns when it ends or is stopped.
    func run(_ people: [Person]) async {
        let found = plan(people)
        let jobs = found.new + found.due
        newCount = found.new.count
        dueCount = found.due.count
        guard !jobs.isEmpty else {
            state = .upToDate
            return
        }
        var failures = 0
        var done = 0
        for person in jobs {
            while !Task.isCancelled {
                guard isConnectionGood() else {
                    state = .paused(.connection)
                    await sleep(.seconds(30))
                    continue
                }
                state = .running(done: done, total: jobs.count)
                if await settle(person) {
                    failures = 0
                    break
                }
                failures += 1
                let wait = min(3600, 60 * (1 << min(failures - 1, 6)))
                state = .paused(.slowDown(until: now().addingTimeInterval(Double(wait))))
                await sleep(.seconds(wait))
            }
            if Task.isCancelled {
                state = .idle
                return
            }
            done += 1
            if done <= found.new.count { newCount -= 1 } else { dueCount -= 1 }
        }
        state = .idle
        measure(people)
    }

    /// Looks one person up, or asks again for their facts. Returns false when a request failed.
    private func settle(_ person: Person) async -> Bool {
        let isNew = store.cache.checked[person.key] == nil
        let ok: Bool
        switch person.kind {
        case .composer:
            ok = await settle(composer: person, isNew: isNew)
        case .performer:
            ok = await settle(performer: person, isNew: isNew)
        }
        if ok {
            let days = Double(interval(of: person)) + min(max(jitter(), -Self.jitterDays), Self.jitterDays)
            store.markChecked(person.key, at: now(), due: now().addingTimeInterval(days * 86_400))
        }
        return ok
    }

    private func settle(composer person: Person, isNew: Bool) async -> Bool {
        if !isNew, let qid = store.qid(ofComposer: person.tag) { return await store.refresh(qid) }
        return await store.lookUp(composer: person.tag, again: !isNew)
    }

    private func settle(performer person: Person, isNew: Bool) async -> Bool {
        if !isNew, let qid = store.qid(ofPerformer: person.tag) { return await store.refresh(qid) }
        if !isNew { store.reopen(performer: person.tag) }
        return await store.resolve(performer: person.tag)
    }
}

/// Tells whether the connection suits a long run of small requests: it works, and it is neither metered nor
/// in Low Data Mode (ADR 0042).
final class ConnectionMonitor: @unchecked Sendable {
    private let monitor = NWPathMonitor()
    private let lock = NSLock()
    private var good = true

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let usable = path.status == .satisfied && !path.isConstrained && !path.isExpensive
            self?.lock.withLock { self?.good = usable }
        }
        monitor.start(queue: DispatchQueue(label: "de.whnr.klassik.connection"))
    }

    var isGood: Bool { lock.withLock { good } }

    deinit { monitor.cancel() }
}
