import Foundation
import Observation

/// An action that a row can hold on a swipe.
enum SwipeAction: String, CaseIterable, Identifiable, Codable, Sendable {
    case playNext
    case addToQueue
    case download
    case reference

    var id: Self { self }

    var title: String {
        switch self {
        case .playNext: "Play Next"
        case .addToQueue: "Add to Queue"
        case .download: "Download"
        case .reference: "Reference Recording"
        }
    }
}

/// Which actions sit on which swipe edge of a row. Two actions fit on each edge.
@MainActor @Observable
final class SwipeSettings {
    static let defaultLeading: [SwipeAction] = [.download, .reference]
    static let defaultTrailing: [SwipeAction] = [.addToQueue, .playNext]
    static let slots = 2

    /// The actions on the edge that opens by a swipe to the right, in order. A slot can stay empty.
    var leading: [SwipeAction?] {
        didSet { save(leading, key: Self.leadingKey) }
    }
    /// The actions on the edge that opens by a swipe to the left, in order.
    var trailing: [SwipeAction?] {
        didSet { save(trailing, key: Self.trailingKey) }
    }

    private let defaults: UserDefaults
    private static let leadingKey = "swipe.leading"
    private static let trailingKey = "swipe.trailing"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        leading = Self.load(Self.leadingKey, from: defaults) ?? Self.defaultLeading
        trailing = Self.load(Self.trailingKey, from: defaults) ?? Self.defaultTrailing
    }

    func reset() {
        leading = Self.defaultLeading
        trailing = Self.defaultTrailing
    }

    /// The actions of an edge without gaps and without an action twice.
    static func actions(_ slots: [SwipeAction?]) -> [SwipeAction] {
        var seen: [SwipeAction] = []
        for case let action? in slots where !seen.contains(action) { seen.append(action) }
        return seen
    }

    private func save(_ slots: [SwipeAction?], key: String) {
        defaults.set(slots.map { $0?.rawValue ?? "" }, forKey: key)
    }

    private static func load(_ key: String, from defaults: UserDefaults) -> [SwipeAction?]? {
        guard let stored = defaults.stringArray(forKey: key) else { return nil }
        return stored.map { SwipeAction(rawValue: $0) }
    }
}
