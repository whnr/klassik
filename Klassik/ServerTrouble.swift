import Foundation

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

/// Why changes of the listener wait on the device. Each kind of change keeps its own, and the Library shows one quiet
/// line for all of them.
enum ServerTrouble: Equatable, Sendable {
    /// No answer: no connection, or the server is down.
    case unreachable
    /// The server answered and did not take a change.
    case refused

    /// Nil when nothing failed. A connection failure wins, because it also stops the changes after it.
    init?(_ failures: [any Error]) {
        var trouble: ServerTrouble?
        for failure in failures {
            if failure is URLError {
                self = .unreachable
                return
            }
            trouble = .refused
        }
        guard let trouble else { return nil }
        self = trouble
    }

    /// The trouble of several kinds of change together: no answer wins over a refusal.
    static func worst(_ troubles: [ServerTrouble?]) -> ServerTrouble? {
        if troubles.contains(.unreachable) { return .unreachable }
        return troubles.contains(.refused) ? .refused : nil
    }

    /// The one quiet status line.
    var status: String {
        switch self {
        case .unreachable: L("Server not reachable. Changes wait on this iPhone.")
        case .refused: L("The server did not take some changes. They wait on this iPhone.")
        }
    }
}
