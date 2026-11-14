import Foundation

/// What one source says about one picture, text or fact, for the About tab (ADR 0017).
struct PersonCredit: Codable, Equatable, Hashable, Sendable {
    enum Kind: String, Codable, Sendable {
        case picture, text, facts

        var title: String {
            switch self {
            case .picture: "Picture"
            case .text: "Text"
            case .facts: "Facts"
            }
        }
    }

    var kind: Kind
    /// Author and licence, or the name of the source.
    var text: String
    var url: URL?
}

/// A portrait on Wikimedia Commons.
struct PersonPortrait: Codable, Equatable, Sendable {
    /// A file about 1200 points wide.
    var url: URL
    /// The file page on Commons.
    var page: URL?
}

/// A Wikidata item that a search found.
struct PersonMatch: Codable, Equatable, Hashable, Identifiable, Sendable {
    var qid: String
    var name: String
    var description: String?
    var id: String { qid }
}

/// The facts of one person, from Wikidata, Wikipedia and Commons.
struct PersonFacts: Codable, Equatable, Identifiable, Sendable {
    var qid: String
    var name: String
    /// The Wikidata description as Wikidata wrote it. It can hold years.
    var description: String?
    var born: Int?
    var died: Int?
    /// The start of the work period (P2031).
    var activeFrom: Int?
    /// The lead of the Wikipedia article.
    var bio: String?
    var portrait: PersonPortrait?
    var credits: [PersonCredit] = []
    var id: String { qid }

    /// "1685–1750", "born 1950", or nil when Wikidata knows no year.
    var years: String? {
        switch (born, died) {
        case (let born?, let died?): "\(born)–\(died)"
        case (let born?, nil): "born \(born)"
        case (nil, let died?): "died \(died)"
        case (nil, nil): nil
        }
    }

    /// The Wikidata description without years, then the years, joined by a comma (ADR 0017).
    /// Wikidata repeats the years in some descriptions only, so they come out of the text first.
    var descriptionLine: String? {
        let text = description.map(Self.withoutYears) ?? ""
        let line = [text, years].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
        return line.isEmpty ? nil : line
    }

    /// Takes a bracket with a four-digit year, and a trailing span of years, out of a description.
    static func withoutYears(_ text: String) -> String {
        var result = text
        let patterns = [
            #"\s*[\(\[][^\(\)\[\]]*\b\d{4}\b[^\(\)\[\]]*[\)\]]"#,
            #"[\s,;]*\b(?:c\.|ca\.|born|b\.|died|d\.)?\s*\d{3,4}\s*[–—-]\s*(?:c\.|ca\.)?\s*\d{0,4}\s*$"#,
        ]
        for pattern in patterns {
            guard let expression = try? Regex(pattern) else { continue }
            result = result.replacing(expression, with: "")
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ",;")))
    }
}

/// Reads person facts from Wikidata, Wikipedia and Wikimedia Commons. It takes the fetch closure of the
/// MusicBrainz code, so that tests stub it. A missing part gives nil. A failed request throws.
struct PersonFactsService: Sendable {
    static let wikidata = URL(string: "https://www.wikidata.org/w/api.php")!
    static let commons = URL(string: "https://commons.wikimedia.org/w/api.php")!
    static let wikipedia = URL(string: "https://en.wikipedia.org/api/rest_v1/page/summary/")!
    /// Wikidata items of occupation "composer".
    static let composerOccupation = "Q36834"

    /// Hosts that a link or a picture from Wikimedia JSON may point to. The JSON is untrusted: a URL outside
    /// this list is dropped, so that no request leaves the app for a host that a page editor chose.
    static let trustedHosts: Set<String> = [
        "upload.wikimedia.org", "commons.wikimedia.org", "en.wikipedia.org", "www.wikidata.org",
    ]
    /// The seconds that one request may take.
    static let timeout: TimeInterval = 15

    var fetch: MusicBrainz.Fetch = MusicBrainz.network
    var pacer = Pacer.wikidata

    /// The URL when it is https and its host is on the list, else nil.
    static func trusted(_ url: URL?) -> URL? {
        guard let url, url.scheme?.lowercased() == "https", let host = url.host?.lowercased(),
            trustedHosts.contains(host)
        else { return nil }
        return url
    }

    private static func request(_ url: URL) -> URLRequest {
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.setValue(MusicBrainz.userAgent, forHTTPHeaderField: "User-Agent")
        return request
    }

