import Foundation

/// Reads the publication date (P577) of a work from Wikidata, found by its MusicBrainz work ID (P435).
/// Klassik asks only when MusicBrainz has no date.
struct Wikidata: Sendable {
    static let endpoint = URL(string: "https://query.wikidata.org/sparql")!

    var fetch: MusicBrainz.Fetch = MusicBrainz.network
    var pacer = Pacer.wikidata

    /// The earliest year of all P577 values of the items with this MusicBrainz work ID.
    func published(musicBrainzID id: String) async throws -> Int? {
        // Only a UUID goes into the query, so no text from the tags can change it.
        guard UUID(uuidString: id) != nil else { return nil }
        let query = "SELECT ?date WHERE { ?work wdt:P435 \"\(id.lowercased())\"; wdt:P577 ?date. }"
        var request = URLRequest(
            url: Self.endpoint.appending(queryItems: [
                URLQueryItem(name: "query", value: query), URLQueryItem(name: "format", value: "json"),
            ]))
        request.setValue(MusicBrainz.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/sparql-results+json", forHTTPHeaderField: "Accept")
        await pacer.wait()
        let (data, status) = try await fetch(request)
        guard (200..<300).contains(status) else { throw MusicBrainz.Failure.http(status) }
        return try Self.earliestYear(data)
    }

    static func earliestYear(_ data: Data) throws -> Int? {
        struct Results: Decodable {
            struct Body: Decodable {
                struct Binding: Decodable {
                    struct Value: Decodable {
                        var value: String
                    }
                    var date: Value?
                }
                var bindings: [Binding]
            }
            var results: Body
        }
        return try JSONDecoder().decode(Results.self, from: data).results.bindings
            .compactMap { YearSpan.year(of: $0.date?.value) }.min()
    }
}
