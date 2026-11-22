import Foundation

/// What one source says about one picture, text or fact, for the About tab.
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

    /// The words before the link of an About credit line. With a link, the link names Commons for a picture.
    func lead(linked: Bool) -> String {
        "\(kind.title): \(source(linked: linked))."
    }

    /// The author and licence. With a link, the link names Commons for a picture, so the text does not.
    func source(linked: Bool) -> String {
        let commons = ", Wikimedia Commons"
        return linked && kind == .picture && text.hasSuffix(commons) ? String(text.dropLast(commons.count)) : text
    }

    /// The label of the link, as person.html words it.
    func linkLabel(_ url: URL) -> String {
        switch kind {
        case .picture: "Wikimedia Commons"
        case .text: "Article"
        case .facts: url.lastPathComponent
        }
    }
}

/// A portrait on Wikimedia Commons.
struct PersonPortrait: Codable, Equatable, Sendable {
    /// A Commons thumbnail 1280 pixels wide, or the original when it is narrower.
    var url: URL
    /// The file page on Commons.
    var page: URL?
    /// The original file and its size in pixels. Facts stored before the app read them have none.
    var original: URL?
    var width: Int?
    var height: Int?

    /// Width over height, when Commons gave the size.
    var aspect: CGFloat? {
        guard let width, let height, width > 0, height > 0 else { return nil }
        return CGFloat(width) / CGFloat(height)
    }
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
    /// True when the item names a picture and the Commons request for it failed. Nil when Commons answered.
    var pictureUnread: Bool?
    /// The Commons file of an unread picture, so that a retry asks Commons only.
    var pictureFile: String?
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

    /// The Wikidata description without years, then the years, joined by a comma.
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

/// Paces the person requests to Wikimedia sites by Wikimedia's rules (ADR 0042). It spaces requests to 200 a
/// minute, the limit for a client with a compliant User-Agent. After a throttle it holds every request back.
actor WikimediaPacer {
    static let shared = WikimediaPacer()
    /// 60 seconds over 200 requests.
    static let interval = Duration.milliseconds(300)
    /// Wikimedia asks for at least 5 seconds after a lag error, and after a throttle without Retry-After.
    static let minimumWait = 5.0
    /// A request that would wait longer fails at once, and the caller backs off on its own scale. The hold
    /// stays: no request goes before it ends.
    static let longestWait = 60.0
    /// The longest hold a Retry-After can set. The header comes from the network, and `Duration.seconds`
    /// traps on a value that is not finite or too large.
    static let longestHold = 3600.0

    private let interval: Duration
    private let sleep: @Sendable (Duration) async -> Void
    private let now: @Sendable () -> ContinuousClock.Instant
    private var next: ContinuousClock.Instant
    private var throttles = 0

    init(
        interval: Duration = WikimediaPacer.interval,
        sleep: @escaping @Sendable (Duration) async -> Void = { try? await Task.sleep(for: $0) },
        now: @escaping @Sendable () -> ContinuousClock.Instant = { .now }
    ) {
        self.interval = interval
        self.sleep = sleep
        self.now = now
        self.next = now()
    }

    /// Waits for the request's turn. Returns false, and takes no turn, when a throttle holds requests back
    /// for longer than `longestWait`.
    func wait() async -> Bool {
        let start = max(next, now())
        let delay = start - now()
        guard delay <= .seconds(Self.longestWait) else { return false }
        next = start + interval
        if delay > .zero { await sleep(delay) }
        return true
    }

    /// The seconds until a throttle lets the next request go, or 0.
    var hold: Double {
        let (seconds, attoseconds) = (next - now()).components
        return max(0, Double(seconds) + Double(attoseconds) / 1e18)
    }

    /// Records a throttle and holds every request back for its wait. Returns the wait in seconds, or nil when
    /// the wait is longer than `longestWait` and the request must fail.
    /// The wait is Retry-After, at least 5 seconds, and doubles for each throttle in a row.
    /// A Retry-After that is not a number or is negative counts as absent. One above `longestHold` is cut to it.
    func throttled(retryAfter: Double?) -> Double? {
        throttles += 1
        let header = retryAfter.flatMap { $0.isNaN ? nil : min(max($0, 0), Self.longestHold) } ?? 0
        let wait = max(header, Self.minimumWait * Double(1 << min(throttles - 1, 10)))
        next = max(next, now() + .seconds(wait))
        guard wait <= Self.longestWait else {
            throttles = 0
            return nil
        }
        return wait
    }

    func succeeded() {
        throttles = 0
    }
}

/// Reads person facts from Wikidata, Wikipedia and Wikimedia Commons, one person at a time. A test stubs the
/// fetch closure. A missing part gives nil. A failed request throws.
struct PersonFactsService: Sendable {
    /// The body, the HTTP status and the seconds of a Retry-After header.
    struct Response: Sendable {
        var data: Data
        var status: Int
        var retryAfter: Double?
    }
    typealias Respond = @Sendable (URLRequest) async throws -> Response

