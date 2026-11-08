# 0025. The search field finds; filters open in a sheet

Date: 2026-11-07. Decided by Flo after the third specimen round. Beads: sz-rs30.1.83.7, sz-rs30.1.95. The bottom row is replaced by [0029](0029-search-at-the-top.md).

## Context

The search of sz-rs30.1.74.5 built conditions from lists of search terms. On the phone, Flo found no way to reach the works that match: the page switched between term lists and results. The bottom stack of mini player, scope chips and field was crowded. Round 3 kept the conditions of ADR 0020 and tried three places for them: a sheet, a panel above the results, and chips with a page per condition.

## Decision

- The search field finds works, composers and performers, and albums. The results show in sections by kind, in that order. A work opens its work page, a person their person page, an album its album page.
- Albums match on their name, artist and track titles, so a recording without a work tag is found through its album.
- A Filters button sits next to the field. It opens the conditions of ADR 0020 in a sheet at the medium detent. The results stay live above the sheet.
- The sheet lists the search terms of one scope at a time, with its own field to narrow the list. Each term shows what a tap does and the recordings that remain: "and n", "or n", or a check.
- A condition has an "or" control. When it is on, the next term joins that condition with "or". Otherwise a term starts a new condition with "and".
- The query and the conditions stay when the sheet closes. A badge on the Filters button counts the conditions while the sheet is closed.
- The picker hides a genre that every recording with a genre carries, such as Classical.
- The search page has one bottom row. While the keyboard is open, only the field and the Filters button show, on top of the keyboard.
- This replaces the term lists and scope chips of sz-rs30.1.74.5. ADR 0020 stays.

## Consequences

- The panel and the chips lose. Flo liked the chips, but they were too hard to understand.
- Matching and ranking rules are open until after 1.0 (sz-rs30.1.95). The tracer folds case and diacritics and matches word starts. It adds no list of catalogue prefixes and no aliases.
- Round 3 showed the mini player as a cover button in the bottom row. The mini player ticket sz-rs30.1.83.9 decides it.
- The specimen did not prove that the bar rides on the iOS keyboard. The tracer checks it on a device.
- Layout, colours and type are not decided here.
