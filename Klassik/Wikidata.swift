import Foundation

/// Reads the publication date (P577) of works from Wikidata, found by their MusicBrainz work ID (P435).
/// Klassik asks only for works that MusicBrainz has no date for.
struct Wikidata: Sendable {
    static let endpoint = URL(string: "https://query.wikidata.org/sparql")!
    /// The IDs of one query. 50 IDs keep the URL well below the length that servers accept.
    static let batchSize = 50

    var fetch: MusicBrainz.Fetch = MusicBrainz.network
    var pacer = Pacer.wikidata

    /// The earliest P577 year of each MusicBrainz work ID that Wikidata has a date for.
    func published(musicBrainzIDs ids: [String]) async throws -> [String: Int] {
        // Only UUIDs go into the query, so no text from the tags can change it.
        let values = ids.filter { UUID(uuidString: $0) != nil }.map { "\"\($0.lowercased())\"" }
        guard !values.isEmpty else { return [:] }
        let query =
            "SELECT ?id ?date WHERE { VALUES ?id { \(values.joined(separator: " ")) } "
            + "?work wdt:P435 ?id; wdt:P577 ?date. }"
        var request = URLRequest(
            url: Self.endpoint.appending(queryItems: [
                URLQueryItem(name: "query", value: query), URLQueryItem(name: "format", value: "json"),
            ]))
        request.setValue(MusicBrainz.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/sparql-results+json", forHTTPHeaderField: "Accept")
        await pacer.wait()
        let (data, status) = try await fetch(request)
        guard (200..<300).contains(status) else { throw MusicBrainz.Failure.http(status) }
        return try Self.earliestYears(data)
    }

    static func earliestYears(_ data: Data) throws -> [String: Int] {
        struct Results: Decodable {
            struct Body: Decodable {
                struct Binding: Decodable {
                    struct Value: Decodable {
                        var value: String
                    }
                    var id: Value?
                    var date: Value?
                }
                var bindings: [Binding]
            }
            var results: Body
        }
        var years: [String: Int] = [:]
        for binding in try JSONDecoder().decode(Results.self, from: data).results.bindings {
            guard let id = binding.id?.value, let year = YearSpan.year(of: binding.date?.value) else { continue }
            years[id] = min(years[id] ?? year, year)
        }
        return years
    }
}
