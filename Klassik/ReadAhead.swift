import Foundation
import Network

/// How much music the app may prepare without a request (ADR 0060).
enum DataMode: Equatable, Sendable {
    case normal
    /// Low Data Mode or Low Power Mode: one following track only.
    case constrained
    /// No network: existing files only.
    case offline

    static func of(satisfied: Bool, constrained: Bool, lowPower: Bool) -> DataMode {
        if !satisfied { return .offline }
        return constrained || lowPower ? .constrained : .normal
    }
}

/// The tracks to prepare after the one that plays, in the order of the queue (ADR 0060).
enum ReadAhead {
    /// Normal mode prepares the rest of the recording and the first track of the next queue item.
    /// A constrained mode prepares exactly the next audible track, also across a recording boundary.
    static func plan(_ item: QueueItem, movement: Int, upNext: [QueueItem], mode: DataMode) -> [Song] {
        let rest = Array(item.recording.songs.dropFirst(movement + 1))
        let following = rest + (upNext.first?.recording.songs.first.map { [$0] } ?? [])
        switch mode {
        case .normal: return following
        case .constrained: return Array(following.prefix(1))
        case .offline: return []
        }
    }
}

/// Follows the network path and Low Power Mode for the read-ahead set (ADR 0060). It sees constrained Wi-Fi too.
final class DataModeMonitor: @unchecked Sendable {
    typealias Change = @MainActor @Sendable (_ mode: DataMode, _ pathChanged: Bool) -> Void

    private let monitor = NWPathMonitor()
    private let lock = NSLock()
    private var satisfied = true
    private var constrained = false
    private var observer: (any NSObjectProtocol)?

    init(onChange: @escaping Change) {
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            let mode = lock.withLock {
                satisfied = path.status == .satisfied
                constrained = path.isConstrained
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
            satisfied: satisfied, constrained: constrained, lowPower: ProcessInfo.processInfo.isLowPowerModeEnabled)
    }

    deinit {
        monitor.cancel()
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }
}