    /// Composers by name. The search takes the occupation as a filter, so that "Strauss" finds composers only.
    func composers(named name: String) async throws -> [PersonMatch] {
        let text = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return [] }
        // Quotes make the name one phrase, so that search syntax in a tag stays text.
        let phrase = text.filter { $0 != "\"" && $0 != "\\" }.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !phrase.isEmpty else { return [] }
        return try await matches(search: "\"\(phrase)\" haswbstatement:P106=\(Self.composerOccupation)")
    }

    /// The person of a MusicBrainz artist ID, found by P434. This does not read an ID from the tags.
    func person(musicBrainzArtist id: String) async throws -> PersonMatch? {
        guard UUID(uuidString: id) != nil else { return nil }
        return try await matches(search: "haswbstatement:P434=\(id.lowercased())").first
    }

    /// The facts, the bio and the portrait of one item.
    func facts(qid: String) async throws -> PersonFacts? {
        guard Self.isQID(qid) else { return nil }
        let data = try await get(
            Self.wikidata,
            [
                .init(name: "action", value: "wbgetentities"), .init(name: "ids", value: qid),
                .init(name: "props", value: "labels|descriptions|claims|sitelinks"),
                .init(name: "languages", value: "en"), .init(name: "sitefilter", value: "enwiki"),
                .init(name: "format", value: "json"),
            ])
        guard let entity = Self.entity(qid, in: data) else { return nil }
        var facts = Self.parse(entity, qid: qid)
        facts.credits.append(
            PersonCredit(kind: .facts, text: "Wikidata, CC0", url: URL(string: "https://www.wikidata.org/wiki/\(qid)")))
        if let title = Self.wikipediaTitle(entity) {
            // The text and the picture are extras: a failure there leaves the facts.
            if let summary = try? await bio(title: title) {
                facts.bio = summary.text
                facts.credits.append(
                    PersonCredit(kind: .text, text: "Wikipedia, CC BY-SA 4.0", url: summary.page))
            }
        }
        if let file = Self.pictureFile(entity), let found = try? await portrait(file: file) {
            facts.portrait = found.portrait
            facts.credits.append(found.credit)
        }
        return facts
    }

    // MARK: Search

    private func matches(search: String) async throws -> [PersonMatch] {
        let data = try await get(
            Self.wikidata,
            [
                .init(name: "action", value: "query"), .init(name: "list", value: "search"),
                .init(name: "srsearch", value: search), .init(name: "srlimit", value: "10"),
                .init(name: "format", value: "json"),
            ])
        let titles = Self.searchTitles(data).filter(Self.isQID)
        guard !titles.isEmpty else { return [] }
        let labels = try await get(
            Self.wikidata,
            [
                .init(name: "action", value: "wbgetentities"), .init(name: "ids", value: titles.joined(separator: "|")),
                .init(name: "props", value: "labels|descriptions"), .init(name: "languages", value: "en"),
                .init(name: "format", value: "json"),
            ])
        return titles.compactMap { qid in
            guard let entity = Self.entity(qid, in: labels) else { return nil }
            let parsed = Self.parse(entity, qid: qid)
            return PersonMatch(qid: qid, name: parsed.name, description: parsed.description)
        }
    }

    private func bio(title: String) async throws -> (text: String, page: URL?)? {
        // A title is one path segment: a slash in it is text.
        let segment = title.replacingOccurrences(of: " ", with: "_")
            .addingPercentEncoding(withAllowedCharacters: Self.segmentCharacters)
        guard let segment, let url = URL(string: Self.wikipedia.absoluteString + segment) else { return nil }
        let request = Self.request(url)
        await pacer.wait()
        let (data, status) = try await fetch(request)
        if status == 404 { return nil }
        guard (200..<300).contains(status) else { throw MusicBrainz.Failure.http(status) }
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let text = (object["extract"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
            !text.isEmpty
        else { return nil }
        let page = ((object["content_urls"] as? [String: Any])?["desktop"] as? [String: Any])?["page"] as? String
        return (text, Self.trusted(page.flatMap { URL(string: $0) }))
    }

    private func portrait(file: String) async throws -> (portrait: PersonPortrait, credit: PersonCredit)? {
        let data = try await get(
            Self.commons,
            [
                .init(name: "action", value: "query"), .init(name: "titles", value: "File:\(file)"),
                .init(name: "prop", value: "imageinfo"), .init(name: "iiprop", value: "url|extmetadata"),
                .init(name: "iiurlwidth", value: "1200"), .init(name: "format", value: "json"),
            ])
        return Self.parsePortrait(data)
    }

    private static let segmentCharacters = CharacterSet.urlPathAllowed.subtracting(CharacterSet(charactersIn: "/"))

    private func get(_ base: URL, _ items: [URLQueryItem]) async throws -> Data {
        let request = Self.request(base.appending(queryItems: items))
        await pacer.wait()
        let (data, status) = try await fetch(request)
        guard (200..<300).contains(status) else { throw MusicBrainz.Failure.http(status) }
        return data
    }

    // MARK: Parsing

    static func isQID(_ text: String) -> Bool {
        text.count > 1 && text.hasPrefix("Q") && text.dropFirst().allSatisfy(\.isASCII)
            && text.dropFirst().allSatisfy(\.isNumber)
    }

    static func searchTitles(_ data: Data) -> [String] {
        let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        let hits = (object?["query"] as? [String: Any])?["search"] as? [[String: Any]]
        return (hits ?? []).compactMap { $0["title"] as? String }
    }

    static func entity(_ qid: String, in data: Data) -> [String: Any]? {
        let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        let entity = (object?["entities"] as? [String: Any])?[qid] as? [String: Any]
        return entity?["missing"] == nil ? entity : nil
    }

    static func parse(_ entity: [String: Any], qid: String) -> PersonFacts {
        func text(_ key: String) -> String? {
            ((entity[key] as? [String: Any])?["en"] as? [String: Any])?["value"] as? String
        }
        let claims = entity["claims"] as? [String: Any] ?? [:]
        func value(_ property: String) -> Any? {
            // A preferred statement wins; else the first that is not deprecated.
            let statements = (claims[property] as? [[String: Any]])?.filter { $0["rank"] as? String != "deprecated" }
            let best = statements?.first { $0["rank"] as? String == "preferred" } ?? statements?.first
            return ((best?["mainsnak"] as? [String: Any])?["datavalue"] as? [String: Any])?["value"]
        }
        func year(_ property: String) -> Int? {
            guard let object = value(property) as? [String: Any] else { return nil }
            // Precision 9 is a year. A decade or a century (8, 7) would show a wrong year.
            if let precision = object["precision"] as? Int, precision < 9 { return nil }
            return (object["time"] as? String).flatMap { YearSpan.year(of: $0) }
        }
        return PersonFacts(
            qid: qid, name: text("labels") ?? qid, description: text("descriptions"), born: year("P569"),
            died: year("P570"), activeFrom: year("P2031"))
    }

    static func pictureFile(_ entity: [String: Any]) -> String? {
        let statements = (entity["claims"] as? [String: Any])?["P18"] as? [[String: Any]]
        let usable = statements?.filter { $0["rank"] as? String != "deprecated" }
        let best = usable?.first { $0["rank"] as? String == "preferred" } ?? usable?.first
        return ((best?["mainsnak"] as? [String: Any])?["datavalue"] as? [String: Any])?["value"] as? String
    }

    static func wikipediaTitle(_ entity: [String: Any]) -> String? {
        ((entity["sitelinks"] as? [String: Any])?["enwiki"] as? [String: Any])?["title"] as? String
    }

    static func parsePortrait(_ data: Data) -> (portrait: PersonPortrait, credit: PersonCredit)? {
        let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        let pages = (object?["query"] as? [String: Any])?["pages"] as? [String: Any]
        guard let page = pages?.values.first as? [String: Any],
            let info = (page["imageinfo"] as? [[String: Any]])?.first,
            let link = (info["thumburl"] as? String) ?? (info["url"] as? String),
            let url = trusted(URL(string: link))
        else { return nil }
        let meta = info["extmetadata"] as? [String: Any] ?? [:]
        func field(_ key: String) -> String? {
            (meta[key] as? [String: Any])?["value"] as? String
        }
        let author = field("Artist").map(plain).flatMap { $0.isEmpty ? nil : $0 }
        let licence = field("LicenseShortName").map(plain).flatMap { $0.isEmpty ? nil : $0 }
        let filePage = trusted((info["descriptionurl"] as? String).flatMap { URL(string: $0) })
        let text = [author ?? "Unknown author", licence, "Wikimedia Commons"].compactMap { $0 }.joined(separator: ", ")
        return (PersonPortrait(url: url, page: filePage), PersonCredit(kind: .picture, text: text, url: filePage))
    }

    /// Commons gives the author as HTML, sometimes as a file name. This keeps the words.
    static func plain(_ html: String) -> String {
        let text = decodeEntities(html.replacing(try! Regex("<[^>]*>"), with: ""))
            .replacing(try! Regex(#"\s+"#), with: " ")
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// One pass, so that "&amp;lt;" comes out as "&lt;" and not as "<".
    static func decodeEntities(_ text: String) -> String {
        let named = ["amp": "&", "quot": "\"", "apos": "'", "lt": "<", "gt": ">", "nbsp": " "]
        var result = ""
        var rest = Substring(text)
        while let ampersand = rest.firstIndex(of: "&") {
            result += rest[..<ampersand]
            let tail = rest[rest.index(after: ampersand)...]
            guard let end = tail.firstIndex(of: ";"), tail.distance(from: tail.startIndex, to: end) <= 8 else {
                result.append("&")
                rest = tail
                continue
            }
            let name = String(tail[..<end])
            var decoded: String?
            if name.hasPrefix("#x") || name.hasPrefix("#X") {
                decoded = UInt32(name.dropFirst(2), radix: 16).flatMap(Unicode.Scalar.init).map { String($0) }
            } else if name.hasPrefix("#") {
                decoded = UInt32(name.dropFirst()).flatMap(Unicode.Scalar.init).map { String($0) }
            } else {
                decoded = named[name]
            }
            if let decoded {
                result += decoded
                rest = tail[tail.index(after: end)...]
            } else {
                result.append("&")
                rest = tail
            }
        }
        return result + rest
    }
}