    static let wikidata = URL(string: "https://www.wikidata.org/w/api.php")!
    static let commons = URL(string: "https://commons.wikimedia.org/w/api.php")!
    static let wikipedia = URL(string: "https://en.wikipedia.org/api/rest_v1/page/summary/")!
    /// Wikidata items of occupation "composer".
    static let composerOccupation = "Q36834"

    /// Hosts that a link or a picture from Wikimedia JSON may point to. The JSON is untrusted: a URL outside
    /// this list is dropped, so that no request leaves the app for a host that a page editor chose.
    /// Commons answers a scaled picture (`iiurlwidth`) with a URL on thumb.wikimedia.org, not upload.
    static let trustedHosts: Set<String> = [
        "upload.wikimedia.org", "thumb.wikimedia.org", "commons.wikimedia.org", "en.wikipedia.org",
        "www.wikidata.org",
    ]
    /// The seconds that one request may take.
    static let timeout: TimeInterval = 15

    /// The replica lag in seconds above which the Action API refuses a request, as Wikimedia recommends.
    static let maxlag = "5"
    /// Wikimedia's User-Agent policy asks for the client, its version, contact information, and "bot" for an
    /// automated client.
    static let userAgent: String = {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        return "Klassik/\(version) (https://github.com/whnr/klassik) person-facts bot"
    }()

    var respond: Respond = PersonFactsService.network
    var pacer = WikimediaPacer.shared

    init() {}

    init(respond: @escaping Respond, pacer: WikimediaPacer) {
        self.respond = respond
        self.pacer = pacer
    }

    /// A fetch without headers, as the stubs of tests and UI tests give it.
    init(fetch: @escaping MusicBrainz.Fetch, pacer: WikimediaPacer) {
        self.respond = { request in
            let (data, status) = try await fetch(request)
            return Response(data: data, status: status)
        }
        self.pacer = pacer
    }

    static let network: Respond = { request in
        let (data, response) = try await URLSession.shared.data(for: request)
        let http = response as? HTTPURLResponse
        let retryAfter = http?.value(forHTTPHeaderField: "Retry-After").flatMap(Double.init)
        return Response(data: data, status: http?.statusCode ?? 0, retryAfter: retryAfter)
    }

    /// The URL when it is https and its host is on the list, else nil.
    static func trusted(_ url: URL?) -> URL? {
        guard let url, url.scheme?.lowercased() == "https", let host = url.host?.lowercased(),
            trustedHosts.contains(host)
        else { return nil }
        return url
    }

