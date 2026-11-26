import Foundation
import Observation
import Synchronization

extension AccentFamily: Identifiable {
    static let storageKey = "accentFamily"

    var id: Self { self }

    var title: String {
        switch self {
        case .claret: L("Claret")
        case .green: L("Bottle Green")
        case .plum: L("Plum")
        }
    }

    /// The family that the listener picked in Settings. Every colour of the app reads it.
    static var current: AccentFamily { AccentChoice.shared.family }
}

/// The accent switch of Settings. A view that reads a colour observes the pick, so a new pick redraws it
/// at once. Colours resolve off the main actor too, so a lock guards the value.
final class AccentChoice: Observable, Sendable {
    static let shared = AccentChoice()

    private let registrar = ObservationRegistrar()
    private let stored: Mutex<AccentFamily>
    private let key: String

    init(storageKey: String = AccentFamily.storageKey) {
        key = storageKey
        let saved = UserDefaults.standard.string(forKey: storageKey).flatMap(AccentFamily.init(rawValue:))
        stored = Mutex(saved ?? .standard)
    }

    var family: AccentFamily {
        get {
            registrar.access(self, keyPath: \.family)
            return stored.withLock { $0 }
        }
        set {
            registrar.withMutation(of: self, keyPath: \.family) {
                stored.withLock { $0 = newValue }
            }
            UserDefaults.standard.set(newValue.rawValue, forKey: key)
        }
    }
}
