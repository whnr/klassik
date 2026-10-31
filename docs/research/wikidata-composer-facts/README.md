# What Wikidata and Wikipedia give a composer page

Bead: sz-rs30.1.74.2. Checked 2026-10-31 against the live APIs from Linux. Probe: `probe.py` in this folder. It downloads no image. Names come from a weak library: a composer name, nothing else.

## Answer

Wikidata and Wikipedia give a composer page a match, life dates, a bio and a portrait. They need no MusicBrainz ID. One composer name is enough.

- Match: Wikidata full-text search with the filter `haswbstatement:P106=Q36834` (occupation composer). It found a composer for 28 of 28 tagged-name variants. The first hit was right for 27. The one doubt is "Strauss": it returns Johann Strauss II, not Richard.
- Life dates: P569 (born) and P570 (died). Born date present for all 15 composers checked. A living composer has no P570.
- Short bio: the Wikidata description ("German composer (1685–1750)") costs no extra request. A longer bio: the Wikipedia `extract` of the lead section.
- Portrait: P18 gives a Commons file. 13 of 15 composers checked have one. 9 of 13 are public domain and need no credit. 4 of 13 are CC BY-SA and need a credit line.
- Cost: about 100 requests for 100 composers, plus 100 image downloads. Section "Request cost".
- Face crop: Vision `DetectFaceRectanglesRequest` runs on iOS 26 and is part of the OS. App size grows by zero. Not run here (no Apple device).

## Match from a name

Two ways were run on 28 variants (Bach, "J.S. Bach", "Bach, Johann Sebastian", Tchaikovsky, Tschaikowsky, "Chopin, Frédéric", Dvorak, Dvořák, Rachmaninov, Moussorgski, Schoenberg, "Arvo Part" and more; see `probe.py`).

| Way | Request | Hits (28 variants) | Note |
| --- | --- | --- | --- |
| A. `wbsearchentities`, then `wbgetentities`, then filter on P106 | 2 | 19 | Misses "Last, First" and "W.A. Mozart", "Strauss", "Schönberg", "Pärt". The search returns 10 items. Surname items and places fill them. The composer is not among them. |
| B. `action=query&list=search&srsearch=<name> haswbstatement:P106=Q36834` | 1 | 28 | The filter applies inside the search, so surname items do not crowd out the composer. Matches labels and aliases in all languages ("Tschaikowsky" is an alias). Handles "Chopin, Frédéric" and "Debussy, Claude". |

Use B. It is cheaper and finds more.

Pitfalls (proven):

- B ranks by relevance and popularity. "Bach" returns Johann Sebastian first, then C. P. E. Bach. "Strauss" returns Johann Strauss II first, then Richard. A tag with a surname only is ambiguous. The app must not claim a surname match as certain.
- B has no score. Auto-accept needs a rule of the app. One candidate rule: accept when B returns one item, or when the query has a given name and the label or an alias equals it. Else let the listener confirm. Not tested at scale.
- Non-composers match too: "Anonymous" returns Anonymous IV, "Unknown" and "Traditional" return composer items. "Various Artists" returns nothing. The app must skip such tags.
- Wikidata P569 for a Julian-calendar birth can differ between APIs: `wbgetentities` gave Bach 1685-03-21, SPARQL gave 1685-03-31. Show the year only.

## Life dates

