# 0018. The system back stack, with the name of the page behind

Date: 2026-11-04. Decided by Flo after one prototype round and research. Bead: sz-rs30.1.74.11. For the tab places, the rule of no custom back button is replaced by [0029](0029-search-at-the-top.md).

## Context

A listener walks a graph: composer, work, recording, performer, album, and on to another work. A stack can grow ten pages deep. The iOS back button has a long-press menu that lists the stack, but most people do not find it. iOS 26 removed the name of the previous page from the back button, so a listener cannot see where Back goes.

Round 1 tried a title menu, breadcrumbs, a path sheet and the pages behind as edges. Research turned the question around:

- People hold about four things in working memory. They do not track depth. They remember a page they want to return to.
- Most returns go one or two steps back. Users think of Back as a list of recent pages.
- Breadcrumbs show the location of a page in a hierarchy, not the path that a listener walked. A walked path is long and repeats itself.
- Klassik already has three ways back: the swipe from the edge (one step), the mini player (what plays), and a second tap on the tab (its root).

## Decision

- Each place keeps the system `NavigationStack` with its back button, its swipe from the edge and its long-press menu.
- The back button shows the name of the page behind it. This is the only addition.
- A link to a page that is already in the stack goes back to it (settled in sz-rs30.1.74.4).
- A one-time TipKit tip tells the listener to hold the back button to go back further.
- No breadcrumbs, no depth count, no title menu, no custom back button. A custom back button loses the long-press menu and the swipe.

## Consequences

- Every page needs a short name for the back button and the long-press menu, such as "Beethoven" or "Karajan, 1962". The long-press menu takes its names from the back button title, not from the navigation title.
- The tracer must first check on an iPhone with iOS 26 that the system back button can show the name. If it cannot, Flo decides again.
