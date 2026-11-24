import Foundation

/// Shares one limit across encoded files. Reservations include open files after their directory entries disappear.
public final class AudioStorageBudget: @unchecked Sendable {
    private struct Entry {
        var url: URL
        var bytes: Int64
        /// An explicit download owns these bytes. Downloads stay outside the Music limit (ADR 0060).
        var exempt = false
    }

    private let lock = NSLock()
    private var entries: [UUID: Entry] = [:]
    private var files: [URL: Int64] = [:]
    private var maximum: Int64

    public init(limit: Int64) { maximum = max(0, limit) }

    public var limit: Int64 {
        get { lock.withLock { maximum } }
        set { lock.withLock { maximum = max(0, newValue) } }
    }

    public var storedBytes: Int64 { lock.withLock { total() } }
    public var availableBytes: Int64 { lock.withLock { max(0, maximum - total()) } }

    /// Reconciles complete files and abandoned partial files. Active reservations count their own bytes.
    public func synchronize(_ sizes: [URL: Int64]) {
        lock.withLock {
            let managed = Set(entries.values.map(\.url))
            files = sizes.filter { !managed.contains($0.key) }
        }
    }

    func reserve(_ url: URL) -> Reservation {
        let id = UUID()
        lock.withLock { entries[id] = Entry(url: url, bytes: 0) }
        return Reservation(budget: self, id: id)
    }

    private func total() -> Int64 {
        files.values.reduce(0, +) + entries.values.reduce(0) { $0 + ($1.exempt ? 0 : $1.bytes) }
    }

    final class Reservation {
        private let budget: AudioStorageBudget
        private let id: UUID

        fileprivate init(budget: AudioStorageBudget, id: UUID) {
            self.budget = budget
            self.id = id
        }

        var availableGrowth: Int64 {
            budget.lock.withLock {
                budget.entries[id]?.exempt == true ? .max : max(0, budget.maximum - budget.total())
            }
        }

        /// An exempt reservation grows without the limit and does not count against it. Its directory entry stays
        /// managed, so a rescan of the cache folder does not count it as an abandoned file.
        var isExempt: Bool {
            get { budget.lock.withLock { budget.entries[id]?.exempt == true } }
            set { budget.lock.withLock { budget.entries[id]?.exempt = newValue } }
        }

        /// Reserve growth before writing. Reusing circular slots needs no additional reservation.
        func resize(to bytes: Int64) -> Bool {
            budget.lock.withLock {
                guard bytes >= 0, let current = budget.entries[id] else { return false }
                let growth = bytes - current.bytes
                guard current.exempt || growth <= 0 || growth <= budget.maximum - budget.total() else {
                    return false
                }
                budget.entries[id]?.bytes = bytes
                return true
            }
        }

        /// Publication transfers storage ownership without charging for a second physical file.
        func publish(to url: URL) {
            budget.lock.withLock {
                budget.files[url] = nil
                budget.entries[id]?.url = url
            }
        }

        deinit {
            budget.lock.withLock {
                guard let entry = budget.entries.removeValue(forKey: id) else { return }
                // A completed download that stays in the cache folder counts under Music from here on.
                if FileManager.default.fileExists(atPath: entry.url.path()) {
                    budget.files[entry.url] = entry.bytes
                }
            }
        }
    }
}
