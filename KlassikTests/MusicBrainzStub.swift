import Foundation

@testable import Klassik

/// Answers MusicBrainz and Wikidata requests from trimmed real responses, keyed as the UI-test stub keys them.
/// Records each request, so tests can count them.
final class MusicBrainzStub: @unchecked Sendable {
    private let lock = NSLock()
    private var bodies: [String: [(status: Int, body: String)]]
    private(set) var requests: [String] = []

    init(_ bodies: [String: String] = MusicBrainzStub.recorded) {
        self.bodies = bodies.mapValues { [(200, $0)] }
    }

    /// Answers the next request for this key with this status first, as a busy server does.
    func fail(_ key: String, status: Int) {
        lock.withLock { bodies[key, default: []].insert((status, ""), at: 0) }
    }

    var fetch: MusicBrainz.Fetch {
        { request in
            let key = Enrichment.stubKey(request.url!)
            return self.lock.withLock {
                self.requests.append(key)
                guard var answers = self.bodies[key], !answers.isEmpty else { return (Data(), 404) }
                let answer = answers.count > 1 ? answers.removeFirst() : answers[0]
                self.bodies[key] = answers
                return (Data(answer.body.utf8), answer.status)
            }
        }
    }

    var musicBrainz: MusicBrainz { MusicBrainz(fetch: fetch, pacer: Pacer(interval: 0)) }
    var wikidata: Wikidata { Wikidata(fetch: fetch, pacer: Pacer(interval: 0)) }

    static let vivaldi = "ad79836d-9849-44df-8789-180bbc823f3c"
    static let chopin = "09ff1fe8-d61c-4b98-bb82-18487c74d7b7"
    static let summer = "4f9cffd7-ed5c-3454-a62d-882b04bcabd0"
    static let summerFirstMovement = "e87e8a60-4453-3070-8a05-0203d776a363"
    static let etude = "3c6f04d7-dca0-3f06-b603-0d9d8cecdb27"
    static let nocturne = "71085559-a222-4061-96f6-438bd7cef3b0"