    private static func request(_ url: URL) -> URLRequest {
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
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

    /// The Wikidata item of a performer. The search runs first for items that hold a MusicBrainz artist ID
    /// (P434), then without that filter. The first search takes its first hit. The second takes a hit
    /// only when its name is the tag's name, because an unfiltered hit can be anything. Nil: no item.
    func performer(named name: String) async throws -> PersonMatch? {
        guard let phrase = Self.phrase(name) else { return nil }
        if let found = try await matches(search: "\"\(phrase)\" haswbstatement:P434").first { return found }
        let wanted = PersonFactsStore.fold(phrase)
        return try await matches(search: "\"\(phrase)\"").first { PersonFactsStore.fold($0.name) == wanted }
    }

    /// A tag as one search phrase, so that search syntax in a tag stays text.
    private static func phrase(_ name: String) -> String? {
        let text = name.filter { $0 != "\"" && $0 != "\\" }.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
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
        if let file = Self.pictureFile(entity) {
            do {
                if let found = try await portrait(file: file) {
                    facts.portrait = found.portrait
                    facts.credits.append(found.credit)
                }
            } catch {
                // A failed request is no answer: the facts stay, and the background pass asks Commons again.
                facts.pictureUnread = true
                facts.pictureFile = file
            }
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
        let (data, status) = try await send(Self.request(url))
        if status == 404 { return nil }
        guard (200..<300).contains(status) else { throw MusicBrainz.Failure.http(status) }
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let text = (object["extract"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
            !text.isEmpty
        else { return nil }
        let page = ((object["content_urls"] as? [String: Any])?["desktop"] as? [String: Any])?["page"] as? String
        let article = URL(string: "https://en.wikipedia.org/wiki/" + segment)
        return (text, Self.trusted(page.flatMap { URL(string: $0) }) ?? article)
    }

    /// The picture of a Commons file with its credit. Nil when Commons has no usable picture for the file.
    func portrait(file: String) async throws -> (portrait: PersonPortrait, credit: PersonCredit)? {
        let data = try await get(
            Self.commons,
            [
                .init(name: "action", value: "query"), .init(name: "titles", value: "File:\(file)"),
                .init(name: "prop", value: "imageinfo"), .init(name: "iiprop", value: "url|size|extmetadata"),
                .init(name: "iiurlwidth", value: "1280"), .init(name: "format", value: "json"),
            ])
        return Self.parsePortrait(data)
    }

    private static let segmentCharacters = CharacterSet.urlPathAllowed.subtracting(CharacterSet(charactersIn: "/"))

    /// An Action API request. It carries maxlag, as Wikimedia asks of clients that run without a person waiting.
    private func get(_ base: URL, _ items: [URLQueryItem]) async throws -> Data {
        let request = Self.request(base.appending(queryItems: items + [.init(name: "maxlag", value: Self.maxlag)]))
        let (data, status) = try await send(request)
        guard (200..<300).contains(status) else { throw MusicBrainz.Failure.http(status) }
        return data
    }

    /// Sends a request when the pacer allows it. A throttle (429, a 503 with Retry-After, or a maxlag error)
    /// sends it again after the pacer's wait. A long hold fails the request with 429 and sends nothing.
    /// A 503 without Retry-After comes from the cache layer, and Wikimedia asks clients not to repeat it at once.
    private func send(_ request: URLRequest) async throws -> (Data, Int) {
        while true {
            guard await pacer.wait() else { throw MusicBrainz.Failure.http(429) }
            let response = try await respond(request)
            guard Self.isThrottle(response) else {
                await pacer.succeeded()
                return (response.data, response.status)
            }
            guard await pacer.throttled(retryAfter: response.retryAfter) != nil else {
                throw MusicBrainz.Failure.http(response.status == 200 ? 503 : response.status)
            }
        }
    }

    static func isThrottle(_ response: Response) -> Bool {
        switch response.status {
        case 429: return true
        case 503: return response.retryAfter != nil
        case 200..<300: return isLagError(response.data)
        default: return false
        }
    }

    /// The Action API answers a lag above maxlag with status 200 and the error code "maxlag".
    static func isLagError(_ data: Data) -> Bool {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let error = object["error"] as? [String: Any]
        else { return false }
        return error["code"] as? String == "maxlag"
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
        let portrait = PersonPortrait(
            url: url, page: filePage, original: trusted((info["url"] as? String).flatMap { URL(string: $0) }),
            width: info["width"] as? Int, height: info["height"] as? Int)
        return (portrait, PersonCredit(kind: .picture, text: text, url: filePage))
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
