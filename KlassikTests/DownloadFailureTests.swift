import Foundation
import Testing

@testable import Klassik

struct DownloadFailureTests {
    @Test func aURLErrorShowsCodeAndName() {
        #expect(DownloadFailure.text(for: URLError(.timedOut)) == "-1001 timed out")
        #expect(DownloadFailure.text(for: URLError(.cannotParseResponse)) == "-1017 cannot parse response")
    }

    @Test func anUnknownURLCodeStillShowsItsNumber() {
        let error = NSError(domain: NSURLErrorDomain, code: -1999)
        #expect(DownloadFailure.text(for: error) == "-1999 network error")
    }

    @Test func aServerAnswerShowsTheStatus() {
        #expect(DownloadFailure.text(for: SubsonicError.http(status: 503)) == "HTTP 503")
    }

    @Test func theTextIsShortEnoughForOneLine() {
        #expect(DownloadFailure.text(for: URLError(.serverCertificateUntrusted)).count <= 30)
    }

    @Test func theLogLineHoldsNoLoginDetails() {
        let url = URL(string: "https://music.example/rest/stream?u=flo&t=SECRETTOKEN&s=SALT123&id=a")!
        let error = URLError(
            .timedOut,
            userInfo: [NSURLErrorFailingURLErrorKey: url, NSURLErrorFailingURLStringErrorKey: url.absoluteString])
        let text = DownloadFailure.logText(for: error, song: "a")
        for secret in ["SECRETTOKEN", "SALT123", "u=flo", "?"] {
            #expect(!text.contains(secret), "log holds \(secret)")
        }
        #expect(text.contains("-1001"))
        #expect(text.contains("music.example"))
    }
}
