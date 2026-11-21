import Foundation
import Network

/// How much music the app may prepare without a request (ADR 0060). Download speed never changes it.
enum DataMode: Equatable, Sendable {
    /// Wi-Fi or another path that is not cellular, expensive or constrained: whole works.
    case normal
    /// Cellular, an expensive path, Low Data Mode or Low Power Mode: one following track only.
    case constrained
    /// No network: existing files only.
    case offline

    static func of(satisfied: Bool, constrained: Bool, cellular: Bool, lowPower: Bool) -> DataMode {
        if !satisfied { return .offline }
        return constrained || cellular || lowPower ? .constrained : .normal
    }
}

/// The tracks to prepare after the one that plays, in the order of the queue (ADR 0060).
enum ReadAhead {
    /// Normal mode prepares the rest of the current work or album and all of the next queue item.
    /// A constrained mode prepares exactly the next audible track, also across a work boundary.
    static func plan(_ item: QueueItem, movement: Int, upNext: [QueueItem], mode: DataMode) -> [Song] {
        let rest = Array(item.recording.songs.dropFirst(movement + 1))
        let next = upNext.first?.recording.songs ?? []
        switch mode {
        case .normal:
            // A queue item that repeats tracks of the current one prepares them once.
            var seen = Set(item.recording.songs.prefix(movement + 1).map(\.id))
            return (rest + next).filter { seen.insert($0.id).inserted }
        case .constrained: return Array((rest + next).prefix(1))
        case .offline: return []
        }
    }
}

/// Follows the network path and Low Power Mode for the read-ahead set (ADR 0060). It sees constrained Wi-Fi and an
/// expensive path, such as a personal hotspot, too.
final class DataModeMonitor: @unchecked Sendable {
    typealias Change = @MainActor @Sendable (_ mode: DataMode, _ pathChanged: Bool) -> Void

    private let monitor = NWPathMonitor()
    private let lock = NSLock()
    private var satisfied = true
    private var constrained = false
    private var cellular = false
    private var observer: (any NSObjectProtocol)?

    init(onChange: @escaping Change) {
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            let mode = lock.withLock {
                satisfied = path.status == .satisfied
                constrained = path.isConstrained
                cellular = path.usesInterfaceType(.cellular) || path.isExpensive
                return current()
            }
            Task { @MainActor in onChange(mode, true) }
        }
        observer = NotificationCenter.default.addObserver(
            forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: nil
        ) { [weak self] _ in
            guard let self else { return }
            let mode = lock.withLock { current() }
            Task { @MainActor in onChange(mode, false) }
        }
        monitor.start(queue: DispatchQueue(label: "de.whnr.klassik.datamode"))
    }

    /// Call it with `lock` held.
    private func current() -> DataMode {
        DataMode.of(
            satisfied: satisfied, constrained: constrained, cellular: cellular,
            lowPower: ProcessInfo.processInfo.isLowPowerModeEnabled)
    }

    deinit {
        monitor.cancel()
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }
}
