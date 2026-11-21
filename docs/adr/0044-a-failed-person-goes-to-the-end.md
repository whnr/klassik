# 0044. A failed person goes to the end of the queue

Date: 2026-11-17. Decided by Flo after the 0.14.0 build. Bead: sz-rs30.1.105.83.
Replaces the retry rule of [0042](0042-wikidata-pass-in-the-background.md): "tries the same person again".

## Context

Flo expects his 400 people to sync in minutes, not hours. ADR 0042 made the pass try a failed person again
before it continued, after waits of 1, 2, 4 minutes and so on, up to one hour. So one person that always failed
blocked every person after it.

Flo's decision: "A failed person does not block: move it to the end of the queue. Stop after two failures, then
retry that person on the standard person cadence."

## Decision

- A failed person goes to the end of the queue of the pass. The pass continues with the next person.
- The pass tries one person at most two times. After the second failure it stops trying that person.
- The person then gets a due time on the standard cadence of 0042: 30, 365 or 90 days, with the random spread of
  up to 10 days. The person is not marked as checked. A later pass skips the person until that due time.
- One failure waits only for a `Retry-After` of Wikimedia. Failures in a row point to a problem of the service.
  From the second failure in a row, the pass waits 1, 2, 4 minutes and so on, at most one hour. A success
  resets the count.
- The throttle rules of 0042 stay: `Retry-After`, `maxlag` and the pace of 200 requests a minute.

### A picture that Commons did not answer

Added on 2026-11-21 for sz-rs30.1.135.4.

- When the Commons request for a picture fails, the facts are not complete. The person is not marked as checked.
- After the last failed try of a pass, such a person waits 1 hour, not the standard cadence. Each next pass
  that fails again doubles the wait, at most 24 hours. A short loss of the connection can fail both tries of a
  pass, so the first wait is short. The next pass after the wait takes the person first. A pass in the wait
  sends no request for the person. The count of failed passes is saved with the wait. A settled person loses both.
- A retry asks Commons only, for the file that the facts name. Facts from older builds do not name the file,
  so their retry loads the facts again.
- When Wikidata no longer has the item, the picture counts as read. The person settles with the old facts.

## Consequences

- One person that always fails costs the pass two requests, not hours of waits.
- A person that failed twice waits up to 100 days for its next try. Settings does not count the person as new
  while it waits.
- When the service is down, the pass still backs off, so it does not send a burst of failed requests.
- A lasting Commons failure costs each person with a picture one pass at 1, 2, 4, 8 and 16 hours, then one pass
  a day. Settings shows the pass as up to date while the persons wait.
