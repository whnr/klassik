import Foundation
import Testing

@testable import Klassik

/// The bottom of Settings names the real version and build.
struct SettingsVersionTests {
    @Test func showsVersionAndBuild() {
        let info: [String: Any] = ["CFBundleShortVersionString": "0.23.0", "CFBundleVersion": "76"]
        #expect(SettingsView.version(from: info) == "0.23.0 (76)")
    }

    @Test func emptyValuesShowAsQuestionMarks() {
        let info: [String: Any] = ["CFBundleShortVersionString": "", "CFBundleVersion": " "]
        #expect(SettingsView.version(from: info) == "? (?)")
        #expect(SettingsView.version(from: nil) == "? (?)")
    }

    /// The app bundle carries a real version and a numeric build.
    @Test func theBundleReportsARealVersion() {
        let text = SettingsView.version(from: Bundle(for: BundleToken.self).infoDictionary)
        #expect(text.wholeMatch(of: /\d+\.\d+\.\d+ \(\d+\)/) != nil)
    }
}

private final class BundleToken {}
