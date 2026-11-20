import Foundation
import Observation
import Testing

@testable import Klassik

/// The accent switch of Settings: claret by default, bottle green and plum on request (ADR 0034).
struct AccentTests {
    private func key() -> String { "accent-test-\(UUID().uuidString)" }

    @Test func claretIsTheDefaultAndAPickStays() {
        let key = key()
        defer { UserDefaults.standard.removeObject(forKey: key) }
        let choice = AccentChoice(storageKey: key)
        #expect(choice.family == .claret)
        choice.family = .plum
        #expect(AccentChoice(storageKey: key).family == .plum)
    }

    @Test func theSwitchOffersThreeFamilies() {
        #expect(AccentFamily.allCases.map(\.title) == ["Claret", "Bottle Green", "Plum"])
        #expect(AccentFamily.standard == .claret)
    }

    @Test(arguments: AccentFamily.allCases)
    func aColourNamesTheSetOfItsFamily(family: AccentFamily) {
        #expect(Palette.tint.assetName(in: family) == "\(family.rawValue)/Tint")
    }

    /// A view that reads a colour redraws when the listener picks another family.
    @Test func aPickTellsItsObservers() {
        let key = key()
        defer { UserDefaults.standard.removeObject(forKey: key) }
        let choice = AccentChoice(storageKey: key)
        let changed = Changed()
        withObservationTracking {
            _ = choice.family
        } onChange: {
            changed.mark()
        }
        choice.family = .green
        #expect(changed.value)
    }

    private final class Changed: @unchecked Sendable {
        private(set) var value = false
        func mark() { value = true }
    }
}
