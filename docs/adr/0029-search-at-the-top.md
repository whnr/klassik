# 0029. Search at the top, with a back arrow and recent searches

Date: 2026-11-08. Decided by Flo after specimen rounds 8 and 9 on the phone. Beads: sz-rs30.1.83.13, sz-rs30.1.83.14. Replaces the bottom row of [0025](0025-search-field-and-filter-sheet.md). Replaces the rule of [0018](0018-stack-and-back.md) that adds no custom back button, for the tab places only.

## Context

ADR 0025 put the field and the Filters button in one bottom row that rides on the keyboard. With the pill of ADR 0028 in the tab row, that row was lower than the tab bar, the field was narrow, and Search had no way back. With the keyboard open, the Filters button dropped the keyboard and left a gap. A search with filters only never reached a list of past searches.

iOS 27 offers two Search tabs (WWDC26 session 292). A standard tab opens a page with the field at the top. A prominent tab opens the keyboard at once, with the field on it. Round 8 showed four places for the field. Flo chose the top.

## Decision

- The tab bar stays as on every page. The field sits at the top of the Search page, under the back arrow, with no large title. Only the results scroll.
- Beside the field: the Filters button, then an x pill. The x pill clears the text and every condition. The x in the field clears the text only. The x pill stays in place when there is nothing to clear.
- Filters closes the keyboard as the sheet rises. The sheet rides on the keyboard only for its own field.
- A pick in the filter sheet clears its narrowing field, so the listener can add the next term at once.
- The filter counts use only the recordings that the text found through works, people and albums. A term that leaves no recording does not show.
- Chronology, Settings and Search show a back arrow that names the page they were opened from and returns to it. Opened without a page behind, they go back to Library. Library has none.
- The empty Search page lists **recent searches**, newest first, with a Clear button. Klassik shows no suggestions: it has no content that the listener does not already know.
- A recent search keeps its text and its conditions and shows both. A tap restores both.
- One **search session** is one recent search. Enter, Done on the filters, opening a result and leaving the page commit it. Each commit replaces the entry of the session. The x pill commits, then ends the session.
- Back from a result keeps the search. A tab or a link opens Search empty, with the recent searches.

## Consequences

- The keyboard flow was checked in Chromium and on Flo's phone in the specimen only. The tracer checks it in SwiftUI with `searchable` in a standard tab.
- A system `TabView` gives the root of a tab no back button. The tracer adds one to the tab places and checks that it keeps the swipe from the edge.
- Recent searches are device data, like listening notes. They do not go to the server.
- The page scroll indicator runs beside the timeline, not on it (sz-rs30.1.83.14). In SwiftUI: `contentMargins` for `scrollIndicators`.
