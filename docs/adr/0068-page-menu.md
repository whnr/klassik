# 0068. One menu at the top right of a page

Date: 2026-11-21. Status: Proposed by code; Flo decides. Bead: sz-rs30.1.105.33.10.
Extends [0008](0008-offline-storage.md) with the place of the per-page download.

## Context

Flo, 2026-11-21: "the ugly downloads button will move to a multi functional three dots menu in the top right.
That might hold more than just the download button […] It might show up in many places."

Flo also removed the download mark from rows and kept the Download swipe (sz-rs30.1.105.33.7).
Held PR #127 already puts a "More" menu into the bar of the recording and album page.
It holds Tags and Grouping, then the download with its state.
A row already has a long-press menu with Play, Play Next, Add to Queue, Download and Favourite.
Swipe Actions puts two of these actions on each edge of a row.

## Decision

### One component

- The page menu is one SwiftUI `Menu` in `ToolbarItem(placement: .topBarTrailing)`.
  Its label is `Label("More", systemImage: "ellipsis")`; iOS draws it as a glass circle.
- Every page uses the same component. The page gives it the thing it shows: a recording, an album or a work.
- A page without a thing to act on shows no button. The menu is never empty and never dimmed as a whole.
- The back button stays at the left and the menu at the right. The bar shows no title (ADR [0023](0023-no-title-in-the-bar.md)).
  The menu stays in the bar when the large title scrolls away.

### Pages

| Page | Menu |
| --- | --- |
| Recording page | Download section; Play Next, Add to Queue; Tags and Grouping |
| Album page | Download section; Play Next, Add to Queue |
| Work page | Play Next, Add to Queue of the top recording. No Download: a work has several recordings (0008). |
| Player overlay | Download section; Tags and Grouping of what plays. No queue actions: the item plays. |
| Playlist page | None: Klassik has no playlists. A playlist page would take the album menu. |
| Composer and performer pages | None. A person has no download, and the fermata favourites the person. |
| Library, Chronology, Search | None. Library keeps Edit and the Settings cog. |
| Composers, Performers, Albums, Favourites | None. Each row has its swipes and its long-press menu. |
| Settings and its pages, Tags, Local Storage | None. |

The work page keeps its separate Edit button for the favourite order.

### Order

Sections from the top, separated by the system band:

1. Download, in one of its states.
2. Play Next, Add to Queue.
3. Tags and Grouping.

The order is fixed. A state changes the words in the first section, never its place.

### Download states

| State | Section header | Item |
| --- | --- | --- |
| Not downloaded | none | Download, with the size as subtitle |
| Downloading | "Downloading, 42 %" | Cancel Download |
| Downloaded | "Downloaded, 250 MB" | Remove Download, destructive (red) |
| Not downloaded, server out of reach | none | Download, dimmed, subtitle "Needs the server" |
| Downloading, server out of reach | "Downloading, waits for the server" | Cancel Download |
| Album, some recordings downloaded | none | Download, subtitle "2 of 5 recordings downloaded"; it downloads the rest |

- The menu reads the state when it opens. It does not change while it is open.
- Remove Download asks no question. The server can supply the files again.
- A failed download keeps no files (0008). The menu shows Download again.
  The failure shows in the one quiet server status (ADR [0058](0058-one-quiet-server-status.md)), never in an alert.
- The button carries no download mark or progress ring. Local Storage lists the downloads.

### Swipes and the long-press menu

- A swipe is a shortcut on a row. Swipe Actions chooses it. It does not change the page menu.
- The page menu holds the same actions as the long-press menu of a row for the same thing.
  It leaves out Play, because the page has its Play button. It adds what only a page has, such as Tags and Grouping.
- Both menus use the same words and SF Symbols:
  `arrow.down.circle`, `xmark.circle`, `trash`, `text.line.first.and.arrowtriangle.forward`,
  `text.line.last.and.arrowtriangle.forward` and `tag`.

### Left out

- Favourite: the fermata beside the title is the one control.
- Share: a link points at a private server, so nobody else can open it.
- Shuffle: Flo removed it until after 1.0.
- About on a person page: it stays on the page.

### Accessibility

- The button reads "More, button". VoiceOver reads each item with its subtitle: "Download, 250 megabytes".
  It reads the section header before its item, and "dimmed" for an item that cannot act now.
- The system menu takes Dynamic Type; subtitles wrap at accessibility sizes. The button keeps the 44 point hit target.
- After a choice the focus goes back to the button. A tap beside the open menu closes it and reaches nothing below.
- UI tests find the button by the identifier `page-menu` and each item by its label.

## Consequences

- PR #127 is the first page menu. After Flo decides, a follow-up makes it match:
  Download first, the queue section, the album and player menus, and the identifier `page-menu`.
- No download row stays on any page. The page menu and the row actions are the only ways to download.
- The specimen shows the proposal as the variant `page-menu` and the page `menu.html`.
  When Flo decides, the component moves into the decided specimen files and the variant goes.
