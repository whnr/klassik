# 0031. No separator glyph: prose, words and role lines

Date: 2026-11-09. Decided by Flo after specimen round 15 on the phone. Bead: sz-rs30.1.83.16.

## Context

The specimen joined facts with a middle dot everywhere: "1972 · Dvořák Symphonies", "Recordings · 3", "Allegro · 4:12". Flo found it overused and not elegant. A dot also says nothing about how two facts relate. Names joined with commas break when a role follows a name or when a library tags the sort form ("Kubelík, Rafael").

## Decision

- No separator glyph in the app: no middle dot, pipe, slash or spaced dash between facts.
- **Facts are prose.** A recording row reads "Recorded in 1972 on Dvořák Symphonies. 42 minutes, 4 movements." The player header has the same line without the album. "Recorded in" stays until a better source for the recording year exists.
- **Durations in prose** round to the nearest minute, never under one: 41:58 is "42 minutes"; an hour and more is "1 hour 48 minutes". The timeline and the rows keep exact times.
- **Counts are words.** The noun follows the place: movements in a work or recording, tracks on an album, works for a composer, recordings for a performer. A person in search gets one count for each role, the biggest first: "Conductor on 212 recordings, composer of 30 works and violinist on 3 recordings".
- **A section heading** takes its count in parentheses, a step lighter: "Recordings (23)".
- **Short facts** join with a comma: "Joseph Haydn, composed 1796", "Czech composer, 1841–1904", "Kubelík, 1972".
- **Names** in the page header and in an opened row stand one line per role, behind a small-cap label: "conductor Rafael Kubelík". The album in the player header is one more labelled line. The header centres the lines. A row aligns them on the leading edge. Names never line up in a label column.
- **Label type:** lowercase text set as true small caps (`lowercaseSmallCaps`), at the size of the names, tracked +0.06 em, in secondary colour. A no-break space of about 0.45 em ties it to the first name. At accessibility sizes the label stands above its names.
- **Names in one role** join with commas and "and". When a name in the role holds a comma, each name takes its own line, with the label repeated. Names without a role go last, unlabelled.
- **The scrub label** has two lines: the movement, then the time. It follows the finger but stays whole on screen.
- A number never wraps away from its word or prefix (ADR 0030).

## Consequences

- Most text needs localised plural rules and list formatting: String Catalog plurals and `ListFormatter`.
- Free role tags become labels as tagged. Klassik does not translate or pluralise them.
- An ensemble shows "founded" only when its founding year is available. The specimen data has none yet.