    /// Trimmed from musicbrainz.org and query.wikidata.org. MusicBrainz data is CC0.
    /// The second KK IVa/16 match and the IDs of works that no test looks up are made up.
    static let recorded: [String: String] = [
        "work/\(summer)": """
        {"id":"\(summer)","title":"Concerto in G minor, op. 8 no. 2, RV 315 “L’estate”","relations":[
          {"type":"composer","direction":"backward","begin":"1723","end":"1723","artist":{"id":"\(vivaldi)","name":"Antonio Vivaldi"}},
          {"type":"parts","direction":"forward","attributes":["movement"],"work":{"id":"\(summerFirstMovement)","title":"I. Allegro non molto"}},
          {"type":"parts","direction":"backward","attributes":["part of collection"],"work":{"id":"87886dcf-9776-49cb-b6f5-10104da6e42c","title":"Le quattro stagioni"}}]}
        """,
        "work/\(summerFirstMovement)": """
        {"id":"\(summerFirstMovement)","title":"Concerto in G minor, op. 8 no. 2, RV 315 “L’estate”: I. Allegro non molto","relations":[
          {"type":"composer","direction":"backward","artist":{"id":"\(vivaldi)","name":"Antonio Vivaldi"}},
          {"type":"parts","direction":"backward","attributes":["movement"],"work":{"id":"\(summer)","title":"Concerto in G minor, op. 8 no. 2, RV 315 “L’estate”"}}]}
        """,
        "work/\(etude)": """
        {"id":"\(etude)","title":"Étude in C major, op. 10 no. 1: Allegro","relations":[
          {"type":"composer","direction":"backward","begin":"1829","end":"1829","artist":{"id":"\(chopin)","name":"Fryderyk Chopin"}},
          {"type":"parts","direction":"backward","attributes":[],"work":{"id":"c7e5aab6-3d55-4b18-a63e-b4a0fb22ab72","title":"Études, op. 10"}}]}
        """,
        "work/\(nocturne)": """
        {"id":"\(nocturne)","title":"Nocturne, op. 9 no. 2","relations":[
          {"type":"composer","direction":"backward","artist":{"id":"\(chopin)","name":"Fryderyk Chopin"}}]}
        """,
        "sparql?\(nocturne)": """
        {"head":{"vars":["date"]},"results":{"bindings":[
          {"date":{"datatype":"http://www.w3.org/2001/XMLSchema#dateTime","type":"literal","value":"1833-01-01T00:00:00Z"}},
          {"date":{"datatype":"http://www.w3.org/2001/XMLSchema#dateTime","type":"literal","value":"1832-01-01T00:00:00Z"}}]}}
        """,
        "artist/\(vivaldi)": """
        {"id":"\(vivaldi)","name":"Antonio Vivaldi","type":"Person","life-span":{"begin":"1678-03-04","end":"1741-07-28","ended":true}}
        """,
        "artist/\(chopin)": """
        {"id":"\(chopin)","name":"Fryderyk Chopin","type":"Person","life-span":{"begin":"1810-03-01","end":"1849-10-17","ended":true}}
        """,
        "work?\"op. 10 no. 1\" AND artist:\"Chopin\"": """
        {"count":1,"works":[{"id":"\(etude)","score":100,"title":"Étude in C major, op. 10 no. 1: Allegro"}]}
        """,
        "work?\"op. 9 no. 2\" AND artist:\"Chopin\"": """
        {"count":5,"works":[
          {"id":"\(nocturne)","score":100,"title":"Nocturne, op. 9 no. 2"},
          {"id":"1e14127f-0686-3b29-b56f-501044d019b3","score":86,"title":"Nocturne no. 2 in E‐flat major, op. 9 no. 2: Andante"},
          {"id":"47fb07f5-d0dd-4107-9300-fa76c8a62b9d","score":83,"title":"Nocturne no. 2 in E‐flat major, op. 9 no. 2: Andante"},
          {"id":"03fe28a6-e1cd-4d79-a67c-db5651a9a359","score":74,"title":"Nocturne no. 2 in E‐flat major, op. 9 no. 2"},
          {"id":"dc7516c3-760f-40fb-9708-7739d6d059e9","score":68,"title":"Nocturne no. 2 in E‐flat major, op. 9, no. 2"}]}
        """,
        "work?\"KK IVa\\/16\" AND artist:\"Chopin\"": """
        {"count":2,"works":[
          {"id":"a7619cf9-0d62-31a5-aa0c-436edd8b7dd1","score":100,"title":"Nocturne no. 20 in C‐sharp minor “Reminiscence”, op. posth. 1 no. 16, B. 49, KKIVa/16"},
          {"id":"5f1c3b0e-5a40-4a6b-9a3e-2d1c7f0e9b11","score":96,"title":"Nocturne in C‐sharp minor, KK IVa/16 “Lento con gran espressione”"}]}
        """,
        "work?\"op. 64\" AND artist:\"Mendelssohn\"": """
        {"count":6,"works":[
          {"id":"9241f25f-c16d-38e2-b18c-18e2d7004ed5","score":100,"title":"Violinkonzert in e-Moll, op. 64: II. Andante"},
          {"id":"c230858f-8b2b-3e77-aa3e-777743980263","score":95,"title":"Violinkonzert in e-Moll, op. 64"},
          {"id":"a15328c7-f30f-3c05-8fcc-27c9f46b1b22","score":93,"title":"Violinkonzert in e-Moll, op. 64: I. Allegro molto appassionato"},
          {"id":"0c40c54e-6ea7-4ecd-8a92-93e38f0437e4","score":92,"title":"Violinkonzert in e-Moll, op. 64"},
          {"id":"6e6efb69-17ea-3687-af9c-3ba6d06f8446","score":90,"title":"Violinkonzert in e-Moll, op. 64: III. Allegretto non troppo – Allegro molto vivace"}]}
        """,
        "artist?artist:\"Frédéric Chopin\" AND type:person": """
        {"count":1,"artists":[{"id":"\(chopin)","name":"Fryderyk Chopin","score":100,"life-span":{"begin":"1810-03-01","end":"1849-10-17"}}]}
        """,
    ]
}
