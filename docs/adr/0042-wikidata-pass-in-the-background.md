# 0042. A background pass loads Wikidata for the whole library

Date: 2026-11-14. Decided by Flo in the 0.13.0 device notes. Bead: sz-rs30.1.105.62.
Replaces the rule "fetched once" of [0011](0011-enrichment.md) for the facts of persons.

## Context

Person pages load their Wikidata facts when the listener opens them. Flo wants every composer and performer of
his library loaded in the background. He also wants Klassik to find new persons fast and to ask again from time to
time, so that the facts of living people do not stay old.

## Decision

- A background pass looks up every composer tag and every performer tag of the library, after the MusicBrainz
  pass. It uses the lookup that a person page uses, so both give the same answer (ADR 0017, 0019).
- The app saves when it settled each person. A later pass takes persons without a saved check first, in library
  order, composers before performers. It then takes persons whose check is due.
- A check is due after 30 days for a living person, after 365 days for a person with a death year, and after
  90 days for a person that Wikidata does not know. The person with the longest wait goes first.
- A due person with an item gets new facts for that item. The tag keeps its item and the listener's choice.
  A due person without an item gets the lookup again.
- The pass keeps the rules of 0011: one request every 1.1 seconds for Wikidata, with a User-Agent that names
  Klassik. A person needs several requests, so a large library takes hours.
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
- Wikidata gets about 5 requests for each new person. Klassik asks for a living person once a month.
- The listener cannot start the pass by hand. It starts after the sync and the MusicBrainz pass.
- The app declares `processing` in `UIBackgroundModes` and one identifier in `BGTaskSchedulerPermittedIdentifiers`.
- 0011 keeps "fetched once" for the dates of works. Only person facts are asked for again.
