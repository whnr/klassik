# Search

Rules for `search.html`. The terms **search term**, **condition**, **scope**, **recent search** and **search session** are in `CONTEXT.md`.

## Field and results

- The field sits at the top of the Search page, under the back arrow, with no large title. Only the results scroll.
- Beside the field: the Filters button, then an x pill. The x pill clears the text and every condition. The x in the field clears the text only. The x pill stays in place when there is nothing to clear.
- Every keyboard covers the tab bar, mini player and timeline. They keep their position.
- The field finds composers, performers, works and albums. The results show in that order, in sections by kind. A composer who also performs shows once, under Composers.
- Albums match on their name, artist and track titles, so a recording without a work tag is found through its album. Every matching recording shows under Albums, with its fermata when it is a favourite. Each row opens its recording page.
- Search shows no hidden-work count.
- Matching folds case and diacritics and matches word starts. It has no list of catalogue prefixes and no aliases.

## Filters

- Filters opens the conditions in a sheet at the medium detent and closes the keyboard as the sheet rises. The sheet rides on the keyboard only for its own field.
- The sheet is modal: native dimming, and the page behind takes no taps. Results still update behind it.
- The sheet has its own Back, the word "Back" before its title, because the sheet blocks the back arrow of the page. Back closes Filters, then returns to the page before Search. Leaving Search closes Filters; a return never restores an open sheet.
- The sheet lists the search terms of one scope at a time, with a field to narrow the list. Each term shows what a tap does and the recordings that remain: "and n", "or n", or a check. A pick clears the narrowing field.
- A condition has an "or" control. When it is on, the next term joins that condition with "or". Otherwise a term starts a new condition with "and".
- The counts use only the recordings that the text found. A term that leaves no recording does not show. The picker hides a genre that every recording with a genre carries, such as Classical.
- The query and the conditions stay when the sheet closes. A badge on Filters counts the conditions.

## Recent searches

- The empty Search page lists recent searches, newest first, with a Clear button. Klassik shows no suggestions: it has no content that the listener does not already know.
- A recent search shows its text and its conditions. A tap restores both.
- Enter, Done on the filters, opening a result and leaving the page commit the search session. Each commit replaces the entry of the session. The x pill commits, then ends the session.
- Back from a result keeps the search. A tab or a link opens Search empty.
- Recent searches stay on the device. They do not go to the server.
