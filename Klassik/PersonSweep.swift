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
    /// A pass tries one person at most this many times. Then the person waits for its next due time.
    static let triesPerPass = 2
    /// A picture that Commons did not answer in any try of a pass waits this long after the first such pass, then
    /// twice as long after each next one, at most `pictureWaitMaxHours`. The first wait is short,
    /// because a short loss of the connection can fail both tries of a pass.
    static let pictureWaitHours = 1.0
    static let pictureWaitMaxHours = 24.0
    /// The most shown performers that the pass keeps in front. A long scroll through the performers adds more.
    static let shownLimit = 100

    private(set) var state = State.idle
    /// The persons that have no check yet, and the persons whose check is due.
    private(set) var newCount = 0
    private(set) var dueCount = 0

    private let store: PersonFactsStore
    private let isConnectionGood: @Sendable () -> Bool
    private let now: @Sendable () -> Date
    private let sleep: @Sendable (Duration) async -> Void
    private let jitter: @Sendable () -> Double
    /// Keeps a found picture on the device, given the picture that the person had before the lookup.
    private let keepPicture: @MainActor @Sendable (PersonPortrait, PersonPortrait?) async -> Bool
    private let hasPicture: @MainActor @Sendable (PersonPortrait) async -> Bool
    private var task: Task<Void, Never>?
    /// Picture downloads run one after the other beside the lookup, so that they never slow it down.
    @ObservationIgnored private var pictureWork: Task<Void, Never>?
    @ObservationIgnored private var pictureID = UUID()
    /// Performers that a page shows and that have no saved check, the latest page first.
    @ObservationIgnored private(set) var shown: [Person] = []

    init(
        store: PersonFactsStore, isConnectionGood: @escaping @Sendable () -> Bool = { true },
        now: @escaping @Sendable () -> Date = { .now },
        sleep: @escaping @Sendable (Duration) async -> Void = { try? await Task.sleep(for: $0) },
        jitter: @escaping @Sendable () -> Double = {
            Double.random(in: -PersonSweep.jitterDays...PersonSweep.jitterDays)
        },
        pictures: @escaping @MainActor @Sendable (PersonPortrait, PersonPortrait?) async -> Bool = { _, _ in true },
        hasPicture: @escaping @MainActor @Sendable (PersonPortrait) async -> Bool = { _ in true }
    ) {
        self.store = store
        self.isConnectionGood = isConnectionGood
        self.now = now
        self.sleep = sleep
        self.jitter = jitter
        keepPicture = pictures
        self.hasPicture = hasPicture
    }

    // MARK: Plan

    /// The persons of the library, composers first, in library order.
    static func people(of index: WorkIndex) -> [Person] {
        let composers = index.composers.filter { $0.name != Song.unknownComposer }.map {
            Person(kind: .composer, tag: $0.name)
        }
        return composers + index.performers.map { Person(kind: .performer, tag: $0.name) }
    }

    /// The days after which the person is due again.
    func interval(of person: Person) -> Int {
        guard let qid = qid(of: person), let facts = store.cache.people[qid] else { return Self.unknownDays }
        return facts.died == nil ? Self.livingDays : Self.deadDays
    }

    /// The persons to look up, new ones in library order, and due ones with the longest wait first.
    func plan(_ people: [Person]) -> (new: [Person], due: [Person]) {
        let current = now()
        var new: [Person] = []
        var due: [(person: Person, overdue: TimeInterval)] = []
        for person in people {
            // A picture that Commons did not answer goes first after its short wait, whatever the check says.
            if missesPicture(person) {
                if let wait = store.cache.pictureWait[person.key], wait > current { continue }
                if store.cache.checked[person.key] == nil {
                    new.append(person)
                } else {
                    due.append((person, .greatestFiniteMagnitude))
                }
                continue
            }
            guard let last = store.cache.checked[person.key] else {
                // A person that failed in an earlier pass waits for the due time that the pass saved.
                if let due = store.cache.due[person.key], due > current { continue }
                new.append(person)
                continue
            }
            let expires = store.cache.due[person.key] ?? last.addingTimeInterval(Double(interval(of: person)) * 86_400)
            if expires <= current { due.append((person, current.timeIntervalSince(expires))) }
        }
        return (new, due.sorted { $0.overdue > $1.overdue }.map(\.person))
    }

    /// The order of a pass: all composers before all performers, new ones before due ones in each group.
    func order(_ people: [Person]) -> [Person] {
        let found = plan(people)
        let all = found.new + found.due
        return all.filter { $0.kind == .composer } + all.filter { $0.kind == .performer }
    }

    /// Puts the performers of a page in front of the pass, when they were never looked up.
    func prefer(performers tags: [String]) {
        var seen: Set<Person> = []
        let fresh = tags.map { Person(kind: .performer, tag: $0) }.filter {
            store.cache.checked[$0.key] == nil && seen.insert($0).inserted
        }
        guard !fresh.isEmpty else { return }
        shown = Array((fresh + shown.filter { !seen.contains($0) }).prefix(Self.shownLimit))
    }

    /// Marks the people whose saved texts are of another language than the app asks for. A device language that
    /// changed while the app was closed leaves no in-session change to see, so each pass starts with this.
    func invalidateStaleTexts() {
        store.invalidateTexts()
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

    /// Returns when the pass and its picture downloads have ended.
    func finish() async {
        await task?.value
        await pictureWork?.value
    }

    /// Stops the pass. The persons that it settled stay settled.
    func stop() {
        task?.cancel()
        pictureWork?.cancel()
        pictureID = UUID()
        task = nil
        if case .running = state { state = .idle }
    }

    /// Runs a pass to its end, and returns when it ends or is stopped.
    /// A failed person goes to the end of the queue, so that it does not hold up the others.
    func run(_ people: [Person]) async {
        for person in people {
            guard !Task.isCancelled else { return }
            if let found = portrait(of: person) {
                let kept = await hasPicture(found)
                if store.cache.picturePending[person.key] == nil, !kept {
                    store.queuePicture(person.key, portrait: found, old: nil)
                }
            }
            if let work = store.cache.picturePending[person.key] { queuePicture(person.key, work: work) }
        }
        let found = plan(people)
        let jobs = order(people)
        let newOnes = Set(found.new)
        newCount = found.new.count
        dueCount = found.due.count
        guard !jobs.isEmpty else {
            state = .upToDate
            return
        }
        var queue = jobs
        var next = 0
        var tries: [Person: Int] = [:]
        var failuresInARow = 0
        var done = 0
        while next < queue.count {
            guard await waitForConnection() else {
                state = .idle
                return
            }
            // The pick comes after the wait, so that a page shown during a pause still goes first.
            if let front = shownIndex(in: queue, from: next, tries: tries), front != next {
                let moved = queue.remove(at: front)
                queue.insert(moved, at: next)
            }
            let person = queue[next]
            next += 1
            state = .running(done: done, total: jobs.count)
            let settled = await settle(person)
            guard !Task.isCancelled else {
                state = .idle
                return
            }
            shown.removeAll { $0 == person }
            if settled {
                failuresInARow = 0
            } else {
                failuresInARow += 1
                tries[person, default: 0] += 1
                let retries = tries[person, default: 0] < Self.triesPerPass
                if retries { queue.append(person) } else { postpone(person) }
                if next < queue.count { await backOff(failuresInARow: failuresInARow) }
                if Task.isCancelled {
                    state = .idle
                    return
                }
                if retries { continue }
            }
            done += 1
            if newOnes.contains(person) { newCount -= 1 } else { dueCount -= 1 }
        }
        state = .idle
        measure(people)
    }

    /// The place of the first shown performer that waits in the queue and has no try in this pass. A failed
    /// performer keeps its place at the end of the queue.
    private func shownIndex(in queue: [Person], from next: Int, tries: [Person: Int]) -> Int? {
        for person in shown where tries[person] == nil && store.cache.checked[person.key] == nil {
            if let index = queue[next...].firstIndex(of: person) { return index }
        }
        return nil
    }

    /// Returns false when the pass is stopped before the connection suits it.
    private func waitForConnection() async -> Bool {
        while !Task.isCancelled {
            if isConnectionGood() { return true }
            state = .paused(.connection)
            await sleep(.seconds(30))
        }
        return false
    }

    /// One failure waits only for Wikimedia's Retry-After. Failures in a row point to a service problem: from
    /// the second, the pass waits 1, 2, 4 minutes and so on, at most one hour, or longer when Retry-After asks.
    private func backOff(failuresInARow failures: Int) async {
        let backoff = failures < 2 ? 0 : min(3600, 60 * (1 << min(failures - 2, 6)))
        let wait = max(backoff, Int((await store.throttleHold()).rounded(.up)))
        guard wait > 0 else { return }
        state = .paused(.slowDown(until: now().addingTimeInterval(Double(wait))))
        await sleep(.seconds(wait))
    }

    /// A person that failed every try of the pass gets the due time of a check, without being marked checked.
    /// A person without their picture waits a short time instead, so that a lasting Commons failure costs one
    /// pass a day at most and the picture still arrives soon after Commons works again.
    private func postpone(_ person: Person) {
        if missesPicture(person) {
            let failures = (store.cache.pictureFailures[person.key] ?? 0) + 1
            let hours = min(Self.pictureWaitMaxHours, Self.pictureWaitHours * pow(2, Double(min(failures - 1, 10))))
            store.postponePicture(person.key, until: now().addingTimeInterval(hours * 3600), failures: failures)
        } else {
            store.postpone(person.key, due: dueDate(of: person))
        }
    }

    private func dueDate(of person: Person) -> Date {
        let days = Double(interval(of: person)) + min(max(jitter(), -Self.jitterDays), Self.jitterDays)
        return now().addingTimeInterval(days * 86_400)
    }

    /// Looks one person up, or asks again for their facts. Returns false when a request failed.
    private func settle(_ person: Person) async -> Bool {
        let before = portrait(of: person)
        let isNew = store.cache.checked[person.key] == nil
        var ok: Bool
        if missesPicture(person), let qid = qid(of: person) {
            ok = await store.retryPicture(qid)
        } else {
            switch person.kind {
            case .composer:
                ok = await settle(composer: person, isNew: isNew)
            case .performer:
                ok = await settle(performer: person, isNew: isNew)
            }
        }
        // Facts without their picture do not settle a person, so the next pass asks Commons again.
        if ok, missesPicture(person) { ok = false }
        if ok { store.markChecked(person.key, at: now(), due: dueDate(of: person)) }
        // Each lookup fetches the picture, so a page never waits for it and a changed one replaces the old (ADR 0059).
        if ok, let found = portrait(of: person) {
            store.queuePicture(person.key, portrait: found, old: before)
            if let work = store.cache.picturePending[person.key] { queuePicture(person.key, work: work) }
        }
        return ok
    }

    private func qid(of person: Person) -> String? {
        person.kind == .composer ? store.qid(ofComposer: person.tag) : store.qid(ofPerformer: person.tag)
    }

    private func portrait(of person: Person) -> PersonPortrait? {
        qid(of: person).flatMap { store.cache.people[$0]?.portrait }
    }

    private func missesPicture(_ person: Person) -> Bool {
        qid(of: person).flatMap { store.cache.people[$0]?.pictureUnread } == true
    }

    private func queuePicture(_ key: String, work: PersonFactsStore.PictureWork) {
        let previous = pictureWork
        let keep = keepPicture
        let id = pictureID
        pictureWork = Task {
            await previous?.value
            await store.saved()
            guard !Task.isCancelled, pictureID == id, isConnectionGood() else { return }
            if await keep(work.portrait, work.old), !Task.isCancelled, pictureID == id {
                store.finishPicture(key, work: work)
            }
        }
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

/// Tells whether the connection suits a long run of small requests: it works and it is not metered. Low Data
/// Mode alone does not stop people pictures; mobile data keeps the limit of ADR 0042.
final class ConnectionMonitor: @unchecked Sendable {
    private let monitor = NWPathMonitor()
    private let lock = NSLock()
    private var good = true

    /// `onConnect` also accepts mobile data and Low Data Mode for small queued writes.
    init(onConnect: @escaping @Sendable () -> Void = {}) {
        monitor.pathUpdateHandler = { [weak self] path in
            let usable = path.status == .satisfied && !path.isExpensive
            self?.lock.withLock { self?.good = usable }
            if path.status == .satisfied { onConnect() }
        }
        monitor.start(queue: DispatchQueue(label: "de.whnr.klassik.connection"))
    }

    var isGood: Bool { lock.withLock { good } }

    deinit { monitor.cancel() }
}
