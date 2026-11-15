# 0042. A background pass loads Wikidata for the whole library

Date: 2026-11-14. Decided by Flo in the 0.13.0 device notes. Refined by Flo on 2026-11-15, before the build
reached his phone: parallel start, one person for each lookup, Wikimedia's pace and spread re-checks.
Bead: sz-rs30.1.105.62.
Replaces the rule "fetched once" and the 1.1-second pace of [0011](0011-enrichment.md) for the facts of persons.

## Context

Person pages load their Wikidata facts when the listener opens them. Flo wants every composer and performer of
his library loaded in the background. He also wants Klassik to find new persons fast and to ask again from time to
time, so that the facts of living people do not stay old.

## Decision

- A background pass looks up every composer tag and every performer tag of the library. It starts with the
  MusicBrainz pass and runs beside it. Its input is the composer and person names in the tags only. It needs no
  MusicBrainz output.
- The pass does not match Wikidata by a MusicBrainz work ID or composer ID. It searches by name, as a person
  page does when the works give no ID (ADR 0017, 0019). A tag that a person page resolved keeps its resolution.
- One lookup asks about one person. No request holds the names or items of several people, because a mixed
  answer confuses the match.
- The app saves when it settled each person. A later pass takes persons without a saved check first, in library
  order, composers before performers. It then takes persons whose check is due.
- A check is due after 30 days for a living person, after 365 days for a person with a death year, and after
  90 days for a person that Wikidata does not know. Each due time moves by a random amount of up to 10 days,
  earlier or later, so that the re-checks of a library do not fall due at once. The app saves the due time
  with the check. The person with the longest wait goes first.
- A due person with an item gets new facts for that item. The tag keeps its item and the listener's choice.
  A due person without an item gets the lookup again.
- The person requests to Wikidata, Wikipedia and Commons follow Wikimedia's own rules, not the 1.1 seconds of
  0011. That pace came from the MusicBrainz rule. The rules:
  - The User-Agent names the client, its version and a contact, and says "bot" for an automated client:
    `Klassik/<version> (https://github.com/whnr/klassik) person-facts bot`. Source: the
    [User-Agent policy](https://foundation.wikimedia.org/wiki/Policy:Wikimedia_Foundation_User-Agent_Policy).
  - Requests go one at a time, as [API:Etiquette](https://www.mediawiki.org/wiki/API:Etiquette) asks. They are
    spaced to at most 200 a minute (one every 0.3 seconds). 200 a minute is the limit for an unauthenticated
    bot with a compliant User-Agent. Wikimedia also asks for 3 concurrent requests or fewer. Source:
    [Wikimedia APIs/Rate limits](https://www.mediawiki.org/wiki/Wikimedia_APIs/Rate_limits).
  - Each Action API request carries `maxlag=5`, the value that the
    [maxlag manual](https://www.mediawiki.org/wiki/Manual:Maxlag_parameter) recommends for tasks without a
    person waiting. A lag error comes back with status 200, the code `maxlag` and a `Retry-After` header.
  - A 429, a 503 with `Retry-After` or a lag error is a throttle. All person requests then wait `Retry-After`
    seconds, at least 5 seconds. Each throttle in a row doubles the wait (exponential back-off). Both sources
    ask for at least 5 seconds when `Retry-After` is missing.
  - A 503 without `Retry-After` comes from the cache layer. The maxlag manual asks clients not to repeat it at
    once, so it counts as a failed request.
  - When a throttle wait would pass one minute, the request fails, and each request in the wait fails without
    being sent. The pass waits the longer of its own back-off below and the rest of the wait.
- The SPARQL queries for the dates of works belong to the MusicBrainz pass. They keep the rules of 0011.
- The pass runs while the app is open and as a background processing task that the system starts. The system
  stops that task when it wants the time back. The saved state lets the next pass continue.
- The pass pauses without a connection, on a metered connection and in Low Data Mode. It checks again every 30
  seconds.
- After a failed request the pass waits 1, 2, 4 minutes and so on, at most one hour, and tries the same person
  again. A failed person is not marked as checked.
- The Settings page "MusicBrainz" has a section "People from Wikidata". It shows the state (looking up with a
  count, waiting, paused with the reason, or up to date), the people checked, the new people and the due ones.
- Facts that the app saved before the Commons picture host was trusted had no picture. The saved cache has a
  version, and an older version drops its facts once. Tags and the listener's choices stay.

## Consequences

- The About tab credits and the pictures stay as ADR 0017 says. Only the time of the lookup changes.
- Wikidata gets about 5 requests for each new person. At 200 requests a minute, that is about 40 new people a
  minute: 10,000 new people take about 4 hours. Klassik asks for a living person about once a month.
- The person pass does not wait for the MusicBrainz pass, which can take much longer.
- The listener cannot start the pass by hand. It starts after the sync, together with the MusicBrainz pass.
- The app declares `processing` in `UIBackgroundModes` and one identifier in `BGTaskSchedulerPermittedIdentifiers`.
- 0011 keeps "fetched once" for the dates of works. Only person facts are asked for again.
