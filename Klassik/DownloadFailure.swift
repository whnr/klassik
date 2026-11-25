import Foundation
import os

/// The one-line text of a failed download. The menu row has room for one short line, so the text gives the code
/// and a short name, never the system's long sentence.
enum DownloadFailure {
    static let log = Logger(subsystem: "de.whnr.klassik", category: "downloads")

    /// Short names of the URL error codes that a download can end with.
    private static let names: [Int: String] = [
        -999: "cancelled", -1000: "bad URL", -1001: "timed out", -1002: "unsupported URL", -1003: "host not found",
        -1004: "cannot connect", -1005: "connection lost", -1009: "offline", -1011: "bad response",
        -1013: "needs login", -1017: "cannot parse response", -1022: "blocked by ATS",
        -1200: "TLS failed", -1202: "untrusted certificate", -995: "needs shared container",
        -996: "session in use", -997: "session disconnected",
    ]

    static func text(for error: any Error) -> String {
        if case SubsonicError.http(let code) = error { return "HTTP \(code)" }
        let ns = error as NSError
        guard ns.domain == NSURLErrorDomain else { return "\(ns.domain) \(ns.code)" }
        return "\(ns.code) \(names[ns.code] ?? "network error")"
    }

    /// The log line of a failed download. It never holds the error's userInfo: a URL error carries the stream URL,
    /// whose query is the user, token and salt of the login.
    static func logText(for error: any Error, song: String) -> String {
        let ns = error as NSError
        var text = "download of \(song) failed: \(ns.domain) \(ns.code) \(ns.localizedDescription)"
        if let url = ns.userInfo[NSURLErrorFailingURLErrorKey] as? URL {
            text += " at \(url.host() ?? "") \(url.path())"
        }
        return text
    }

    /// Writes the error to the app log, which a person reads with the device console.
    static func record(_ error: any Error, song: String) {
        log.error("\(logText(for: error, song: song), privacy: .public)")
    }
}