- P569 and P570 have precision 11 (day) for all composers checked, 9 (year) for Hildegard of Bingen's birth. Read the year and show a range.
- Living composer: no P570 (Pärt, Glass). Show "born 1935".
- Wikidata data is CC0 (https://www.wikidata.org/wiki/Wikidata:Licensing). No credit is needed.

## Bio

- Wikidata description (`wbgetentities` `descriptions`, or SPARQL `schema:description`): "Czech composer (1841–1904)". English and German exist for the composers checked. Cheapest bio, and CC0.
- Wikipedia lead: REST `GET /api/rest_v1/page/summary/{title}` (one article per request) or Action API `prop=extracts&exintro&explaintext&exsentences=2&exlimit=20&titles=A|B|C` (20 articles per request, proven with 5). The summary also returns a thumbnail URL. The extract can start with a pronunciation and Old Style dates ("31 March [O.S. 21 March] 1685"). It needs trimming.
- Languages: the Wikidata item lists one sitelink for each language (`enwiki`, `dewiki`). Ask SPARQL for the sitelinks you want. A composer with no article in the language needs a fallback to English. Not measured for rare composers.
- Wikipedia text is CC BY-SA 4.0. It needs a hyperlink to the article as credit (Terms of Use, section on reuse: https://foundation.wikimedia.org/wiki/Policy:Terms_of_Use). The Wikidata description needs none.

## Portrait

- P18 holds a Commons file name. Link: `https://commons.wikimedia.org/wiki/Special:FilePath/<name>?width=<px>`. It redirects (302, then 301) to `thumb.wikimedia.org` and returns a JPEG. Proven with one file: width 400 returned 500 px, 76 kB. The server rounds to a size step.
- Licence and author: Commons API `prop=imageinfo&iiprop=extmetadata`, fields `LicenseShortName`, `AttributionRequired`, `Artist`, `Credit`. 50 files per request. `Artist` is HTML. The app must strip tags.
- Results for 15 composers:

| Composer | Licence | Credit needed |
| --- | --- | --- |
| Bach, Tchaikovsky, Dvořák, C. P. E. Bach, J. Strauss II, Rachmaninoff, Boulanger, Hildegard, Beethoven | Public domain | No |
| Pärt, Schoenberg, Glass | CC BY-SA 2.0 | Yes |
| Ligeti | CC BY-SA 3.0 nl | Yes |
| Zelenka, Anonymous IV | no P18 | not applicable |

- Duty for CC BY-SA: name the author, name the licence, link to the licence or the file page (https://commons.wikimedia.org/wiki/Commons:Reusing_content_outside_Wikimedia). A crop is a change. Say "cropped". A CC BY-SA image that the app changes carries CC BY-SA on the changed image. This is a reading of the licence text, not legal advice. Flo should decide.
- Living or recent composers are the likely CC BY-SA cases. Old composers are public domain. This matches the 2026 sample, not a rule.
- P18 can be a poor portrait: Bach's P18 is a PNG of the Haussmann painting. Pärt's file is a Flickr photo. The Wikipedia lead image can differ from P18. Both are free to use. P18 is the stable choice.
- A file can have several P18 values. SPARQL then returns several rows for one item. Prefer rank "preferred", else the first.
- Do not store the image in the repository. Fetch it at runtime, cache it on the device. Keep author, licence and file page URL next to the cache.

## Request limits and User-Agent

- Every request needs a descriptive User-Agent with contact information, in the form `Name/version (url-or-email) library/version`. Generic agents such as `python-requests`, `curl` and `Python-urllib` may be blocked. Source: https://foundation.wikimedia.org/wiki/Policy:Wikimedia_Foundation_User-Agent_Policy.
- Unauthenticated requests with a compliant User-Agent: 200 requests per minute, enforced per client. No identifying data: 10 per minute. At most 3 concurrent requests. Respect `Retry-After` on 429 or 503. Without it, wait 5 seconds. Source: https://www.mediawiki.org/wiki/Wikimedia_APIs/Rate_limits.
- Read requests have no hard speed limit. Make them one at a time, and use pipes (`ids=A|B`) to ask for many items. Source: https://www.mediawiki.org/wiki/API:Etiquette.
- An iOS app sets the header on `URLRequest`. All 100 probe requests passed with one such agent.
- ADR 0011 already sets one request every 1.1 seconds with a Klassik User-Agent. That is far inside 200 per minute. Keep it.
- The query service (`query.wikidata.org/sparql`) needs the same User-Agent. Its own limits (query timeout, parallel queries) were not read in the primary source. One small query ran in 0.5 s.

## Request cost for 100 composers

| Step | Requests |
| --- | --- |
| Match each name (way B) | 100 |
| Dates, description, P18 name, article links, one SPARQL query with `VALUES` of 100 Q-numbers | 1 |
| Bio extracts (20 titles each) | 5 |
| Licence and author (50 files each) | 2 |
| Portrait download (`Special:FilePath`, 2 redirects each) | 100 |

Total: 108 API requests plus 100 image downloads. At 1 request per 1.1 s the API part takes about 2 minutes.

Why SPARQL and not `wbgetentities` for step 2: `wbgetentities` cannot select properties. It returned 1.5 MB (280 kB compressed) for 5 composers. SPARQL returned 1 kB for 7. Without SPARQL, 100 composers cost 2 requests and about 5 MB on the wire.

Save requests: cache by Q-number. Look each composer up once. Ask again only when the listener asks.

## Face detection for the crop

- Vision `DetectFaceRectanglesRequest` (Swift, iOS 18.0 and later) and `VNDetectFaceRectanglesRequest` (iOS 11.0 and later) return face bounding boxes. Core Image `CIDetector` (iOS 5.0 and later) also finds faces. Sources: https://developer.apple.com/documentation/vision/detectfacerectanglesrequest, https://developer.apple.com/documentation/vision/vndetectfacerectanglesrequest, https://developer.apple.com/documentation/coreimage/cidetector. Revision 1 of the face rectangles request is marked deprecated. Use the default revision.
- Both frameworks ship with the OS. App size grows by zero. No model download.
- A cheaper path with no detector exists: `VNGenerateAttentionBasedSaliencyImageRequest` (iOS 13.0 and later) finds the salient area of a portrait.

## Unproven

- Face detection on painted and engraved portraits. Many P18 images of old composers are paintings. Needs a run on an iOS 26 simulator or device.
- Sample size: 28 name variants, 15 composers. Rare composers may lack an article, a portrait or an English description.
- Auto-accept rule for ambiguous surnames.
- Query service limits.
- Wikipedia summaries in languages other than English.
- Reading the Terms of Use and Commons licence pages as a licence rule for a crop that stays on the device.

## Sources

- Wikidata API `wbsearchentities`, `wbgetentities`, CirrusSearch keyword `haswbstatement` (https://www.wikidata.org/w/api.php, https://www.mediawiki.org/wiki/Help:CirrusSearch).
- Wikipedia REST summary and Action API extracts (https://en.wikipedia.org/api/rest_v1/, https://www.mediawiki.org/wiki/API:Query).
- Wikimedia User-Agent policy, API Etiquette, API rate limits (links above).
- Commons: Reusing content outside Wikimedia (https://commons.wikimedia.org/wiki/Commons:Reusing_content_outside_Wikimedia).
- Wikidata licensing (https://www.wikidata.org/wiki/Wikidata:Licensing).
- Apple Vision and Core Image pages (links above).
- Live probes on 2026-10-31: `probe.py`.
