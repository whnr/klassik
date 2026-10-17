import Foundation
import Testing
@testable import Klassik

struct InfoPlistTests {
    var info: [String: Any] { Bundle(for: BundleToken.self).infoDictionary ?? [:] }

    /// Home servers often run on the local network without TLS.
    @Test func allowsLocalNetworking() {
        let ats = info["NSAppTransportSecurity"] as? [String: Any]
        #expect(ats?["NSAllowsLocalNetworking"] as? Bool == true)
        #expect((info["NSLocalNetworkUsageDescription"] as? String)?.isEmpty == false)
    }

    /// Playback continues while the phone is locked.
    @Test func playsAudioInBackground() {
        #expect((info["UIBackgroundModes"] as? [String])?.contains("audio") == true)
    }

    @Test func versionIsSemantic() {
        let version = info["CFBundleShortVersionString"] as? String ?? ""
        #expect(version.wholeMatch(of: /\d+\.\d+\.\d+/) != nil)
    }

    /// Without this key every TestFlight upload waits for an export compliance answer.
    @Test func declaresNoCustomEncryption() {
        #expect(info["ITSAppUsesNonExemptEncryption"] as? Bool == false)
    }
}
