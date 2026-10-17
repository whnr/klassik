import Foundation
import Testing
@testable import Klassik

struct SubsonicClientTests {
    let client = SubsonicClient(credentials: ServerCredentials(
        url: URL(string: "https://music.example.org/navidrome")!, username: "joe", password: "sesame"))

    @Test(arguments: [
        ("music.example.org", "https://music.example.org"),
        ("  https://music.example.org/ ", "https://music.example.org"),
        ("http://localhost:4533", "http://localhost:4533"),
        ("https://example.org/navidrome/", "https://example.org/navidrome"),
    ])
    func normalizesTypedURL(typed: String, expected: String) {
        #expect(ServerCredentials.normalizedURL(from: typed)?.absoluteString == expected)
    }

    @Test(arguments: ["", "   ", "ftp://example.org", "https://"])
    func rejectsUnusableURL(typed: String) {
        #expect(ServerCredentials.normalizedURL(from: typed) == nil)
    }

    /// The example from the Subsonic API documentation.
    @Test func tokenIsMD5OfPasswordAndSalt() {
        #expect(SubsonicClient.token(password: "sesame", salt: "c19b2d") == "26719a1196d2a940705a59634eb18eab")
    }

    @Test func requestKeepsServerPathAndSendsNoPassword() throws {
        let url = client.url("ping", salt: "c19b2d")
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let query = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        #expect(components.path == "/navidrome/rest/ping")
        #expect(query["u"] == "joe")
        #expect(query["t"] == "26719a1196d2a940705a59634eb18eab")
        #expect(query["s"] == "c19b2d")
        #expect(query["f"] == "json")
        #expect(query["p"] == nil)
        #expect(!url.absoluteString.contains("sesame"))
    }

    @Test func decodesNavidromePing() throws {
        let json = #"{"subsonic-response":{"status":"ok","version":"1.16.1","type":"navidrome","serverVersion":"0.64.2 (10114574)","openSubsonic":true}}"#
        let response = try SubsonicClient.decode(Data(json.utf8))
        #expect(response.version == "1.16.1")
        #expect(response.type == "navidrome")
        #expect(response.openSubsonic == true)
    }

    @Test func surfacesServerError() {
        let json = #"{"subsonic-response":{"status":"failed","version":"1.16.1","error":{"code":40,"message":"Wrong username or password"}}}"#
        #expect(throws: SubsonicError.server(code: 40, message: "Wrong username or password")) {
            try SubsonicClient.decode(Data(json.utf8))
        }
    }

    /// A reverse proxy login page instead of the API.
    @Test func rejectsNonSubsonicAnswer() {
        #expect(throws: SubsonicError.notSubsonic) {
            try SubsonicClient.decode(Data("<html>Login</html>".utf8))
        }
    }
}
